# Cloud-1: Infraestructura Multi-Servidor en AWS

Este documento es la guía completa de la arquitectura y el despliegue del proyecto Cloud-1 en su versión final: multi-servidor, con balanceo de carga, alta disponibilidad, CDN y automatización total mediante Terraform y Ansible.

---

## 1. Conceptos Fundamentales del Proyecto

La diferencia clave respecto al README anterior es que ya no levantamos **un solo servidor** con todo dentro. Ahora la infraestructura se distribuye entre varias máquinas especializadas, y todo se aprovisiona mediante **dos capas de automatización**:

### Infraestructura como Código (IaC) con Terraform

Terraform es la herramienta que nos permite describir en código HCL (HashiCorp Configuration Language) qué recursos de AWS queremos crear. Es el equivalente a un presupuesto de obra: le dices "quiero tres instancias EC2, un balanceador de carga y un sistema de ficheros compartido", y Terraform lo construye todo.

Lo más importante de Terraform es que gestiona el **estado** de tu infraestructura. Si ejecutas `terraform apply` dos veces, solo aplicará los cambios que no existan todavía. Y si ejecutas `terraform destroy`, eliminará absolutamente todo lo que creó, dejando tu cuenta de AWS limpia y sin costes.

### Configuración de Servidores con Ansible

Ansible sigue siendo la herramienta para configurar el interior de cada máquina. En esta versión, Ansible solo configura el servidor de base de datos (MariaDB), porque las instancias web se auto-configuran solas al arrancar mediante un script de `cloud-init` (más sobre esto en la sección de arquitectura).

### La regla de oro sigue siendo la misma

**1 contenedor = 1 proceso**. Los servicios que corren son:

- **Nginx**: Servidor web y *Reverse Proxy* en las instancias web.
- **WordPress (PHP-FPM)**: La aplicación en PHP.
- **MariaDB**: Base de datos, en su propia instancia EC2 dedicada.
- **phpMyAdmin**: Interfaz web de administración de la base de datos.

---

## 2. Arquitectura Completa

```
                        INTERNET
                           │
                           ▼
              ┌─────────────────────────┐
              │   AWS CloudFront (CDN)  │
              │   dominio: xxxx.cloudfront.net
              │   - HTTPS para el usuario
              │   - Caché de /wp-content/*
              └────────────┬────────────┘
                           │ HTTP (interno)
                           ▼
              ┌─────────────────────────┐
              │  Application Load       │
              │  Balancer (ALB)         │
              │  - Distribuye tráfico   │
              │  - Health checks        │
              └──────┬──────────┬───────┘
                     │          │  Round-robin
           ┌─────────┘          └─────────┐
           ▼                              ▼
  ┌────────────────┐           ┌────────────────┐
  │  EC2-Web-1     │           │  EC2-Web-2     │  ← Auto Scaling Group
  │  Ubuntu 22.04  │           │  Ubuntu 22.04  │    (mín. 2, máx. 4)
  │  Docker:       │           │  Docker:       │
  │  · Nginx       │           │  · Nginx       │
  │  · WP PHP-FPM  │           │  · WP PHP-FPM  │
  │  · phpMyAdmin  │           │  · phpMyAdmin  │
  └───────┬────────┘           └────────┬───────┘
          │                             │
          └──────────────┬──────────────┘
                         │ puerto 3306 (red privada AWS)
                         ▼
              ┌─────────────────────────┐
              │  EC2-DB                 │
              │  Ubuntu 22.04           │
              │  Docker: MariaDB        │
              │  (solo accesible desde  │
              │   las instancias web)   │
              └─────────────────────────┘

  ┌─────────────────────────────────────────────┐
  │  AWS EFS (Elastic File System)              │
  │  Montado en /home/ubuntu/data/wordpress     │
  │  en AMBAS instancias web                    │
  │  → Uploads y wp-content compartidos         │
  └─────────────────────────────────────────────┘

  ┌─────────────────────────────────────────────┐
  │  AWS S3 (bucket privado)                    │
  │  Almacena: docker-compose.yml,              │
  │  nginx.conf, .env para las instancias web   │
  │  → cloud-init lo descarga al arrancar       │
  └─────────────────────────────────────────────┘
```

