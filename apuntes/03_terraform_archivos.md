# 03 — Terraform: Cada Archivo Explicado

> Todos los archivos `.tf` están en `42_Cloud-1/terraform/`. Este documento explica qué hace cada uno y por qué está organizado así.

---

## Convención de nombres

Terraform no requiere nombres específicos de archivo (todo el directorio se trata como una unidad). Pero por convención:

| Archivo | Contenido |
|---------|-----------|
| `main.tf` | Configuración del provider, data sources generales |
| `variables.tf` | Todas las variables de entrada |
| `outputs.tf` | Todos los outputs |
| `X.tf` | Recursos relacionados con X |

---

## `main.tf` — Base de todo

```hcl
terraform {
  required_version = ">= 1.5"		# versión mínima de Terraform
  required_providers {
    aws    = { source = "hashicorp/aws",   version = "~> 5.0" }
    local  = { source = "hashicorp/local", version = "~> 2.0" }
    random = { source = "hashicorp/random",version = "~> 3.0" }
    null   = { source = "hashicorp/null",  version = "~> 3.0" }
  }
}

provider "aws" {
  region = var.aws_region			# la región viene de variables.tf
}
```

**Data sources definidos aquí**:
- `data.aws_availability_zones.available` — AZs disponibles en la región
- `data.aws_vpc.default` — la VPC por defecto de la cuenta
- `data.aws_subnets.default` — subnets de esa VPC
- `data.aws_ami.ubuntu` — la AMI más reciente de Ubuntu 22.04 de Canonical (owner ID `099720109477`)

El data source de AMI busca la imagen más reciente con filtros de nombre y virtualización:
```hcl
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]	# Canonical (empresa que mantiene Ubuntu)
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}
```

**Por qué usar `most_recent = true`**: siempre usa la última AMI con los últimos parches de seguridad.

---

## `variables.tf` — Todas las variables configurables

### Variables sin default (obligatorias)
```hcl
variable "my_ip"           # IP del deployer para SSH → "1.2.3.4/32"
variable "db_password"     # password de MariaDB (sensitive)
variable "db_root_password"# password root de MariaDB (sensitive)
variable "wp_admin_password"# password del admin de WordPress (sensitive)
```

### Variables con default (opcionales)
```hcl
variable "aws_region"       { default = "eu-west-3" }
variable "instance_type"    { default = "t3.micro"  }
variable "key_name"         { default = "cloud-1-key" }
variable "web_min_size"     { default = 2 }
variable "web_desired"      { default = 2 }
variable "web_max_size"     { default = 4 }
variable "db_name"          { default = "wordpress" }
variable "db_user"          { default = "wordpress_user" }
variable "wp_title"         { default = "Cloud-1" }
variable "wp_admin_user"    { default = "admin" }
variable "wp_admin_email"   { default = "admin@example.com" }
variable "duckdns_token"    { default = "" }  # vacío = no actualizar DNS
variable "duckdns_subdomain"{ default = "mlezcano-cloud1" }
variable "project_name"     { default = "cloud1" }  # prefijo de nombres
```

**Patrón `project_name`**: usar un prefijo en todos los recursos evita colisiones de nombres en AWS cuando tienes varios proyectos. Por ejemplo: `cloud1-lb-sg`, `cloud1-web-asg`, `cloud1-efs`.

---

## `security_groups.tf` — El firewall por instancia

Define 4 Security Groups (SG). Un SG en AWS es un firewall con estado (*stateful*): las respuestas al tráfico entrante están permitidas automáticamente.

### SG-LB: para el Load Balancer
```hcl
resource "aws_security_group" "lb" {
  ingress { port = 80,  from = "0.0.0.0/0" }  # internet puede conectar
  ingress { port = 443, from = "0.0.0.0/0" }  # internet puede conectar
  ingress { port = 22,  from = var.my_ip    }  # SSH solo desde tu IP
  egress  { all, to = "0.0.0.0/0"           }  # puede salir a cualquier sitio
}
```

### SG-Web: para los servidores web
```hcl
ingress { port = 80, from_security_group = aws_security_group.lb.id }
```

**Clave**: en lugar de una IP, el origen es **otro Security Group**. Esto significa "solo el LB puede conectar al puerto 80 de los web servers". Si el LB cambia de IP (por reinicio), el SG sigue siendo correcto porque referencia al grupo, no a la IP. Esto es un patrón muy habitual en AWS.

