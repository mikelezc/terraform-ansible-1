# 08 — Hoja de Ruta: Terraform Associate Certification

---

## Sobre el examen

**Nombre oficial**: HashiCorp Certified: Terraform Associate (003)
**Precio**: ~$70 USD
**Duración**: 60 minutos
**Preguntas**: ~57 (opción múltiple, verdadero/falso, completar código)
**Nota mínima para aprobar**: 70%
**Validez**: 2 años

Es un examen de nivel Associate — se evalúan conocimientos prácticos de Terraform, no arquitecturas avanzadas. Con el proyecto Cloud-1 tienes una base sólida.

---

## Dominios del examen

| Dominio | Peso aproximado |
|---------|----------------|
| 1. Conceptos de IaC | 9% |
| 2. Propósito de Terraform | 9% |
| 3. Conceptos básicos de Terraform | 26% |
| 4. Terraform CLI | 20% |
| 5. Módulos | 12% |
| 6. Flujo de trabajo | 9% |
| 7. Estado | 15% |

---

## Qué cubre el proyecto Cloud-1 del examen

### ✅ Cubierto en el proyecto

**Dominio 1: Conceptos de IaC**
- Beneficios de IaC sobre configuración manual ✅
- Diferencia entre declarativo (Terraform) e imperativo (Ansible) ✅
- Idempotencia ✅

**Dominio 2: Propósito de Terraform**
- Multi-cloud provisioning ✅
- Gestionar el ciclo de vida de infraestructura ✅
- Terraform vs otras herramientas ✅

**Dominio 3: Conceptos básicos**
- Providers y su configuración ✅
- Resources ✅
- Data sources ✅
- Variables (input, output, local) ✅
- Variables sensibles (`sensitive = true`) ✅
- Tipos de variables (string, number, list, map) ✅
- `count` y `for_each` ✅
- `depends_on` ✅
- `lifecycle` (create_before_destroy) ✅
- Provisioners (local-exec) ✅
- Funciones built-in: `templatefile`, `base64encode`, `replace`, `toset`, `md5` ✅
- `.terraform.lock.hcl` ✅

**Dominio 4: Terraform CLI**
- `terraform init` ✅
- `terraform plan` (con y sin `-out`) ✅
- `terraform apply` ✅
- `terraform destroy` ✅
- `terraform output` ✅
- `terraform fmt` (no lo usamos explícitamente pero lo conocemos) ✅
- `terraform validate` ✅

**Dominio 6: Flujo de trabajo**
- Write → Plan → Apply ✅
- `terraform destroy` para limpieza ✅

**Dominio 7: Estado**
- Qué es el state file ✅
- Por qué no se commitea ✅
- Local backend ✅

---

## ❌ Conceptos del examen NO cubiertos en el proyecto



### Módulos (Dominio 5 — 12%)

**Qué es**: un módulo es un directorio de `.tf` reutilizable. El examen pregunta mucho sobre cómo llamar módulos, pasar variables, y los módulos del Terraform Registry.

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.0.0"
  name    = "mi-vpc"
  cidr    = "10.0.0.0/16"
}

# Acceder a outputs de un módulo:

