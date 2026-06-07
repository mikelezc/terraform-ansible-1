# 04 — Servicios de AWS Usados en el Proyecto

---

## EC2 — Elastic Compute Cloud

EC2 es el servicio de computación más conocido de AWS. Cada instancia (VM) es un servidor en la nube.

### Conceptos clave

**AMI (Amazon Machine Image)**: imagen del sistema operativo. En este proyecto usamos `ubuntu-jammy-22.04-amd64` de Canonical ya que el subject nos pide Ubuntu 22.04.

**Instance type**: define CPU y RAM.
- `t3.micro`: 2 vCPU, 1 GB RAM. Free tier elegible en la mayoría de regiones.

**Key pair**: par de claves RSA para SSH. AWS guarda la clave pública; nosotros guardamos el `.pem` (clave privada). Sin él no podemos conectarnos a las máquinas.

**User data**: script que AWS ejecuta una sola vez en el primer arranque de la instancia. Es cloud-init. Lo usamos para configurar automáticamente las instancias web.

**EBS (Elastic Block Store)**: disco virtual persistente. Cada EC2 tiene un volumen EBS raíz. Si terminamos la instancia, el volumen se borra por defecto (esto es configurable). Los datos de MariaDB están en EBS de EC2-DB.

### Free Tier
750 horas/mes de t2.micro o t3.micro. Perfecto para nuestro proyecto (usaremos 4 de estas).

---

## Security Groups — Firewall a nivel de instancia

Un Security Group (SG) es un firewall virtual a nivel de instancia (no de red).

### Características clave

**Stateful**: si permites tráfico entrante desde 1.2.3.4:80, las respuestas (tráfico de salida hacia 1.2.3.4) se permiten automáticamente. No hay que definir la regla de vuelta.

**Solo "Allow"**: los SGs no tienen reglas de denegación. Si no hay una regla que permita el tráfico, se deniega.

**Todo el tráfico de salida está permitido por defecto** (en nuestra configuración explícitamente ponemos `egress { all, 0.0.0.0/0 }`).

**Las reglas de entrada pueden referenciar otros SGs**: esto es fundamental. En vez de poner "permite la IP 1.2.3.4", puedes poner "permite tráfico desde cualquier instancia que tenga el SG-LB". Si el LB cambia de IP, la regla sigue siendo válida.

### Los 4 SGs del proyecto

```
SG-LB   → internet puede llegar (80, 443). SSH solo desde nuestra IP.
SG-Web  → solo el SG-LB puede llegar (80). SSH solo desde nuestra IP.
SG-DB   → solo el SG-Web puede llegar (3306). SSH solo desde nuestra IP.
SG-EFS  → solo el SG-Web puede llegar (2049, NFS).
```

Esto mejora notablemente la seguridad de acceso a nuestras máquinas: aunque alguien llegue al LB, no puede llegar directamente a la DB.

---

## IAM — Identity and Access Management

IAM gestiona quién puede hacer qué en AWS.

### Conceptos clave

**Usuario IAM**: persona o aplicación con credenciales permanentes (Access Key + Secret). El nuestro se configura con `aws configure`.

**Rol IAM**: identidad que puede ser asumida temporalmente. No tiene credenciales fijas — genera tokens temporales. Las instancias EC2 asumen roles para acceder a servicios AWS.

**Política IAM**: documento JSON que define permisos (`Allow`/`Deny` sobre `Actions` en `Resources`).

**Instance Profile**: contenedor que vincula un Rol con una instancia EC2.

### En el proyecto

```
IAM Role "web-instance-role"
  └── IAM Policy: Allow s3:GetObject + s3:ListBucket en arn:aws:s3:::cloud1-web-config-xxxxx/*
  
EC2 Instance Profile "web-instance-profile"
  └── vincula el Role con las instancias del ASG
```