### SG-DB: para la base de datos
```hcl
ingress { port = 3306, from_security_group = aws_security_group.web.id }
```

Solo los servidores web pueden conectar al puerto 3306 de MariaDB. Nadie desde internet puede llegar a la base de datos.

### SG-EFS: para el sistema de archivos
```hcl
ingress { port = 2049, from_security_group = aws_security_group.web.id }
```

NFS usa el puerto 2049. Solo los web servers pueden montar el EFS.

---

## `iam.tf` — Permisos de las instancias web

AWS IAM (Identity and Access Management) gestiona quién puede hacer qué en AWS.

### El problema que resuelve
Las instancias web necesitan descargar archivos de S3 al arrancar. Pero no podemos poner credenciales de AWS dentro de la instancia (sería un riesgo de seguridad). La solución: un **IAM Role** que la instancia asume automáticamente.

### Los tres recursos que necesitamos:
```hcl
# 1. El rol (política de quién puede asumir este rol)

resource "aws_iam_role" "web_instance" {
  assume_role_policy = jsonencode({
    Statement = [{ Action = "sts:AssumeRole", Principal = { Service = "ec2.amazonaws.com" } }]
  })
}

# 2. Qué puede hacer el rol (política de permisos)

resource "aws_iam_role_policy" "web_s3_read" {
  policy = jsonencode({
    Statement = [{ Effect = "Allow", Action = ["s3:GetObject", "s3:ListBucket"],
                   Resource = [aws_s3_bucket.config.arn, "${aws_s3_bucket.config.arn}/*"] }]
  })
}

# 3. El recurso que une el rol con la instancia EC2

resource "aws_iam_instance_profile" "web" {
  role = aws_iam_role.web_instance.name
}
```

**Principio de mínimo privilegio**: el rol solo puede leer y listar el bucket de configuración. No puede escribir, no puede acceder a otros buckets, no puede hacer nada más en AWS.

---

## `s3.tf` — Bucket de configuración

```hcl
resource "aws_s3_bucket" "config" {
  bucket        = "${var.project_name}-web-config-${random_id.suffix.hex}"
  force_destroy = true		# permite borrar el bucket aunque tenga objetos
}
```

**`random_id.suffix`**: genera un sufijo aleatorio de 4 bytes (8 caracteres hex). Los nombres de S3 son globales en AWS — si alguien ya tiene `cloud1-web-config`, da error. El sufijo aleatorio evita colisiones.

**`force_destroy = true`**: por defecto, AWS no deja borrar un bucket con objetos. Con esta opción, `terraform destroy` borra los objetos y luego el bucket.

**`aws_s3_bucket_public_access_block`**: bloquea todo acceso público al bucket. Solo las instancias web con el IAM Role pueden leer de él.

---

## `s3_objects.tf` — Contenido del bucket

Sube tres archivos al bucket, renderizados desde templates Terraform:

```hcl
resource "aws_s3_object" "docker_compose_web" {
  content = templatefile("docker-compose.web.yml.tpl", {
    db_private_ip = aws_instance.db.private_ip
  })
}

resource "aws_s3_object" "nginx_web_conf" {
  content = templatefile("nginx.web.conf.tpl", {
    cloudfront_domain = aws_cloudfront_distribution.wordpress.domain_name
  })
}

resource "aws_s3_object" "env_web" {
  content = templatefile("env_web.tpl", {
    db_password = var.db_password
    ...
  })
}
```

Los templates usan `${variable}` para interpolación Terraform y `$${variable_bash}` para variables bash literales.

---

## `efs.tf` — Sistema de archivos compartido

```hcl
resource "aws_efs_file_system" "wordpress" {
  creation_token   = "${var.project_name}-wordpress-efs"
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"
}

resource "aws_efs_mount_target" "wordpress" {
  for_each = toset(data.aws_subnets.default.ids)  # un mount target por subnet
  file_system_id  = aws_efs_file_system.wordpress.id
  subnet_id       = each.value
  security_groups = [aws_security_group.efs.id]
}
```

