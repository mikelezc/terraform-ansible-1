# Guía de preparación: evaluación en ordenador de 42

Este documento explica qué necesitas tener en el ordenador de 42 para poder desplegar el proyecto y qué credenciales debes llevar contigo.

---

## Resumen rápido

Los ordenadores de 42 no tienen `terraform`, `ansible` ni `aws` instalados y no tienes permisos para instalarlos. La solución es usar **Docker**, que sí está disponible: construyes una imagen con todas las herramientas y trabajas dentro del contenedor.

Necesitas llevar tres cosas al ordenador de 42:

| Qué | Formato | Dónde obtenerlo |
|-----|---------|-----------------|
| Credenciales AWS | Fichero `~/.aws/credentials` o dos claves (Access Key ID + Secret) | AWS Console → Security credentials |
| Clave SSH privada | `cloud-1-key.pem` | AWS Console → EC2 → Key Pairs (la descargaste al crear el par) |
| Variables del proyecto | `terraform.tfvars` | Tu ordenador personal (contiene contraseñas) |

---

## Parte 1: preparar en casa antes de ir a 42

### 1.1 Credenciales AWS

Las credenciales AWS son dos valores: un **Access Key ID** (empieza por `AKIA…`) y un **Secret Access Key** (cadena larga). Terraform y AWS CLI los necesitan para crear recursos en tu cuenta.

**Cómo obtenerlos:**

