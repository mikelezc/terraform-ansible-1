# 02 — Terraform: Conceptos Fundamentales


## ¿Qué es Infrastructure as Code (IaC)?

Antes de descubrir IaC, creaba la infraestructura manualmente: entraba a la consola de AWS, configuraba opciones, etc. Esto tiene problemas graves:

- **No reproducible**: otro miembro del equipo no puede replicar exactamente lo mismo.
- **No versionable**: no sabes quién cambió qué y cuándo.
- **Propenso a errores**: un clic equivocado pudía romper producción (lo he sufrido personalmente en mi trabajo).

IaC resuelve esto describiendo la infraestructura en archivos de texto que se pueden versionar en git, revisar en Pull Requests y aplicar de forma reproducible.

### Tipos de IaC

| Tipo | Descripción | Ejemplo |
|------|-------------|---------|
| **Declarativo** | Describimos el estado FINAL deseado. La herramienta decide cómo llegar. | Terraform, CloudFormation |
| **Imperativo** | Describimos los PASOS a ejecutar. | Ansible (principalmente), scripts bash |

Terraform es **declarativo**: describimos qué queremos, no cómo crearlo.

---

## Qué es Terraform?

Terraform es una herramienta de IaC creada por HashiCorp. Sus características clave:

- **Multi-cloud**: funciona con AWS, Azure, GCP, y cientos de proveedores más.
- **Declarativo**: describes el estado deseado en archivos HCL.
- **Idempotente**: ejecutar `terraform apply` varias veces produce el mismo resultado.
- **Gestiona el estado**: sabe qué infraestructura ya existe y qué necesita crear/modificar/destruir.
- **Open source** 

### Terraform vs otras herramientas

| Herramienta | Tipo | Alcance |
|-------------|------|---------|
| **Terraform** | Declarativo | Infraestructura (crear/destruir recursos cloud) |
| **Ansible** | Imperativo/Declarativo | Configuración de servidores (instalar software, editar archivos) |
| **CloudFormation** | Declarativo | Solo AWS, sin estado local |
| **Pulumi** | Declarativo con código | Infraestructura con lenguajes de programación reales |

En este proyecto usamos **Terraform para crear recursos de AWS** y **Ansible para configurar los servidores** — cada herramienta en su punto fuerte ya que está dentro de las mejores prácticas IaC.

---

## HCL — HashiCorp Configuration Language

Los archivos Terraform usan HCL (extensión `.tf`). Características:

```hcl
# Bloque de recurso

resource "aws_instance" "db" {    		# tipo_recurso // nombre
  ami           = "ami-12345678"  		# argumento = valor
  instance_type = "t3.micro"

  tags = {                        		# Mapa (clave = valor)
    Name = "mi-instancia"
  }
}

# Referencia a otro recurso

resource "aws_eip" "lb" {
  instance = aws_instance.db.id   		# tipo.nombre.atributo
}
```

**Tipos de bloques principales**:
- `terraform {}` — configuración del propio Terraform (versión requerida, providers)
- `provider {}` — configura un proveedor (AWS, GCP...)
- `resource {}` — define un recurso real en cloud
- `data {}` — lee información existente sin crearla
- `variable {}` — input variable (valor que entra de fuera)
- `output {}` — valor que Terraform muestra al terminar
- `locals {}` — variables locales calculadas dentro del propio config

---

## Providers

Un provider es un "plugin" que enseña a Terraform a hablar con una API específica (AWS, GitHub, Kubernetes, etc.).

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"		# registro oficial de HashiCorp
      version = "~> 5.0"			# cualquier 5.x
    }
  }
}