### Por qué cada pieza existe

| Componente | Por qué lo necesitamos |
|---|---|
| **CloudFront** | CDN: cachea assets estáticos (CSS, JS, imágenes) cerca del usuario. Requisito obligatorio de la defensa. |
| **ALB** | Distribuye las peticiones entre las instancias web de forma automática. Necesario para que el Auto Scaling Group sepa qué instancias están sanas. |
| **Auto Scaling Group** | Mantiene siempre un mínimo de 2 instancias. Si una cae, lanza otra automáticamente. Permite escalar horizontalmente. |
| **EC2-DB separado** | El subject exige que la base de datos esté en una máquina distinta a las web. |
| **EFS** | Sistema de ficheros de red. Si subes una imagen desde la instancia web-1, también aparece en web-2. Sin esto, cada servidor tendría su propio disco y las imágenes no sincronizarían. |
| **S3** | Las instancias del Auto Scaling Group se lanzan automáticamente (sin intervención humana). Necesitan descargar su configuración de algún sitio. S3 es el repositorio centralizado. |

---

## 3. Cómo Funciona el Auto-arranque (cloud-init)

Este es el concepto más importante de esta arquitectura. Cuando el Auto Scaling Group crea una nueva instancia web (ya sea al arrancar, al escalar o al reemplazar una caída), ejecuta automáticamente el script `terraform/user_data.sh.tpl` en el primer arranque. Este script:

1. Instala Docker y las dependencias necesarias.
2. Monta el EFS en `/home/ubuntu/data/wordpress` (ficheros compartidos de WordPress).
3. Descarga `docker-compose.yml`, `nginx.conf` y `.env` del bucket S3.
4. Genera el certificado SSL auto-firmado para Nginx.
5. Arranca los contenedores con `docker compose up -d`.
6. Espera a que WordPress cree `wp-config.php` y lo parchea para que funcione con HTTPS y con el CDN de CloudFront.

Todo esto ocurre sin que el operador haga nada. El Auto Scaling Group lo gestiona solo.

---

## 4. Prerrequisitos

Antes de ejecutar cualquier cosa, necesitamos tener preparado lo siguiente en nuestra máquina local:

### Herramientas

```bash
# macOS (homebrew):
brew install terraform ansible awscli

# Ubuntu:
sudo apt update && sudo apt install -y ansible awscli
# Terraform: https://developer.hashicorp.com/terraform/install
```

### Cuenta y credenciales AWS

1. Tener una cuenta de AWS con acceso a la región `eu-west-3` (París).
2. Configurar el CLI de AWS con tus credenciales:

```bash
aws configure
# AWS Access Key ID: [tu access key]
# AWS Secret Access Key: [tu secret key]
# Default region name: eu-west-3
# Default output format: json
```

### Key pair de AWS

Las instancias EC2 necesitan un par de claves SSH para que Ansible pueda conectarse al servidor de base de datos. Si no tienes uno:

1. Ve a AWS Console → EC2 → Key Pairs → Create key pair.
2. Nómbralo `cloud-1-key`, elige formato `.pem`.
3. Guarda el fichero descargado en `~/.ssh/cloud-1-key.pem`.
4. Dale permisos correctos:

```bash
chmod 400 ~/.ssh/cloud-1-key.pem
```

> **Importante**: El key pair debe existir en la región `eu-west-3`. Si lo creaste en otra región, no funcionará.

---

## 5. Configuración Inicial (solo la primera vez)

### Paso 1: Configurar variables secretas

Entra en la carpeta `terraform/` y copia el fichero de ejemplo:

```bash
cd 42_Cloud-1/terraform
cp terraform.tfvars.example terraform.tfvars
```

Edita `terraform.tfvars` con tus valores reales:

```hcl
# Tu IP pública actual (para restringir el acceso SSH solo a tu máquina)
# Puedes obtenerla con: curl ifconfig.me
my_ip = "1.2.3.4/32"

# Nombre del key pair que creaste en AWS eu-west-3
key_name = "cloud-1-key"

# Contraseñas de la base de datos (cámbialas por unas seguras)
db_password      = "mi_password_seguro"
db_root_password = "mi_root_password_seguro"
```

