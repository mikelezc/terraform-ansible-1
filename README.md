# Cloud-1: Infraestructura Multi-Servidor en AWS

Este documento es la guía completa de la arquitectura y el despliegue del proyecto. 

---

## 1. Conceptos Fundamentales del Proyecto

La infraestructura se distribuye entre varias máquinas EC2 de AWS, y todo se aprovisiona mediante **dos capas de automatización**:

### Infraestructura como Código (IaC) con Terraform

Terraform nos permite describir en código HCL (HashiCorp Configuration Language) qué recursos de AWS queremos crear y desplegar.

Además, gestiona los cambios que queramos hacer sobre de la infraestructura: 

Si ejecutamos `terraform apply` dos veces, solo aplicará los cambios que no existían todavía (idempotencia).

Si ejecutamos `terraform destroy`, se eliminará absolutamente todo lo que se creó, dejando la cuenta de AWS limpia de todo lo que hemos creado.

### Configuración de Servidores con Ansible

Ansible configura el **load balancer** (EC2-LB) y el **servidor de base de datos** (EC2-DB). 

Las instancias web se auto-configuran solas al arrancar mediante un script de `cloud-init` (explicaremos más sobre esto en la sección de arquitectura).

**1 contenedor = 1 proceso**. Los servicios que corren son:

- **Nginx LB**: Balanceador de carga, en su propia instancia EC2 dedicada.
- **Nginx Web**: Servidor web y *Reverse Proxy* en cada instancia web.
- **WordPress (PHP-FPM)**: La aplicación en PHP, también en cada instancia web.
- **phpMyAdmin**: Interfaz web de administración de la base de datos, también en cada instancia web.
- **MariaDB**: Base de datos, en su propia instancia EC2 dedicada.

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
                           │ HTTP (puerto 80, interno)
                           ▼
              ┌─────────────────────────┐
              │  EC2-LB (t3.micro)      │
              │  Ubuntu 22.04           │
              │  Elastic IP (estable)   │
              │  Docker: Nginx LB       │
              │  - Round-robin a webs   │
              │  - Failover pasivo      │
              │  - Puerto 443 con cert  │
              │    auto-firmado         │
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
              │  EC2-DB (t3.micro)      │
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

### Desglose de componentes

| Componente | Por qué lo necesitamos |
|---|---|
| **CloudFront** | CDN: cachea assets estáticos (CSS, JS, imágenes) cerca del usuario. |
| **EC2-LB + Nginx** | Distribuye peticiones entre instancias web en round-robin. Failover pasivo: si un backend no responde, Nginx lo descarta y usa los demás. Elastic IP estable → DuckDNS puede apuntar a ella. Coste: $0 (t3.micro free tier). |
| **Auto Scaling Group** | Mantiene siempre un mínimo de 2 instancias web. Si una cae (hardware failure, terminación manual), ASG lanza otra automáticamente. Permite escalar horizontalmente. |
| **EC2-DB separado** | La base de datos esté en una máquina distinta a las web. |
| **EFS** | Sistema de ficheros de red compartido. Cuando subes una imagen en la instancia web-1, también aparece en web-2. Sin esto, cada servidor tendría su propio disco y las imágenes no sincronizarían. |
| **S3** | Las instancias del Auto Scaling Group se lanzan automáticamente. Necesitan descargar su configuración de algún sitio al arrancar. S3 es el repositorio centralizado de configuración. |

---

## 3. Cómo Funciona el Auto-arranque de Instancias Web (cloud-init)

Cuando el Auto Scaling Group crea una nueva instancia web, ejecuta automáticamente el script `terraform/user_data.sh.tpl` en el primer arranque. Este script:

1. Instala Docker y las dependencias necesarias.
2. Monta el EFS en `/home/ubuntu/data/wordpress` (ficheros compartidos de WordPress).
3. Descarga `docker-compose.yml`, `nginx.conf` y `.env` del bucket S3.
4. Genera el certificado SSL auto-firmado.
5. Arranca los contenedores con `docker compose up -d`.
6. Espera a que WordPress cree `wp-config.php` y lo parchea para que funcione con HTTPS y con el CDN de CloudFront.