provider "aws" {
  region = "eu-west-3"
}
```

**`~> 5.0`** significa "versión 5.x pero no 6.x" (operador *pessimistic constraint operator*). 🎓

Cuando ejecutamos `terraform init`, Terraform descarga los providers en `.terraform/`. El archivo `.terraform.lock.hcl` registra las versiones exactas descargadas.

---

## Resources

Un resource es un objeto de infraestructura que Terraform crea y gestiona.

```hcl
resource "aws_security_group" "lb" {   # "aws_security_group" = tipo
                                       # "lb" = nombre local (solo en Terraform)
  name   = "cloud1-lb-sg"
  vpc_id = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

Para referenciar un resource desde otro la notación es: `tipo.nombre_local.atributo`
- `aws_security_group.lb.id` → el ID del security group creado

---

## Data Sources

Un data source lee información de recursos que **ya existen** (no los crea).

```hcl
# Lee la VPC por defecto de la cuenta de AWS — no la crea

data "aws_vpc" "default" {
  default = true
}

# Lee las subnets de esa VPC

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}
```

Se referencian como `data.tipo.nombre.atributo`:
- `data.aws_vpc.default.id` → el ID de la VPC por defecto

---

## Variables

### Input Variables

Parámetros que se pueden configurar desde fuera:

```hcl
variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}
```

Se referencian como `var.instance_type`.

**Cómo pasar valores**:
1. Archivo `terraform.tfvars` (automático si existe)
2. Flag `-var="instance_type=t2.micro"`
3. Variable de entorno `TF_VAR_instance_type`

**Tipos de variables**:
- `string`, `number`, `bool` — tipos primitivos
- `list(string)`, `set(string)` — listas
- `map(string)` — mapas clave-valor
- `object({...})` — objetos con estructura definida
- `any` — cualquier tipo

**`sensitive = true`**: marca una variable como sensible. Terraform oculta su valor en logs y output. 
En este proyecto: `db_password`, `db_root_password`, `wp_admin_password`.

### Output Values

Valores que Terraform muestra al terminar y que pueden ser consumidos por otros módulos:

```hcl
output "lb_public_ip" {
  description = "IP pública del LB"
  value       = aws_eip.lb.public_ip
}
```

Se ven con `terraform output lb_public_ip`.

### Local Values

Valores calculados dentro de la configuración, útiles para evitar repetición:

```hcl
locals {
  common_tags = {
    Project     = var.project_name
    Environment = "production"
  }
}

# Se usan como local.common_tags
```

---

## State — El Estado de Terraform

El estado es uno de los conceptos más importante de Terraform (de los más preguntados en el examen).

### Qué es?

Terraform guarda en `terraform.tfstate` (JSON) un mapa completo entre:
- Los recursos definidos en `.tf`
- Los recursos reales que existen en cloud

```json
{
  "resources": [
    {
      "type": "aws_instance",
      "name": "db",
      "instances": [
        {
          "attributes": {
            "id": "i-0abc123def456",
            "public_ip": "35.180.xx.xx",
            ...
          }
        }
      ]
    }
  ]
}
```

### Por qué es necesario? 

Sin estado, Terraform no sabría:
- Si un recurso ya existe o hay que crearlo.
- Qué ID tiene el recurso en AWS para poder modificarlo o eliminarlo.
- Si el estado real en AWS difiere de lo que defines en `.tf`.

### Dónde se guarda?

Por defecto, en un archivo local `terraform.tfstate`. Esto es el **local backend**.

En proyectos de equipo se usa un **remote backend** (S3 + DynamoDB para AWS) que:
- Comparte el estado entre todos los miembros del equipo.
- Aplica *state locking* (DynamoDB) para evitar que dos personas apliquen cambios a la vez.
- Protege el estado (tiene permisos de acceso).

Nosotros usamos el backend local porque es un proyecto individual.

### `terraform.tfstate` está en `.gitignore`

El state puede contener secretos en texto plano (contraseñas, claves). **Nunca se commitea**. Por eso está en `.gitignore`.

### Operaciones de estado

```bash
terraform state list              # lista todos los recursos en el state
terraform state show aws_eip.lb   # muestra detalles de un recurso
terraform state rm aws_eip.lb     # elimina un recurso del state SIN borrarlo en cloud
terraform import aws_eip.lb eipalloc-xxx  # importa un recurso existente al state
```

---

## Workflow de Terraform (comandos principales).

```
terraform init → terraform plan → terraform apply → terraform destroy
```

### `terraform init`

- Descarga providers.
- Inicializa el backend.
- Crea `.terraform/` y `.terraform.lock.hcl`.
- **Hay que ejecutarlo al añadir un nuevo provider** o la primera vez.

### `terraform plan`

- Compara el state actual con la configuración `.tf`.
- Muestra qué va a crear (`+`), modificar (`~`) o destruir (`-`).
- **No modifica nada en cloud**.
- Con `-out=tfplan` guarda el plan en un archivo para aplicarlo exactamente.

### `terraform apply`

- Ejecuta el plan (o genera uno nuevo si no se usa `-out`).
- Crea/modifica/destruye recursos en cloud.
- Actualiza `terraform.tfstate`.
- Pide confirmación (`yes`) a menos que usemos `-auto-approve`.

### `terraform destroy`

- Destruye **todos** los recursos gestionados en el state.
- Equivale a `terraform apply -destroy`.

### Otros comandos útiles 🎓

```bash
terraform fmt          # formatea los archivos .tf según el estándar
terraform validate     # valida la sintaxis sin conectar a cloud
terraform output       # muestra los outputs del state actual
terraform refresh      # actualiza el state con el estado real en cloud (sin modificar)
terraform graph        # genera un grafo de dependencias en formato DOT
terraform show         # muestra el state completo en formato legible
```

---

## Dependencias

Terraform necesita saber en qué orden crear los recursos.

### Dependencias implícitas

Cuando un recurso referencia a otro, Terraform lo detecta automáticamente:

```hcl
resource "aws_eip" "lb" {
  instance = aws_instance.lb.id		# depende implícitamente de aws_instance.lb
}
```

Terraform crea primero `aws_instance.lb` y luego `aws_eip.lb`.

### Dependencias explícitas

Cuando un recurso depende de otro pero no lo referencia directamente:

```hcl
resource "null_resource" "ansible_provision" {
  depends_on = [
    local_file.ansible_inventory,	# necesita que el inventory.ini exista
    aws_eip.lb,						# necesita que el LB tenga IP
    aws_autoscaling_group.web,		# necesita que el ASG exista
  ]
}
```

---

## Meta-argumentos

Son argumentos especiales que funcionan en cualquier resource:

### `count`

Crea N copias de un recurso:

```hcl
resource "aws_instance" "web" {
  count = 3
  ami   = data.aws_ami.ubuntu.id
  # ...
}

# Se accede como: aws_instance.web[0], aws_instance.web[1], aws_instance.web[2]
```

### `for_each`

Crea una copia por cada elemento de un mapa o set:

```hcl
resource "aws_efs_mount_target" "wordpress" {
  for_each = toset(data.aws_subnets.default.ids)
  subnet_id = each.value
  # ...
}
```

### `depends_on`

Dependencia explícita (visto arriba).

### `lifecycle`

Controla cómo Terraform gestiona el ciclo de vida:

```hcl
lifecycle {
  create_before_destroy = true		# crea el nuevo antes de destruir el viejo
  prevent_destroy       = true		# error si se intenta destruir
  ignore_changes        = [tags]	# ignora cambios en tags
}
```

---

## Provisioners

Los provisioners ejecutan comandos locales o remotos **como último recurso**. HashiCorp los considera un "escape hatch" — indican que algo no puede hacerse de forma declarativa.

```hcl
resource "null_resource" "ansible_provision" {
  provisioner "local-exec" {
    command = "ansible-playbook -i inventory.ini playbook.yml"
  }
}

# Aquí vemos como ejecuta el comando para desplegar Ansible una vez que la infraestructura ya ha sido creada
```

**`local-exec`**: ejecuta en la máquina donde corre Terraform.
**`remote-exec`**: ejecuta en el recurso remoto (requiere conexión SSH).

**Por qué son problemáticos**:
- No son idempotentes por defecto.
- Si fallan, el recurso queda en estado "tainted".
- Terraform no puede saber si ya se ejecutaron.

En este proyecto los usamos porque necesitamos ejecutar Ansible (herramienta externa), que es exactamente el caso de uso legítimo.

---

## `templatefile()` — La función que usamos para cloud-init

```hcl
user_data = base64encode(templatefile("user_data.sh.tpl", {
  efs_dns_name = aws_efs_file_system.wordpress.dns_name
  s3_bucket    = aws_s3_bucket.config.id
}))
```

`templatefile(path, vars)` lee un archivo de plantilla y sustituye `${variable}` con los valores del mapa. En este proyecto lo usamos para generar el script de cloud-init con los valores reales de la infraestructura (IP de la DB, dominio de CloudFront, etc.).

**Escapado**: dentro de un templatefile, `$$` genera un `$` literal (para variables bash que no deben ser interpoladas por Terraform).

---

## `null_resource` y `triggers`

```hcl
resource "null_resource" "ejemplo" {
  triggers = {
    lb_ip = aws_eip.lb.public_ip	# se re-ejecuta si esto cambia
  }

  provisioner "local-exec" {
    command = "echo la IP cambió"
  }
}
```

`null_resource` no crea ningún recurso en cloud. Existe para ejecutar provisioners. Los `triggers` son un mapa: si algún valor cambia entre applies, el `null_resource` se re-ejecuta.

En el proyecto lo usamos para lanzar Ansible automáticamente y re-ejecutarlo si cambia la IP del LB o de la DB.

---

## `local_file` — Generar archivos locales

```hcl
resource "local_file" "ansible_inventory" {
  content  = templatefile("inventory.tpl", { ... })
  filename = "../inventory.ini"
}
```

El provider `local` de Terraform permite crear archivos en el sistema local. Lo usamos para generar `inventory.ini` con las IPs reales de las instancias después de que Terraform las crea.

---

## Funciones de Terraform

Terraform tiene funciones built-in que se usan en expresiones:

```hcl
# Cadenas
replace(var.ssh_key_path, "~", "$HOME")
"ec2-${replace(aws_eip.lb.public_ip, ".", "-")}.eu-west-3.compute.amazonaws.com"

# Encoding
base64encode(templatefile("script.sh.tpl", { ... }))
md5("contenido")

# Colecciones
toset(data.aws_subnets.default.ids)   # convierte lista a set
length(var.lista)
```

---

## Módulos

> No los usamos en el proyecto, pero son importantes para la certificación.

Un módulo es un conjunto de archivos `.tf` en un directorio que se puede reutilizar. Cualquier directorio con archivos `.tf` es un módulo.

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"		# módulo público del registry
  version = "5.0.0"

  name = "mi-vpc"
  cidr = "10.0.0.0/16"
}
```

**Módulo raíz**: el directorio desde donde ejecutamos `terraform init/apply`.
**Módulos hijo**: módulos llamados desde el módulo raíz.

Los módulos encapsulan lógica reutilizable. Por ejemplo, en vez de definir una VPC a mano, usas el módulo oficial de AWS que ya lo hace bien.

---

## Workspaces

> No los usamos en el proyecto.

Los workspaces permiten tener múltiples states para la misma configuración:

```bash
terraform workspace new staging     # crea workspace
terraform workspace select staging  # cambia a él
terraform workspace list            # lista workspaces
```

Útil para tener entornos `dev`, `staging`, `production` con la misma configuración pero diferentes states. Cada workspace tiene su propio `terraform.tfstate`.

El workspace por defecto se llama `default`.