**`for_each`**: crea un `aws_efs_mount_target` por cada subnet de la VPC. Esto es importante porque las instancias web pueden estar en cualquier Availability Zone — el EFS debe tener un mount target en la misma AZ que la instancia para que funcione.

**`bursting` throughput**: el EFS escala el throughput según el uso. Suficiente para este proyecto.

---

## `ec2_lb.tf` — El Load Balancer

```hcl
resource "aws_instance" "lb" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type		# t3.micro
  key_name               = var.key_name				# cloud-1-key
  vpc_security_group_ids = [aws_security_group.lb.id]
}

resource "aws_eip" "lb" {
  instance = aws_instance.lb.id						# asocia la Elastic IP a la instancia
}

resource "null_resource" "duckdns_update" {
  count = var.duckdns_token != "" ? 1 : 0			# solo si hay token

  provisioner "local-exec" {
    command = "curl -s 'https://www.duckdns.org/update?domains=...&ip=${aws_eip.lb.public_ip}'"
  }
}
```

**`count = var.duckdns_token != "" ? 1 : 0`**: expresión ternaria. Si el token existe, crea el recurso (count=1); si no, no lo crea (count=0). Así hacemos que DuckDNS pueda ser completamente opcional.

---

## `ec2_db.tf` — La Base de Datos

Simple: una EC2 Ubuntu con el SG de DB. Sin Elastic IP (no necesita IP estable, los web servers se conectan por IP privada que no cambia mientras la instancia está en ejecución).

---

## `asg.tf` — Auto Scaling Group

### Launch Template
Define cómo debe ser cada instancia web que el ASG cree:

```hcl
resource "aws_launch_template" "web" {
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = var.key_name

  iam_instance_profile { name = aws_iam_instance_profile.web.name }

  user_data = base64encode(templatefile("user_data.sh.tpl", {
    efs_dns_name      = aws_efs_file_system.wordpress.dns_name
    s3_bucket         = aws_s3_bucket.config.id
    cloudfront_domain = aws_cloudfront_distribution.wordpress.domain_name
    wp_admin_password = var.wp_admin_password
    ...
  }))
}
```

El `user_data` es el script de cloud-init codificado en base64. AWS lo ejecuta automáticamente en el primer arranque de la instancia.

### Auto Scaling Group

```hcl
resource "aws_autoscaling_group" "web" {
  min_size         = var.web_min_size			# mínimo 2 instancias
  desired_capacity = var.web_desired			# objetivo 2 instancias
  max_size         = var.web_max_size			# máximo 4

  health_check_type         = "EC2"				# usa los status checks de EC2
  health_check_grace_period = 600				# 10 min para que cloud-init termine
}
```

**`health_check_type = "EC2"`**: el ASG usa los AWS EC2 status checks para determinar si una instancia es saludable. Si los status checks fallan (hardware roto, instancia no responde), el ASG termina esa instancia y lanza una nueva.

**`health_check_grace_period = 600`**: espera 10 minutos antes de empezar a comprobar la salud. Necesario porque cloud-init tarda varios minutos.

### CloudWatch Alarms + Scaling Policies

```hcl
# Si CPU > 70% durante 2 minutos → añadir 1 instancia

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  threshold     = 70
  alarm_actions = [aws_autoscaling_policy.scale_up.arn]
}

# Si CPU < 30% durante 3 minutos → quitar 1 instancia

resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  threshold     = 30
  alarm_actions = [aws_autoscaling_policy.scale_down.arn]
}
```

Esto permite la demo de escalado automático por carga.

---

## `cloudfront.tf` — CDN

```hcl
origin {
  domain_name = "ec2-${replace(aws_eip.lb.public_ip, ".", "-")}.eu-west-3.compute.amazonaws.com"
}
```

**Por qué no podemos usar la IP directamente**: CloudFront requiere un hostname como origen, no acepta IPs. AWS asigna automáticamente un hostname DNS a cada Elastic IP con el formato `ec2-W-X-Y-Z.region.compute.amazonaws.com`. Reemplazamos los puntos de la IP por guiones.

**Comportamientos de caché**:
- Default: `min_ttl=0, default_ttl=0` → sin caché (para WordPress dinámico)
- `/wp-content/*`: `default_ttl=86400` → caché de 1 día (CSS, JS, imágenes)
- `/wp-includes/*`: `default_ttl=86400` → caché de 1 día (core de WordPress)