1. Entra en [console.aws.amazon.com](https://console.aws.amazon.com) con tu cuenta.
2. Clic en tu nombre (arriba a la derecha) → **Security credentials**.
3. Baja a la sección **Access keys** → **Create access key**.
4. Elige **Command Line Interface (CLI)** → Next → Create.
5. **Descarga el `.csv`** — el Secret solo se muestra esta vez.

Cuando configures `aws configure` en casa quedará guardado en `~/.aws/credentials`:

```
[default]
aws_access_key_id     = AKIAIOSFODNN7EXAMPLE
aws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
```

**Lleva a 42** ese fichero `~/.aws/credentials` (y `~/.aws/config` si existe) en un USB o apunta los valores en algún sitio seguro.

> Si ya tienes las claves creadas y sabes los valores, no hace falta generar unas nuevas.

---

### 1.2 Clave SSH privada (`cloud-1-key.pem`)

Es el fichero que permite que Ansible acceda por SSH a las instancias EC2. Si ya lo tienes en `~/.ssh/cloud-1-key.pem` en tu ordenador, llévatelo en el USB.

**Si no lo tienes o lo perdiste**, no puedes regenerarlo desde AWS (AWS solo guarda la parte pública). Tendrás que:

1. Ir a AWS Console → EC2 → Key Pairs → selecciona `cloud-1-key` → Actions → **Delete**.
2. Crear uno nuevo: **Create key pair** → nombre `cloud-1-key`, formato `.pem` → guarda el fichero.
3. El nombre debe ser exactamente `cloud-1-key` porque así está referenciado en el código Terraform.

---

### 1.3 Fichero `terraform.tfvars`

Está en `42_Cloud-1/terraform/terraform.tfvars` y **no está en git** (es secreto). Llévalo también en el USB, pero ten en cuenta que **deberás editarlo en 42** porque contiene tu IP pública (`my_ip`) que cambiará.

Si no tienes el fichero, puedes recrearlo desde el ejemplo:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Y rellenar los valores que conoces (contraseñas, etc.).

---

### 1.4 Lista de comprobación antes de salir de casa

```
[ ] USB o método de transferencia preparado
[ ] ~/.aws/credentials  (o los valores anotados: Access Key ID + Secret)
[ ] ~/.ssh/cloud-1-key.pem
[ ] 42_Cloud-1/terraform/terraform.tfvars
[ ] El proyecto completo (o acceso a GitHub para clonarlo)
```

---

## Parte 2: en el ordenador de 42

### 2.1 Verificar que Docker está disponible

```bash
docker --version
# Docker version 24.x.x, build ...
```

Si no aparece, avisa al staff (es raro, Docker es estándar en los iMacs de 42).

---

### 2.2 Obtener el proyecto

**Opción A — desde git:**

```bash
git clone https://github.com/TU_USUARIO/TU_REPO.git ~/cloud-1
cd ~/cloud-1/42_Cloud-1
```

**Opción B — desde USB:**

```bash
cp -r /Volumes/USB/cloud-1 ~/cloud-1
cd ~/cloud-1/42_Cloud-1
```

---

### 2.3 Colocar las credenciales

```bash
# Credenciales AWS
mkdir -p ~/.aws
cp /Volumes/USB/credentials ~/.aws/credentials
# O, si solo tienes los valores, configúralos directamente:
aws configure   # (si tienes aws instalado) — si no, hazlo dentro del contenedor (ver 2.5)

# Clave SSH
mkdir -p ~/.ssh
cp /Volumes/USB/cloud-1-key.pem ~/.ssh/cloud-1-key.pem
chmod 400 ~/.ssh/cloud-1-key.pem

# terraform.tfvars
cp /Volumes/USB/terraform.tfvars ~/cloud-1/42_Cloud-1/terraform/terraform.tfvars
```

---

### 2.4 Actualizar tu IP pública en terraform.tfvars

**Esto es obligatorio.** La IP de 42 es diferente a la de tu casa. El Security Group de AWS solo permite SSH desde la IP configurada en `my_ip`, y Ansible necesita SSH para funcionar.

```bash
# Obtener la IP pública del ordenador de 42:
curl -s ifconfig.me
# → p.ej. 195.77.12.34

# Editar terraform.tfvars:
nano ~/cloud-1/42_Cloud-1/terraform/terraform.tfvars
# Cambia la línea: my_ip = "195.77.12.34/32"
```

> Si ya tienes la infraestructura desplegada desde casa, necesitas hacer `terraform apply` para actualizar el Security Group con la nueva IP antes de poder ejecutar Ansible.

---

### 2.5 Construir el contenedor de herramientas

La primera vez tarda ~3 minutos mientras descarga e instala Terraform, Ansible y AWS CLI:

```bash
cd ~/cloud-1/42_Cloud-1
chmod +x docker/cloud1-tools.sh
./docker/cloud1-tools.sh
```

Esto construye la imagen `cloud1-tools` y abre una **bash interactiva dentro del contenedor**. El proyecto queda montado en `/workspace`, las credenciales AWS en `/root/.aws` y la clave SSH en `/root/.ssh/cloud-1-key.pem`.

Si tu clave `.pem` está en una ruta diferente a `~/.ssh/cloud-1-key.pem`:

```bash
AWS_KEY_PATH=/ruta/a/tu/cloud-1-key.pem ./docker/cloud1-tools.sh
```

---

### 2.6 Configurar AWS CLI (solo si no tienes ~/.aws/credentials)

Dentro del contenedor:

```bash
aws configure
# AWS Access Key ID:     AKIAIOSFODNN7EXAMPLE
# AWS Secret Access Key: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
# Default region name:   eu-west-3
# Default output format: json
```

Esto escribe en `/root/.aws/credentials` dentro del contenedor. Para que persista en el host (y no tener que repetirlo), es mejor tener ya el fichero en `~/.aws/credentials` antes de lanzar el contenedor (se monta en modo lectura).

---

### 2.7 Desplegar el proyecto

Una vez dentro del contenedor en `/workspace`:

```bash
# Ir a la carpeta terraform
cd terraform

# Primera vez: descargar los plugins de Terraform
terraform init

# (Opcional) Ver qué se va a crear
terraform plan

# Crear toda la infraestructura (~20 min por CloudFront)
terraform apply
```

Terraform al terminar:
- Muestra la URL de CloudFront y las IPs de las instancias.
- Genera automáticamente `ansible/inventory.ini`.
- Lanza Ansible automáticamente para configurar LB y DB.

Espera ~5 minutos a que las instancias web terminen su cloud-init. Luego accede a la URL de CloudFront.

Para más detalles del despliegue consulta el [README.md](README.md).

---

## Parte 3: referencia rápida de credenciales

### ¿Qué es cada credencial y para qué sirve?

| Credencial | Para qué sirve | ¿Es secreta? |
|-----------|----------------|--------------|
| **AWS Access Key ID** (`AKIA…`) | Identifica tu cuenta ante AWS (Terraform + AWS CLI) | No especialmente, pero no la publiques |
| **AWS Secret Access Key** | Contraseña de la clave anterior — permite crear/borrar recursos en tu cuenta | **Sí, trátala como una contraseña** |
| **`cloud-1-key.pem`** | Clave privada SSH para conectarse a las EC2 | **Sí, nunca la subas a git** |
| **`terraform.tfvars`** | Contraseñas de BD, WordPress, tu IP | **Sí, está en .gitignore** |

### Dónde vive cada cosa en el sistema de ficheros

```
~/.aws/credentials          ← Access Key ID + Secret Access Key
~/.aws/config               ← región por defecto (eu-west-3)
~/.ssh/cloud-1-key.pem      ← clave privada SSH (permisos: 400)
42_Cloud-1/terraform/terraform.tfvars  ← variables secretas del proyecto
```

---

## Solución de problemas frecuentes

**`Permission denied (publickey)` al ejecutar Ansible**
- Verifica que `cloud-1-key.pem` tiene permisos 400: `chmod 400 ~/.ssh/cloud-1-key.pem`
- Verifica que el key pair en AWS se llama exactamente `cloud-1-key` (en eu-west-3)

**`Error: No valid credential sources found`**
- Las credenciales AWS no están disponibles dentro del contenedor
- Comprueba que `~/.aws/credentials` existe en el host y que el script lo monta correctamente

**`Connection timed out` al hacer SSH desde Ansible**
- Tu IP pública en `my_ip` no coincide con la IP del ordenador de 42
- Obtén la IP real con `curl ifconfig.me` y actualiza `terraform.tfvars`
- Si la infra ya está desplegada: `terraform apply` desde dentro del contenedor para actualizar el Security Group

**`docker: command not found`**
- Docker no está instalado en ese iMac — prueba con otro o contacta al staff

**La imagen Docker tarda mucho en construirse**
- Normal la primera vez (~3 min). Las siguientes veces usa la caché y arranca en segundos.
- Si hay problemas de red, espera un momento y vuelve a intentarlo.