Todo esto ocurre sin que el operador haga nada. El Auto Scaling Group lo gestiona solo.

---

## 4. Prerrequisitos

Antes de ejecutar cualquier cosa, necesitamos configurar lo siguiente en la máquina local:

### Herramientas

```bash
# macOS — Terraform requiere el tap oficial de HashiCorp (no está en Homebrew core):
brew tap hashicorp/tap
brew install hashicorp/tap/terraform

# macOS — Ansible y AWS CLI sí están en Homebrew core:
brew install ansible awscli

# Ubuntu:
sudo apt update && sudo apt install -y ansible awscli
# Terraform en Ubuntu: https://developer.hashicorp.com/terraform/install

# Verificar que todo está instalado:
terraform version
ansible --version
aws --version
```

### Cuenta y credenciales AWS

1. Inicia sesión en [console.aws.amazon.com](https://console.aws.amazon.com).
2. Haz clic en tu nombre de usuario (arriba a la derecha) → **Security credentials**.
3. Baja hasta la sección **Access keys** → **Create access key**.
4. Elige el caso de uso **Command Line Interface (CLI)** → Next → Create.
5. Copia el **Access Key ID** y el **Secret Access Key** — el secret solo se muestra una vez, descarga el `.csv` si no quieres apuntarlo a mano.

Con esos datos, configura el CLI de AWS:

```bash
aws configure
# AWS Access Key ID:     AKIAIOSFODNN7EXAMPLE
# AWS Secret Access Key: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
# Default region name:   eu-west-3
# Default output format: json
```

Esto guarda las credenciales en `~/.aws/credentials`. Terraform las usará automáticamente desde ahí.

### Key pair de AWS

Las instancias EC2 necesitan un par de claves SSH para que Ansible pueda conectarse. Para crearlas:

1. Vamos a AWS Console → EC2 → Key Pairs → Create key pair.
2. Ponemos nombre `cloud-1-key`, y elegimos el formato `.pem`.
3. Guardamos el fichero en nuestra máquina local `~/.ssh/cloud-1-key.pem`.
4. Otorgamos permisos correctos:

```bash
chmod 400 ~/.ssh/cloud-1-key.pem
```

> **Importante**: El key pair debe existir en la región `eu-west-3` por como está creado nuestro código. 

---

## 5. Configuración Inicial

### Paso 1: Configuración de las variables secretas

Entramos en la carpeta `terraform/` y copia el fichero de ejemplo:

```bash
cd 42_Cloud-1/terraform
cp terraform.tfvars.example terraform.tfvars
```

Editamos `terraform.tfvars` con los valores reales:

```hcl
# Nuestra IP pública actual (para restringir SSH solo a tu máquina)
# Podemos obtenerla con: curl ifconfig.me
my_ip = "1.2.3.4/32"

# Nombre del key pair que creamos en AWS eu-west-3
key_name = "cloud-1-key"

# Contraseñas de la base de datos
db_password      = "mi_password_seguro"
db_root_password = "mi_root_password_seguro"

# Credenciales del admin de WordPress (se instala automáticamente con WP-CLI al arrancar)
wp_admin_password = "mi_password_wp_seguro"
# wp_admin_user  = "admin"                 # usuario admin (por defecto: admin)
# wp_admin_email = "admin@example.com"     # email del admin
# wp_title       = "Cloud-1"              # título del sitio

# Opcional: DuckDNS (si queremos un dominio concreto)
# duckdns_token     = "tu-token-de-duckdns"
# duckdns_subdomain = "mlezcano-cloud1"
```

> **Nunca subas `terraform.tfvars` a git.** Está en el `.gitignore`. Contiene todas las contraseñas.

Las variables de WordPress funcionan así:
- `wp_admin_password` es obligatoria (no tiene valor por defecto).
- `wp_admin_user`, `wp_admin_email` y `wp_title` tienen valores por defecto y son opcionales.
- Al arrancar cada instancia web, `cloud-init` instala WP-CLI dentro del contenedor de WordPress y ejecuta `wp core install` con estas credenciales. Si WordPress ya está instalado en el EFS (porque otra instancia lo instaló antes), se salta la instalación.

### Paso 2 (Opcional): DuckDNS

Si queremos un dominio personalizado (`mlezcano-cloud1.duckdns.org`):

1. Crea una cuenta en [duckdns.org](https://www.duckdns.org) y creamos el subdominio.
2. Copiamos el token que aparece en la cuenta.
3. Lo añadiremos en `terraform.tfvars`.

Terraform actualizará automáticamente el registro DNS con la IP del LB al hacer `terraform apply`.

---

## 6. Despliegue Completo

### Fase 1: Infraestructura con Terraform

```bash
cd 42_Cloud-1/terraform

# Descargamos los plugins de Terraform (solo la primera vez)
terraform init

# Previsualizamos qué se va a crear (opcional pero recomendado)
terraform plan

# Creamos toda la infraestructura en AWS
terraform apply
```

> **Aviso de `terraform plan`**: al terminar muestra el mensaje *"You didn't use the -out option to save this plan..."*. Es informativo, no un error. Significa que si algo cambiase en AWS entre el `plan` y el `apply`, Terraform actuaría sobre el estado real en ese momento, no sobre la foto del plan. Para este proyecto se puede ignorar. Si quisieras garantía total, guardarías el plan así:
> ```bash
> terraform plan -out=tfplan   # guarda el plan en un archivo
> terraform apply tfplan       # aplica exactamente ese plan
> ```

```bash
```

Terraform creará, en orden aproximado:

1. Security Groups e IAM roles.
2. Bucket S3 y sube la configuración renderizada.
3. Sistema de ficheros EFS.
4. EC2-DB (base de datos) y EC2-LB (load balancer).
5. Elastic IP asociada al EC2-LB.
6. CloudFront (esto tarda ~15 minutos — es normal).
7. Auto Scaling Group con las instancias web.
8. Genera el fichero `inventory.ini` para Ansible.
9. **Lanza Ansible automáticamente** — espera SSH en LB y DB, espera que el ASG tenga instancias activas y ejecuta el playbook sin intervención manual.

Al finalizar, veremos los outputs:

```
cloudfront_domain = "https://d1abc123xyz.cloudfront.net"
lb_public_ip      = "15.188.xx.xx"
db_public_ip      = "35.180.xx.xx"
```

La URL de CloudFront es la dirección del sitio.

> **`ansible/inventory.ini` se genera automáticamente**: Terraform escribe este fichero en `ansible/` al terminar con las IPs reales del LB, la DB y las variables necesarias para Ansible. No hay que tocarlo a mano.

### Fase 2: Esperar a las instancias web (~5 minutos)

Mientras Terraform lanzaba Ansible en el paso anterior, el Auto Scaling Group arrancaba las instancias web en paralelo. Éstas se auto-configuran mediante `cloud-init` (instalan Docker, montan EFS, descargan config de S3 y arrancan WordPress). Puedes ver el progreso en AWS Console → EC2 → Instances.

> **Ansible ya se ejecutó solo**: no hace falta correr `ansible-playbook` manualmente en un despliegue inicial. El paso siguiente existe como referencia para casos específicos.

### Ejecutar Ansible manualmente (solo cuando sea necesario)

Terraform llama a Ansible automáticamente en el despliegue inicial. Solo necesitas ejecutarlo a mano en estos casos:

```bash
# Los comandos de Ansible se ejecutan desde la carpeta ansible/
cd 42_Cloud-1/ansible

# Tras escalar el número de instancias web (actualizar upstream de Nginx):
ansible-playbook -i inventory.ini playbook.yml -l lb

# Si quieres re-configurar LB y DB sin destruir la infraestructura:
ansible-playbook -i inventory.ini playbook.yml
```

Ansible hace dos cosas:

1. **En EC2-LB**: instala Docker, genera el certificado SSL, consulta AWS para descubrir las IPs privadas de las instancias web del ASG, y arranca Nginx como load balancer con esas IPs en el bloque `upstream`.

2. **En EC2-DB**: instala Docker y arranca MariaDB con las credenciales que definiste en `terraform.tfvars`.

### Fase 4: Acceder al sitio

```bash
# Ver todos los outputs (URL, IPs, nombre del ASG...):
cd terraform
terraform output

# O solo la URL del sitio:
terraform output cloudfront_domain
```

`terraform output <nombre>` muestra el valor del output definido en `outputs.tf` con ese nombre. Debe ejecutarse desde la carpeta `terraform/` donde está el estado de Terraform.

Abrimos esa URL en el navegador. Veremos WordPress funcionando con HTTPS.

---

## 7. Demos de funcionamiento

### Verificar que hay 2 servidores en paralelo

Abrimos las herramientas de desarrollo del navegador (F12 → Network) y recargamos la página varias veces. 
Buscamos la cabecera de respuesta `X-Served-By`: veremos que cambia entre diferentes nombres de instancia, demostrando que el Nginx LB está distribuyendo las peticiones.

![Cabecera X-Served-By en DevTools mostrando el servidor que atendió la petición](guide_photos/x_served_by.png)

Si queremos hacerlo desde la terminal con curl

```bash
for i in $(seq 1 6); do
  curl -sk https://TU_CLOUDFRONT_DOMAIN/ -I | grep -i x-served-by
done
```

### Verificar el CDN

En las herramientas de desarrollo (F12 → Network), recargamos la página dos veces. En la segunda carga, los ficheros de `/wp-content/` (CSS, imágenes del tema) mostrarán la cabecera:

```
x-cache: Hit from cloudfront
```

![Cabecera caché cloudfront](guide_photos/hit_from_cloudfront.png)

Esto demuestra que CloudFront está cacheando y sirviendo los assets estáticos.

### Verificar persistencia de sesión

1. Entra al panel de administración: `https://TU_URL/wp-admin`.
2. Iniciamos sesión con las credenciales configuradas.
3. Recargamos la página varias veces.
4. Comprobamos que seguimos logueados aunque el `X-Served-By` cambie entre instancias.

Esto funciona porque WordPress usa cookies firmadas con las claves de `wp-config.php`. Al compartir `wp-config.php` vía EFS, las claves son idénticas en todas las instancias y las cookies son válidas en cualquier servidor.

### Verificar sincronización de imágenes

1. Vamos a WordPress Admin → Media → Añadir nueva.
2. Subimos cualquier imagen.
3. Publicamos un artículo con esa imagen.
4. Recargamos la página varias veces: la imagen aparece independientemente de qué instancia sirva la petición.

Esto funciona gracias al EFS compartido: el directorio `wp-content/uploads/` es el mismo sistema de ficheros para todas las instancias.

### Demo de escalado horizontal

```bash
cd terraform

# Escalar de 2 a 4 instancias web
terraform apply -var="web_desired=4"
```

Las nuevas instancias arrancarán con cloud-init y se auto-configurarán. Una vez en estado `running`, actualiza el Nginx LB para que las incluya en el upstream:

```bash
cd 42_Cloud-1/ansible
ansible-playbook -i inventory.ini playbook.yml -l lb
```

Para demostrar que el tráfico llega a las nuevas instancias, recargamos el sitio y observamos cómo `X-Served-By` ahora muestra 4 hostnames distintos.

Para volver a 2 instancias:

```bash
cd 42_Cloud-1/terraform
terraform apply -var="web_desired=2"
cd ../ansible
ansible-playbook -i inventory.ini playbook.yml -l lb
```

### Demo de alta disponibilidad (HA)

1. Vamos a AWS Console → EC2 → Instances.
2. Seleccionamos una de las instancias `cloud1-web` y la terminamos (Actions → Terminate instance).
3. Observaremos que el sitio sigue funcionando: el Nginx LB detecta que ese backend no responde y deja de enviarle tráfico (failover pasivo).
4. En AWS Console → Auto Scaling Groups → cloud1-web-asg, verás cómo el ASG lanza automáticamente una nueva instancia para mantener el mínimo de 2.
5. En unos ~5 minutos, la nueva instancia termina cloud-init y está lista.
6. Actualizamos el upstream del Nginx LB:

```bash
cd 42_Cloud-1/ansible
ansible-playbook -i inventory.ini playbook.yml -l lb
```

---

## 8. Gestión del Entorno

### Ver el estado de la infraestructura

```bash
cd terraform

# Para ver todos los outputs (URL, IPs, etc.)
terraform output

# Para ver el estado completo de recursos
terraform show
```

### Reiniciar los contenedores en el servidor de base de datos

```bash
# Desde la carpeta 42_Cloud-1/ansible/ (donde está inventory.ini):
cd 42_Cloud-1/ansible
DB_IP=$(grep -A1 '^\[db\]' inventory.ini | tail -1 | awk '{print $1}')
ssh -i ~/.ssh/cloud-1-key.pem ubuntu@$DB_IP
# Una vez dentro del servidor:
cd /home/ubuntu/db && docker compose restart
```

### Conectarse al Nginx LB

```bash
# Desde la carpeta 42_Cloud-1/ansible/:
cd 42_Cloud-1/ansible
LB_IP=$(grep -A1 '^\[lb\]' inventory.ini | tail -1 | awk '{print $1}')
ssh -i ~/.ssh/cloud-1-key.pem ubuntu@$LB_IP

# Una vez dentro, ver la configuración de nginx generada por Ansible:
cat /home/ubuntu/lb/nginx.conf

# Ver los logs del LB:
docker logs nginx-lb
```

### Ver logs de cloud-init en instancias web

Para diagnosticar problemas en instancias del ASG:

```bash
# Obtenemos la IP de una instancia web desde AWS Console → EC2 → Instances
ssh -i ~/.ssh/cloud-1-key.pem ubuntu@IP_INSTANCIA_WEB
cat /var/log/cloud-init-wordpress.log
```

### Aplicar cambios de configuración a instancias ya desplegadas

El `cloud-init` solo se ejecuta una vez al crear la instancia. Si modificas variables de WordPress o el script de arranque en `terraform.tfvars` o `user_data.sh.tpl`, las instancias web existentes no se actualizarán solas. Para aplicar los cambios:

```bash
# 1. Actualizar el Launch Template con el nuevo user_data
cd terraform
terraform apply

# 2. Terminar las instancias web actuales desde AWS Console:
#    EC2 → Instances → seleccionar instancias "cloud1-web" → Terminate instance
#    El ASG las reemplaza automáticamente con el nuevo script de arranque

# 3. Actualizar el certificado del LB (si cambiaste los campos del cert):
cd 42_Cloud-1/ansible
ansible-playbook -i inventory.ini playbook.yml -l lb
```

### Reset del entorno para demos

Si queremos dejar el LB y la DB completamente limpios para volver a desplegar desde cero:

```bash
cd 42_Cloud-1/ansible
ansible-playbook -i inventory.ini reset.yml
# Y a continuación:
ansible-playbook -i inventory.ini playbook.yml
```

---

## 9. Destrucción Completa de la Infraestructura

Cuando terminemos con el proyecto, **es muy importante** destruir todos los recursos para no incurrir en costes:

```bash
cd 42_Cloud-1/terraform
terraform destroy
```

Terraform pedirá confirmación con `yes`. Eliminará absolutamente todo:

- Las instancias EC2 (LB, DB y todas las web del ASG).
- El Auto Scaling Group y el Launch Template.
- La distribución de CloudFront.
- El bucket S3 y su contenido.
- El sistema de ficheros EFS y todos los datos de WordPress.
- La Elastic IP.
- Los Security Groups e IAM roles.
- El `inventory.ini` local.

> **Atención**: `terraform destroy` borra los datos de WordPress de forma permanente. Esto es correcto para un entorno de práctica.

---

## 10. Estructura del Repositorio

```
42_Cloud-1/
│
├── README.md
├── apuntes/                      # Apuntes del proyecto + hoja de ruta certificación Terraform
├── guide_photos/                 # Capturas para el README
│
├── terraform/                    # Capa de infraestructura (Terraform)
│   ├── main.tf                   # Provider AWS (eu-west-3), data sources
│   ├── variables.tf              # Variables: web_desired, instance_type, credentials...
│   ├── outputs.tf                # Salidas: URL, IPs, ASG name...
│   ├── security_groups.tf        # SG-LB, SG-Web, SG-DB, SG-EFS
│   ├── iam.tf                    # IAM role para que instancias web lean S3
│   ├── ec2_lb.tf                 # EC2 Nginx LB + Elastic IP + DuckDNS update
│   ├── ec2_db.tf                 # EC2 MariaDB
│   ├── s3.tf + s3_objects.tf     # Bucket + configuración renderizada para cloud-init
│   ├── efs.tf                    # Sistema de ficheros compartido
│   ├── asg.tf                    # Launch Template + Auto Scaling Group + CloudWatch
│   ├── cloudfront.tf             # CDN (origin = Elastic IP del LB)
│   ├── inventory.tf              # Genera ansible/inventory.ini tras el apply
│   ├── ansible_provision.tf      # Lanza Ansible automáticamente tras crear la infra
│   ├── terraform.tfvars.example  # Variables de ejemplo (copiar a .tfvars)
│   └── templates/                # Plantillas renderizadas por Terraform
│       ├── user_data.sh.tpl      # Script cloud-init de las instancias web
│       ├── docker-compose.web.yml.tpl
│       ├── nginx.web.conf.tpl
│       ├── env_web.tpl
│       └── inventory.tpl         # Template de ansible/inventory.ini
│
└── ansible/                      # Capa de configuración (Ansible)
    ├── ansible.cfg
    ├── playbook.yml              # Configura LB (loadbalancer) y DB (database)
    ├── reset.yml                 # Reinicia LB y DB (para demos)
    ├── inventory.ini             # AUTO-GENERADO por terraform apply
    ├── group_vars/
    │   └── all.yml
    └── roles/
        ├── docker/               # Instala Docker en cualquier EC2 Ubuntu
        ├── loadbalancer/         # Configura Nginx LB en EC2-LB
        │   ├── tasks/main.yml    # Descubre IPs del ASG, genera config, arranca Nginx
        │   └── templates/
        │       ├── nginx.lb.conf.j2
        │       └── docker-compose.lb.yml.j2
        └── database/             # Despliega MariaDB en EC2-DB
            ├── tasks/main.yml
            └── templates/
                ├── docker-compose.db.yml.j2
                └── .env.db.j2
```

---

## 11. Puntos Importantes

### 1. Gestión de Costes

Con la arquitectura actual (EC2 Nginx LB en lugar de ALB), el proyecto entra completamente en el **Free Tier de AWS** para sesiones cortas de evaluación:

- **4 instancias t3.micro** × 8h de evaluación = 32h → dentro del límite de 750h/mes ✓
- **EFS**: 5 GB de free tier, más que suficiente ✓
- **CloudFront**: 1 TB de transferencia y 10 millones de peticiones/mes ✓
- **S3**: 5 GB y 20.000 peticiones GET/mes ✓

**IMPORTANTÍSIMO**: destruiremos siempre con `terraform destroy` al terminar.

### 2. Seguridad por capas

- **Security Groups**: puerto 3306 (MariaDB) solo accesible desde instancias web. Puerto 2049 (EFS) solo desde instancias web. SSH solo desde tu IP pública.
- **IAM roles**: instancias web solo pueden leer del bucket S3 de configuración.
- **Red privada AWS**: LB → Web y Web → DB usan IPs privadas (nunca pasan por internet).
- **Nginx LB**: solo expone 80 y 443 al mundo exterior.

### 3. Persistencia y alta disponibilidad

- **WordPress files** (imágenes, themes, plugins): viven en EFS → persistentes aunque fallen todas las instancias web.
- **Base de datos**: vive en el EBS de EC2-DB → persiste ante reinicios del servidor. Si la instancia se termina, los datos persisten en el volumen EBS que se puede reasignar.
- **Contenedores**: configurados con `restart: always` → se reinician automáticamente si crashean.
- **EC2 web**: ASG las reemplaza si fallan a nivel de hardware o son terminadas.

### 4. Secrets y seguridad del código

- Las contraseñas viajan de `terraform.tfvars` (local, nunca en git) → a S3 (privado, solo web instances pueden leer) → a las instancias en tiempo de arranque.
- El estado de Terraform (`terraform.tfstate`) contiene datos sensibles → está en `.gitignore`.
- `inventory.ini` contiene IPs y credenciales → está en `.gitignore` y se regenera automáticamente.

### 5. El usuario root

Para conectarse como root:

```bash
ssh -i ~/.ssh/cloud-1-key.pem ubuntu@IP_SERVIDOR
sudo su -
# Ahora eres root
```