> **Nunca subas `terraform.tfvars` a git.** Ya está en el `.gitignore`. Contiene tus contraseñas.

### Paso 2: Configurar credenciales de base de datos para Ansible

Ansible usará las contraseñas directamente desde el `inventory.ini` que genera Terraform automáticamente. No necesitas configurar nada adicional.

---

## 6. Despliegue Completo

### Fase 1: Infraestructura con Terraform (~20 minutos)

```bash
cd 42_Cloud-1/terraform

# Descarga los plugins de Terraform (solo la primera vez)
terraform init

# Previsualiza qué va a crear (opcional pero recomendado)
terraform plan

# Crea toda la infraestructura en AWS
terraform apply
```

Terraform te pedirá confirmación escribiendo `yes`. A continuación creará, en este orden aproximado:

1. Security Groups y roles IAM.
2. Bucket S3 y sube la configuración.
3. Sistema de ficheros EFS.
4. EC2 de base de datos.
5. ALB y target group.
6. CloudFront (esto tarda ~15 minutos, es normal).
7. Auto Scaling Group con las instancias web.
8. Genera el fichero `inventory.ini` para Ansible.

Al finalizar, verás los outputs:

```
cloudfront_domain    = "https://d1abc123xyz.cloudfront.net"
db_public_ip         = "15.188.xx.xx"
efs_dns_name         = "fs-xxxxxxxx.efs.eu-west-3.amazonaws.com"
```

La URL de CloudFront es la dirección de tu sitio.

### Fase 2: Configurar la base de datos con Ansible (~2 minutos)

Una vez Terraform ha terminado, el `inventory.ini` se ha generado automáticamente con la IP real del servidor de base de datos. Lanzamos Ansible:

```bash
cd ..  # Vuelve a la carpeta 42_Cloud-1/
ansible-playbook -i inventory.ini playbook.yml
```

Ansible se conectará al EC2 de base de datos, instalará Docker y arrancará MariaDB con las credenciales que definiste en `terraform.tfvars`.

### Fase 3: Esperar a las instancias web (~5 minutos)

Las instancias web del Auto Scaling Group se están auto-configurando en paralelo mediante el script `cloud-init`. Puedes ver el estado en:

- **AWS Console → EC2 → Auto Scaling Groups → cloud1-web-asg → Activity**.
- **AWS Console → EC2 → Target Groups → cloud1-web-tg**: cuando las instancias aparezcan en estado `healthy`, el sitio está listo.

### Fase 4: Acceder al sitio

```bash
# La URL de tu sitio:
terraform output cloudfront_domain
```

Abre esa URL en el navegador. Deberías ver WordPress funcionando con HTTPS.

---

## 7. Demos para la Defensa

### Verificar que hay 2 servidores en paralelo

Abre las herramientas de desarrollo del navegador (F12 → Network) y recarga la página varias veces. Busca la cabecera de respuesta `X-Served-By`: verás que cambia entre diferentes nombres de instancia, demostrando que cada petición va a un servidor distinto.

Alternativamente, desde terminal:

```bash
for i in $(seq 1 6); do
  curl -sk https://TU_CLOUDFRONT_DOMAIN/ -I | grep X-Served-By
done
```

### Verificar el CDN

En las herramientas de desarrollo (F12 → Network), recarga la página dos veces. En la segunda carga, los ficheros de `/wp-content/` (CSS, imágenes del tema) mostrarán la cabecera:

```
x-cache: Hit from cloudfront
```

Esto demuestra que el CDN está cacheando y sirviendo los assets estáticos.

### Verificar persistencia de sesión

1. Entra al panel de administración de WordPress: `https://TU_URL/wp-admin`.
2. Inicia sesión.
3. Recarga la página varias veces.
4. Comprueba que sigues logueado aunque el `X-Served-By` cambie entre instancias.

Esto funciona porque WordPress usa cookies firmadas con las claves de `wp-config.php`. Al ser el mismo fichero de configuración en todas las instancias (compartido via EFS), las cookies son válidas en cualquier servidor.

### Verificar sincronización de imágenes