Cuando cloud-init ejecuta `aws s3 cp s3://cloud1-web-config-xxx/...`, AWS verifica que la instancia tiene un Instance Profile con permisos sobre ese bucket. No hay credenciales hardcodeadas en el script.

### Principio de mínimo privilegio
Solo los permisos estrictamente necesarios: `GetObject` y `ListBucket`, solo en el bucket de configuración. No `PutObject`, no acceso a otros buckets, no permisos de EC2 ni de nada más.

---

## EFS — Elastic File System

EFS es un sistema de archivos NFS gestionado por AWS. Se puede montar desde múltiples instancias simultáneamente.

### Por qué es necesario

WordPress guarda los uploads en el disco local (`/var/www/html/wp-content/uploads/`). Si hay dos servidores web, cada uno tiene su propio disco. Si el usuario sube una imagen en web-1, web-2 no la tiene.

EFS resuelve esto: ambos servidores montan el mismo sistema de archivos. Los uploads son inmediatamente visibles en todos los nodos.

### Cómo funciona

```
Instancia web-1                    Instancia web-2
  mount -t nfs4 efs-dns:/  →  ←  mount -t nfs4 efs-dns:/
  /home/ubuntu/data/wordpress      /home/ubuntu/data/wordpress

Los contenedores WordPress mapean:
  /var/www/html → /home/ubuntu/data/wordpress (bind mount)
```

### Mount Targets

Un Mount Target es el punto de acceso de EFS en una Availability Zone (AZ). Para que una instancia pueda montar EFS, debe existir un Mount Target en la misma AZ. Por eso creamos un Mount Target en cada subnet/AZ con `for_each`.

### Free Tier
5 GB de EFS Standard al mes. Más que suficiente para WordPress.

---

## S3 — Simple Storage Service

S3 es almacenamiento de objetos. Los objetos (archivos) se guardan en buckets (contenedores).

### Diferencia con EFS

| S3 | EFS |
|----|-----|
| Objetos (archivos inmutables) | Sistema de archivos POSIX |
| API HTTP (GET, PUT, DELETE) | Protocolo NFS (montaje) |
| Global, muy escalable | Regional, acceso de baja latencia |
| Barato para almacenamiento | Más caro, para acceso frecuente |

### Por qué usamos S3 para la configuración

Las instancias web del ASG se crean automáticamente y necesitan su configuración. S3 es el repositorio natural: Terraform sube los archivos renderizados, cloud-init los descarga con `aws s3 cp`.

### Acceso seguro

El bucket es privado (`aws_s3_bucket_public_access_block` con todo en `true`). Solo las instancias con el IAM Role pueden leer. Si alguien encontrara la URL del objeto, no podría descargarlo.

### `force_destroy = true`

Por defecto AWS no permite borrar un bucket con objetos. `force_destroy = true` hace que `terraform destroy` vacíe el bucket antes de borrarlo.

---

## Auto Scaling Group (ASG)

Un ASG gestiona automáticamente un grupo de instancias EC2 idénticas.

### Componentes

**Launch Template**: plantilla de cómo debe ser cada instancia (AMI, tipo, key pair, SG, user data). Si necesitaramos cambiar la configuración de las instancias, actualizariamos el Launch Template.

**Auto Scaling Group**: define cuántas instancias deben estar corriendo:
- `min_size`: mínimo de isntancias corriendo en paralelo (2 en este proyecto).
- `desired_capacity`: objetivo normal.
- `max_size`: máximo durante scaling.

### Health checks

Con `health_check_type = "EC2"`, el ASG comprueba los EC2 Status Checks de AWS. Si una instancia falla (hardware, instancia terminada), el ASG la marca como unhealthy, la termina y lanza una nueva.

Con `health_check_grace_period = 600`, espera 10 minutos antes de evaluar la salud. Si no esperara, terminaría la instancia mientras cloud-init todavía está corriendo.

### Escalado