---

## `ansible_provision.tf` — Automatizar Ansible desde Terraform

```hcl
resource "null_resource" "ansible_provision" {
  depends_on = [
    local_file.ansible_inventory,				# inventory.ini debe existir
    aws_eip.lb,									# LB debe tener IP
    aws_instance.db,
    aws_autoscaling_group.web,
    aws_cloudfront_distribution.wordpress,
  ]

  triggers = {
    lb_ip    = aws_eip.lb.public_ip
    db_ip    = aws_instance.db.public_ip
    asg_name = aws_autoscaling_group.web.name
  }

  provisioner "local-exec" {
    command = <<-EOT

      # Espera SSH en LB
      until ssh -o ConnectTimeout=5 ubuntu@${aws_eip.lb.public_ip} true; do sleep 10; done

      # Espera instancias ASG en InService
      until [ "$(aws autoscaling describe-auto-scaling-groups ...)" -ge 2 ]; do sleep 30; done

      # Lanza Ansible
      cd ${path.module}/..
      ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i inventory.ini playbook.yml
    EOT
  }
}
```

**`triggers`**: si la IP del LB o DB cambia (tras un `destroy` + `apply`), el `null_resource` se re-ejecuta y Ansible vuelve a correr. Sin triggers, Terraform solo lo ejecutaría una vez.

**`${path.module}`**: ruta al directorio que contiene el archivo `.tf`. En este caso `terraform/`. Con `${path.module}/..` llegamos a `42_Cloud-1/`.

---

## `inventory.tf` + `inventory.tpl` — Generar el inventario de Ansible

```hcl
resource "local_file" "ansible_inventory" {
  content = templatefile("inventory.tpl", {
    lb_public_ip  = aws_eip.lb.public_ip
    db_public_ip  = aws_instance.db.public_ip
    db_private_ip = aws_instance.db.private_ip
    asg_name      = aws_autoscaling_group.web.name
    db_password   = var.db_password
    ...
  })
  filename = "${path.module}/../inventory.ini"
}
```

**IP pública vs privada de la DB**:
- **Pública** (`db_public_ip`): Ansible usa SSH desde tu máquina local → necesita IP pública.
- **Privada** (`db_private_ip`): WordPress conecta a MariaDB desde dentro de la VPC de AWS → usa la IP privada (más rápido, no sale a internet).

El template `inventory.tpl` genera:
```ini
[lb]
51.44.x.x ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/cloud-1-key.pem

[db]
15.237.x.x ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/cloud-1-key.pem

[all:vars]
db_private_ip=172.31.x.x
asg_name=cloud1-web-asg
...
```

---

## `outputs.tf` — Valores de salida

Los outputs sirven para dos cosas:
1. Mostrar información útil al usuario al terminar `terraform apply`.
2. Ser consumidos por otros módulos de Terraform (no aplica aquí, somos módulo raíz, no usamos otros).

```hcl
output "cloudfront_domain" {
  value = "https://${aws_cloudfront_distribution.wordpress.domain_name}"
}

output "lb_public_ip" {
  value = aws_eip.lb.public_ip
}

output "deploy_instructions" {
  value = <<-EOT
    Site: https://${aws_cloudfront_distribution.wordpress.domain_name}
    LB:   ${aws_eip.lb.public_ip}
  EOT
}
```

---

## Templates (`.tpl`) — Archivos de plantilla

Terraform usa sus propios templates (no Jinja2 como Ansible).

**`user_data.sh.tpl`**: script bash que corre en las instancias web al arrancar. Los `${variable}` son interpolados por Terraform antes de subir el script a AWS. Los `$$variable` son variables bash que Terraform NO interpola.

**`docker-compose.web.yml.tpl`**: docker-compose para las instancias web. El `${db_private_ip}` viene de Terraform; los `$${DB_USER}` son variables de entorno de Docker que vienen del `.env`.

**`nginx.web.conf.tpl`**: configuración de Nginx para las instancias web. El `${cloudfront_domain}` se usa para configurar `WP_CONTENT_URL`.

**`env_web.tpl`**: genera el archivo `.env` con credenciales. Sin variables bash, todo es interpolación Terraform.

**`inventory.tpl`**: genera `inventory.ini` de Ansible con las IPs reales.