output "vpc_id" {
  value = module.vpc.vpc_id
}
```

**Fuentes de módulos**:
- Terraform Registry: `"terraform-aws-modules/vpc/aws"`
- GitHub: `"git::https://github.com/org/repo.git"`
- Local: `"./modules/vpc"`

**Preguntas típicas**: ¿Qué comando actualiza los módulos tras cambiar la versión? (`terraform init -upgrade`). ¿Cómo referencias el output de un módulo hijo desde el módulo raíz?

### Workspaces (Dominio 7)

```bash
terraform workspace new staging
terraform workspace list
terraform workspace select staging
terraform workspace show    # workspace actual
```

**Uso**: misma configuración, múltiples states. `dev`, `staging`, `prod` con el mismo código pero diferente infraestructura.

**Dentro del código**:
```hcl
resource "aws_instance" "web" {
  count = terraform.workspace == "prod" ? 3 : 1
}
```

### Remote Backends (Dominio 7)

El examen pregunta mucho sobre backends remotos. El más común: S3 + DynamoDB.

```hcl
terraform {
  backend "s3" {
    bucket         = "mi-terraform-state"
    key            = "cloud1/terraform.tfstate"
    region         = "eu-west-3"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}
```

**Conceptos clave**:
- **State locking**: DynamoDB evita que dos personas apliquen cambios simultáneamente.
- **`terraform init` con backend**: al cambiar de backend hay que hacer `terraform init` de nuevo.
- **`terraform state pull`**: descarga el state remoto.
- **`terraform state push`**: sube el state local al backend remoto.

### Terraform Cloud (Dominio 2 y 7)

Terraform Cloud es la plataforma SaaS de HashiCorp. El examen toca los conceptos básicos:
- Remote runs (los plans y applies corren en Terraform Cloud, no en tu máquina).
- Almacenamiento del state en Terraform Cloud.
- Variables en Terraform Cloud (sensibles y no sensibles).
- Free tier: hasta 5 usuarios, plans/applies ilimitados.

### `terraform taint` y `terraform untaint`

> Deprecated en Terraform >= 0.15.2, reemplazado por `terraform apply -replace`.

```bash
# Fuerza la recreación de un recurso en el siguiente apply:
terraform apply -replace="aws_instance.db"
```

El examen puede preguntar sobre esto.

### `terraform import`

Importa un recurso existente en AWS al state de Terraform sin recrearlo:

```bash
terraform import aws_instance.db i-0abc123def456789
```

Útil cuando ya tienes infraestructura creada manualmente y quieres gestionarla con Terraform.

### `terraform refresh`

Actualiza el state con el estado real en cloud (sin modificar nada). En versiones recientes está integrado en `plan` y `apply` por defecto.

```bash
terraform apply -refresh-only   # actualiza el state sin aplicar cambios
```

### Expresiones más avanzadas

```hcl
# Condicional ternario
count = var.create_resource ? 1 : 0

# for expressions
locals {
  instance_ids = [for i in aws_instance.web : i.id]
}

# dynamic blocks
dynamic "ingress" {
  for_each = var.puertos
  content {
    from_port = ingress.value
    to_port   = ingress.value
    protocol  = "tcp"
  }
}
```

### Comandos de state que el examen pregunta

```bash
terraform state list                        # lista recursos en state
terraform state show aws_instance.db        # detalles de un recurso
terraform state mv aws_instance.old aws_instance.new  # renombrar en state
terraform state rm aws_instance.db          # quitar del state (sin borrar en cloud)
```

---

## Plan de estudio recomendado

### Semana 1: Consolidar lo del proyecto

1. Lee `02_terraform_core.md` y `03_terraform_archivos.md` de estos apuntes.
2. Abre cada archivo `.tf` del proyecto y asegúrate de entender cada línea.
3. Haz `terraform apply` y `terraform destroy` varias veces. Observa el output.
4. Lee la documentación oficial de cada recurso que usamos: `aws_autoscaling_group`, `aws_cloudfront_distribution`, `aws_efs_file_system`, etc.

### Semana 2: Conceptos que faltan

1. **Módulos**: estudia la documentación oficial. Crea un módulo simple.
2. **Workspaces**: practica `terraform workspace new/select/list`.
3. **Remote backends**: lee la documentación de S3 backend. Entiende el locking.
4. **Funciones**: practica con `terraform console`:
   ```bash
   terraform console
   > length(["a", "b", "c"])
   > toset(["a", "b", "a"])
   > cidrsubnet("10.0.0.0/16", 8, 0)
   ```

### Semana 3: Exámenes de práctica

1. Haz el examen de práctica de **Bryan Krausen** en Udemy (~250 preguntas).
2. Revisa cada pregunta que falles — entiende por qué.
3. Repasa ExamTopics (gratis, preguntas reales filtradas por la comunidad).
4. Repite hasta superar el 85% en los simulacros.

---

## Comandos que debes dominar para el examen

```bash
# Inicialización
terraform init                    # primera vez o tras añadir providers/modules
terraform init -upgrade           # actualiza providers y módulos a versiones recientes
terraform init -reconfigure       # fuerza reconfigar el backend

# Plan y apply
terraform plan
terraform plan -out=tfplan        # guarda el plan
terraform apply                   # genera plan + aplica
terraform apply tfplan            # aplica plan guardado
terraform apply -auto-approve     # sin confirmación
terraform apply -replace="recurso.nombre"  # fuerza recreación de un recurso

# Destruir
terraform destroy
terraform destroy -target=aws_instance.db  # destruye solo un recurso

# Estado
terraform state list
terraform state show recurso.nombre
terraform state mv recurso.old recurso.new
terraform state rm recurso.nombre
terraform state pull > backup.tfstate     # backup del state
terraform import recurso.nombre id_en_cloud

# Formato y validación
terraform fmt                    # formatea todos los .tf del directorio
terraform fmt -recursive         # formatea también subdirectorios
terraform validate               # valida sintaxis (sin conectar a cloud)

# Output
terraform output
terraform output -json           # output en JSON
terraform output -raw nombre     # valor sin formato (para scripts)

# Workspaces
terraform workspace list
terraform workspace new nombre
terraform workspace select nombre
terraform workspace show
terraform workspace delete nombre

# Consola interactiva
terraform console                # REPL para probar expresiones y funciones

# Graph
terraform graph | dot -Tsvg > graph.svg  # genera diagrama de dependencias
```

---

## Trampas comunes en el examen

### 1. `terraform apply` sin `-out`

El mensaje "You didn't use -out" NO es un error, es un warning informativo. Terraform puede aplicar igual.

### 2. `count` vs `for_each`

- `count = 0` → no crea el recurso (pero sigue existiendo en la config).
- `for_each = {}` → no crea ninguna instancia.
- `count` usa índices numéricos; `for_each` usa claves del mapa/set.
- Si borras un elemento del medio de una lista con `count`, los índices cambian → Terraform recrea todos los recursos posteriores. `for_each` con claves estables evita este problema.

### 3. Providers en módulos

Los módulos heredan el provider del módulo raíz por defecto. Si un módulo necesita un provider diferente, se pasa explícitamente con el bloque `providers`.

### 4. `terraform destroy` y `prevent_destroy`

```hcl
lifecycle {
  prevent_destroy = true
}
```

Si un recurso tiene `prevent_destroy = true`, `terraform destroy` falla. Hay que quitarlo antes.

### 5. State locking

Si un `terraform apply` se interrumpe en mitad de la ejecución, puede dejar el state bloqueado. Hay que desbloquearlo manualmente:
```bash
terraform force-unlock LOCK_ID
```

### 6. `sensitive` no cifra, solo oculta

`sensitive = true` hace que Terraform no muestre el valor en logs. Pero en el `terraform.tfstate` sigue estando en texto plano. La seguridad real está en proteger el state file.

---

## Recursos de estudio

| Recurso | Coste | Para qué |
|---------|-------|---------|
| Documentación oficial (developer.hashicorp.com/terraform) | Gratis | Referencia completa |
| Curso de Bryan Krausen en Udemy | ~10€ | Aprendizaje estructurado |
| Exámenes de práctica de Bryan Krausen (Udemy) | ~10€ | **Imprescindible** para el examen |
| ExamTopics Terraform Associate | Gratis | Preguntas reales de la comunidad |
| `terraform console` | Gratis | Practicar funciones |
| Terraform Registry (registry.terraform.io) | Gratis | Ver módulos y providers |