**Scaling policies**: reglas de cuándo añadir o quitar instancias.
**CloudWatch Alarms**: métricas que disparan las policies (CPU > 70% → scale up).

Para la demo de escalado manual: `terraform apply -var="web_desired=4"` podemos cambiar el `desired_capacity` del ASG, que lanza 2 instancias más. Cuando terminan cloud-init, hay que re-ejecutar Ansible en el LB para que Nginx las incluya en el upstream.

---

## CloudFront — CDN

CloudFront es la red de distribución de contenido (CDN) de AWS. Tiene alrededor de 450 puntos de presencia (PoPs) en todo el mundo.

### Cómo funciona

1. Cuando un usuario pide `https://xxx.cloudfront.net/wp-content/themes/style.css`, la petición llega al PoP más cercano.
2. Si el PoP tiene el archivo en caché (`x-cache: Hit from cloudfront`), lo devuelve directamente.
3. Si no lo tiene (`x-cache: Miss from cloudfront`), lo pide al origen (el LB), lo devuelve al usuario y lo guarda en caché.

Las peticiones posteriores al mismo archivo son muy rápidas porque vienen del PoP cercano, no del servidor original.

### Distribución

Una distribución CloudFront define:
- **Origin**: de dónde obtener el contenido cuando no está en caché.
- **Behaviors**: reglas de qué cachear y por cuánto tiempo.
- **Price class**: qué PoPs usar (más caros = más globales).

En el proyecto:
- `PriceClass_100`: solo PoPs de Norteamérica y Europa (más barato).
- Origin: el Nginx LB (hostname DNS, no IP directa).
- Comportamiento `/wp-content/*`: caché 1 día.
- Comportamiento default: sin caché (WordPress es dinámico).

### Terminar HTTPS en CloudFront

CloudFront usa su propio certificado SSL válido. Los usuarios ven HTTPS sin que el LB necesite un certificado de CA. El LB recibe HTTP interno, CloudFront añade la capa HTTPS hacia el usuario.

### `WP_CONTENT_URL`

En `wp-config.php` configuramos:
```php
define('WP_CONTENT_URL', 'https://xxx.cloudfront.net/wp-content');
```

Esto hace que WordPress genere URLs de assets apuntando a CloudFront. Cuando el navegador pide el CSS, lo pide a CloudFront, que lo cachea.

---

## Elastic IP (EIP)

Una IP pública fija asociada a una instancia EC2.

### El problema que resuelve

Por defecto, una EC2 tiene una IP pública dinámica que cambia cada vez que se reinicia la instancia. CloudFront necesita un origen estable (si la IP cambia, habría que actualizar CloudFront). DuckDNS necesita apuntar a una IP fija.

### Coste

Gratis mientras está asociada a una instancia **en ejecución**. Si la instancia está parada o la EIP está desasociada, AWS cobra por ella (penaliza el "desperdicio" de IPs).

En `terraform destroy` la EIP se libera correctamente.

---

## VPC — Virtual Private Cloud

Una VPC es una red virtual privada en AWS. Todos los recursos se crean dentro de una VPC.

### VPC por defecto

AWS crea automáticamente una VPC por defecto en cada región con:
- Una subnet en cada Availability Zone.
- Internet Gateway conectado.
- Tabla de rutas que permite acceso a internet.

En el proyecto usamos la VPC por defecto para simplificar (no necesitamos crear subnets privadas, NAT Gateway, etc.). En producción real, se crearía una VPC personalizada con subnets privadas y públicas.

### Availability Zones (AZ)

Una región de AWS (como `eu-west-3` = París) tiene múltiples centros de datos físicamente separados llamados Availability Zones (`eu-west-3a`, `eu-west-3b`, `eu-west-3c`).

El ASG distribuye las instancias entre las AZs disponibles para maximizar la disponibilidad: si `eu-west-3a` tiene un problema físico, las instancias en `eu-west-3b` siguen funcionando.