1. Ve a WordPress Admin → Media → Añadir nueva.
2. Sube cualquier imagen.
3. Publica un artículo con esa imagen.
4. Recarga la página varias veces: la imagen aparece independientemente de qué instancia sirva la petición.

Esto funciona gracias al EFS compartido: el directorio `wp-content/uploads/` es el mismo sistema de ficheros para todas las instancias.

### Demo de escalado horizontal

```bash
cd terraform

# Escalar de 2 a 4 instancias
terraform apply -var="web_desired=4"
```

Ve a AWS Console → EC2 → Auto Scaling Groups y observa cómo se lanzan nuevas instancias. En pocos minutos el ALB las detecta como `healthy` y empieza a enviarles tráfico. El sitio permanece accesible durante todo el proceso.

Para volver a 2 instancias:

```bash
terraform apply -var="web_desired=2"
```

### Demo de alta disponibilidad

1. Ve a AWS Console → EC2 → Instances.
2. Selecciona una de las instancias `cloud1-web` y termínala (Actions → Terminate).
3. Observa que el sitio sigue funcionando: el ALB detecta la instancia caída y deja de enviarle tráfico.
4. En AWS Console → Auto Scaling Groups → cloud1-web-asg, verás cómo el ASG lanza automáticamente una nueva instancia para mantener el mínimo de 2.
5. En unos ~5 minutos, la nueva instancia aparece como `healthy` en el target group.

---

## 8. Gestión del Entorno

### Ver el estado de la infraestructura

```bash
cd terraform

# Ver todos los outputs (URL del sitio, IPs, etc.)
terraform output

# Ver el estado completo de los recursos
terraform show
```

### Reiniciar los contenedores en el servidor de base de datos

Si necesitas reiniciar MariaDB:

```bash
ssh -i ~/.ssh/cloud-1-key.pem ubuntu@$(terraform output -raw db_public_ip)
cd /home/ubuntu/db
docker compose restart
```

### Ver logs de cloud-init en instancias web

Para diagnosticar problemas en las instancias web del ASG, conéctate a una de ellas:

```bash
# Obtén la IP de una instancia web desde AWS Console
ssh -i ~/.ssh/cloud-1-key.pem ubuntu@IP_INSTANCIA_WEB
cat /var/log/cloud-init-wordpress.log
```

### Reset del entorno de base de datos (para demos)

Si quieres reiniciar solo el servidor de base de datos (borrar todo y volver a desplegar MariaDB desde cero):

```bash
cd 42_Cloud-1/
ansible-playbook -i inventory.ini reset.yml
# Y a continuación:
ansible-playbook -i inventory.ini playbook.yml
```

---

## 9. Destrucción Completa de la Infraestructura

Cuando termines con el proyecto (después de la defensa, por ejemplo), es **muy importante** destruir todos los recursos para no incurrir en costes:

```bash
cd 42_Cloud-1/terraform
terraform destroy
```

Terraform te pedirá confirmación con `yes`. A continuación eliminará **absolutamente todo** lo que creó:

- Las instancias EC2 (base de datos y todas las web del ASG).
- El ALB y el Auto Scaling Group.
- La distribución de CloudFront.
- El bucket S3 y su contenido.
- El sistema de ficheros EFS y todos los datos de WordPress.
- Los Security Groups y roles IAM.
- El `inventory.ini` local.

> **Atención**: `terraform destroy` borra los datos de WordPress de forma permanente (imágenes, artículos, usuarios). Esto es correcto y esperado en un entorno de práctica. Para entornos reales habría que hacer snapshots del EFS antes.

---

## 10. Estructura del Repositorio

```
42_Cloud-1/
│
├── terraform/                    # Infraestructura AWS como código
│   ├── main.tf                   # Provider AWS, data sources
│   ├── variables.tf              # Variables configurables
│   ├── outputs.tf                # Valores de salida (URL, IPs...)
│   ├── security_groups.tf        # Reglas de firewall (SGs)
│   ├── iam.tf                    # Permisos de instancias web → S3
│   ├── s3.tf                     # Bucket de configuración
│   ├── s3_objects.tf             # Sube docker-compose, nginx.conf, .env
│   ├── efs.tf                    # Sistema de ficheros compartido
│   ├── ec2_db.tf                 # Instancia EC2 de base de datos
│   ├── alb.tf                    # Application Load Balancer
│   ├── asg.tf                    # Auto Scaling Group + CloudWatch alarms
│   ├── cloudfront.tf             # CDN
│   ├── inventory.tf              # Genera inventory.ini para Ansible
│   ├── user_data.sh.tpl          # Script cloud-init de las instancias web
│   ├── docker-compose.web.yml.tpl # Docker Compose para instancias web
│   ├── nginx.web.conf.tpl        # Configuración Nginx de instancias web
│   ├── env_web.tpl               # Template del fichero .env
│   ├── inventory.tpl             # Template de inventory.ini
│   └── terraform.tfvars.example  # Ejemplo de variables (copiar a .tfvars)
│
├── roles/
│   ├── docker/                   # Instala Docker en el servidor de BD
│   └── database/                 # Despliega MariaDB en EC2-DB
│       ├── tasks/main.yml
│       ├── templates/
│       │   ├── docker-compose.db.yml.j2
│       │   └── .env.db.j2        # Credenciales desde inventory → BD
│
├── group_vars/
│   └── all.yml                   # Variables compartidas de Ansible
│
├── playbook.yml                  # Despliega el rol database en EC2-DB
├── reset.yml                     # Reinicia el entorno de base de datos
├── ansible.cfg                   # Configuración de Ansible
├── inventory.ini                 # AUTO-GENERADO por terraform apply
└── .gitignore                    # Protege secrets y ficheros generados
```

---

## 11. Puntos Importantes

### 1. Gestión de Costes

Los recursos que tienen coste (fuera del Free Tier) son:

- **ALB**: ~$0.016/hora (~$0.40/día). Necesario para el Auto Scaling Group.
- **EC2 t3.micro**: El Free Tier cubre 750 horas/mes en total para todas las instancias. Con 3 instancias corriendo 24h serían ~72h/día, lo que supera el límite si se deja encendido todo el mes.

**Regla de oro**: Solo encender la infraestructura cuando vayas a trabajar o a hacer la defensa. Destruir siempre al terminar con `terraform destroy`.

### 2. Seguridad por capas

El proyecto implementa seguridad en múltiples niveles:

- **Security Groups**: El puerto 3306 (MariaDB) solo es accesible desde las instancias web, no desde internet. El puerto 2049 (EFS/NFS) solo es accesible desde las instancias web. El SSH (22) solo es accesible desde tu IP.
- **IAM roles**: Las instancias web solo pueden leer del bucket S3 de configuración. No tienen permisos para modificar nada más.
- **Red privada**: La comunicación entre las instancias web y la base de datos se hace por la red privada de AWS usando IPs privadas.

### 3. Persistencia y alta disponibilidad

- Los datos de WordPress (imágenes, ficheros) viven en el EFS, que es un sistema de ficheros distribuido y resistente a fallos de zona de disponibilidad.
- Los datos de MariaDB viven en el volumen EBS de EC2-DB. Si EC2-DB se reinicia, los datos persisten. Si EC2-DB se termina, los datos se pierden (para producción real habría que usar RDS con Multi-AZ o hacer snapshots).
- Los contenedores Docker están configurados con `restart: always`, por lo que se reinician automáticamente si crashean o si la instancia se reinicia.

### 4. Secrets y seguridad del código

- Las contraseñas viajan de `terraform.tfvars` (en tu máquina local, nunca en git) → a S3 (fichero `.env` privado) → a las instancias web en tiempo de arranque.
- El estado de Terraform (`terraform.tfstate`) contiene las contraseñas en texto plano y está en `.gitignore`. Para producción se usaría un backend remoto de Terraform (S3 + DynamoDB con cifrado).
- Nunca subas `terraform.tfvars`, `inventory.ini`, `.pem` ni `terraform.tfstate` a git.

### 5. El usuario root

Para la defensa, el evaluador pedirá conectarse como root al servidor. En Ubuntu 22.04 el usuario por defecto es `ubuntu`. Para demostrar el acceso como root:

```bash
ssh -i ~/.ssh/cloud-1-key.pem ubuntu@IP_SERVIDOR
sudo su -
# Ahora eres root
```
