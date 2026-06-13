# 07 — Seguridad del Proyecto

---

## Defensa en profundidad

El proyecto implementa múltiples capas de seguridad. Si una capa falla, las demás siguen protegiendo.

```
Capa 1: Solo puertos 80, 443, 22 abiertos al exterior (SG-LB)
Capa 2: Servidores web solo accesibles desde el LB (SG-Web referencia SG-LB)
Capa 3: MariaDB solo accesible desde los servidores web (SG-DB referencia SG-Web)
Capa 4: Credenciales nunca en código (S3 privado + IAM roles)
Capa 5: HTTPS (CloudFront termina TLS)
```

---

## Security Groups: el perímetro

### Regla de referencia entre SGs

El patrón más importante de seguridad en AWS en este proyecto:

```hcl
# Los web servers solo aceptan tráfico del LB

ingress {
  from_port       = 80
  to_port         = 80
  protocol        = "tcp"
  security_groups = [aws_security_group.lb.id]   # ← SG, no una IP
}
```

Si pusiéramos la IP del LB, cuando la IP cambia habría que actualizar la regla. Con la referencia al SG, cualquier instancia que tenga el SG del LB puede conectar, independientemente de su IP.

### Lo que está bloqueado

Desde internet **no se puede**:
- Conectar a MariaDB (puerto 3306). Solo los web servers pueden.
- Conectar directamente a los web servers (puerto 80). Solo el LB puede.
- Conectar al EFS (puerto 2049). Solo los web servers pueden.

Solo están abiertos al exterior: 80 y 443 en el LB, y 22 (SSH) restringido a la IP del deployer.

### Puerto 22 (SSH)

```hcl
ingress {
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = [var.my_ip]    # solo tu IP pública → "1.2.3.4/32"
}
```

`/32` es una máscara CIDR que significa "exactamente esta IP". Nadie más puede conectarse por SSH.

---

## IAM: principio de mínimo privilegio

Las instancias web solo tienen el permiso mínimo necesario: leer objetos de un bucket S3 específico.

```json
{
  "Effect": "Allow",
  "Action": ["s3:GetObject", "s3:ListBucket"],
  "Resource": [
    "arn:aws:s3:::cloud1-web-config-ad4ca450",
    "arn:aws:s3:::cloud1-web-config-ad4ca450/*"
  ]
}
```

No pueden:
- Escribir en S3.
- Acceder a otros buckets.
- Hacer nada en EC2, EFS, u otros servicios AWS.

Si un atacante comprometiera una instancia web y obtuviera el token del IAM Role, solo podría leer ese bucket específico.

---

## Gestión de secretos

### El problema de las credenciales

Las credenciales (contraseñas de DB, admin de WordPress) deben llegar a los servidores pero no pueden estar en el código de git.

### Flujo de credenciales en el proyecto

```
terraform.tfvars (local, en .gitignore)
        │
        ├── terraform apply
        │
        ├── S3 bucket (privado) ← .env con credenciales
        │       └── cloud-init descarga → instancias web
        │
        └── inventory.ini (local, en .gitignore) ← credenciales como vars Ansible
                └── Ansible usa → instancia DB
```

**`terraform.tfvars`**: el único sitio donde podemos escribir las credenciales. Está en `.gitignore`. Nunca se commitea.

**`sensitive = true` en variables**: Terraform no muestra el valor en logs ni en output. Si alguien hace captura de pantalla del terminal, las contraseñas no aparecen.

**S3 privado**: el bucket es completamente privado. Solo las instancias con el IAM Role pueden leer de él. El `.env` con contraseñas viaja cifrado por HTTPS de S3 a la instancia.

**`inventory.ini` en `.gitignore`**: el inventario contiene IPs reales y credenciales de DB. Se genera automáticamente y nunca se commitea.

### Lo que NO hacemos (y por qué)

- **No hardcodeamos contraseñas en `.tf`**: cualquiera con acceso al repo las vería.
- **No usamos variables de entorno sin protección**: un `printenv` las expondría.
- **No pasamos credenciales por SSH**: Ansible usa el inventario que tiene vars en claro pero en la máquina local, no en el servidor.

---

## TLS / HTTPS

### Cómo funciona el cifrado en el proyecto

```
Usuario → HTTPS → CloudFront → HTTP → Nginx LB → HTTP → Nginx Web
```

CloudFront termina TLS: descifra la petición del usuario y la reenvía en HTTP (sin cifrar) al LB. Esto es aceptable porque la comunicación entre CloudFront y el LB ocurre dentro de la red de AWS, no en internet público.

### Certificado auto-firmado del LB

El LB tiene un certificado SSL auto-firmado (generado por Ansible con OpenSSL) para el puerto 443. Sirve para acceso directo al LB sin pasar por CloudFront.

**Por qué los navegadores no confían**: el certificado no está firmado por una CA (Certificate Authority) reconocida como Let's Encrypt o DigiCert. Los navegadores tienen una lista de CAs de confianza. Un certificado auto-firmado no está en esa lista → advertencia "sitio no seguro".

**Solución real**: Let's Encrypt con Certbot. Gratuito. Genera certificados firmados por una CA reconocida. Para DuckDNS necesitaría el plugin de DNS challenge.

### Campos del certificado auto-firmado

```yaml
country_name: "ES"
state_or_province_name: "Madrid"
organization_name: "42 Madrid"
organizational_unit_name: "Cloud-1"
common_name: "d1luk2m7zozc7h.cloudfront.net"
```

Aunque el navegador avise de que no es de confianza, al ver el certificado se muestran estos campos en lugar de campos vacíos. Muestra que se ha configurado correctamente.

---

## Seguridad de los contenedores Docker

### `restart: always`

Si un contenedor se cae (por un bug, por quedarse sin memoria, etc.), Docker lo reinicia automáticamente. Esto garantiza disponibilidad del servicio.

### Contenedores sin puertos expuestos innecesariamente

- WordPress FPM: solo `expose: "9000"` → solo Nginx puede conectar.
- phpMyAdmin: solo `expose: "80"` → solo Nginx puede conectar.
- MariaDB en web: solo `expose: "3306"` → invisible desde fuera.

Nadie puede conectar directamente a WordPress o phpMyAdmin saltándose Nginx.

### MariaDB: bind address

En el `docker-compose.db.yml`, MariaDB escucha en `0.0.0.0:3306` (todas las interfaces). Pero el Security Group SG-DB solo permite conexiones desde SG-Web. La seguridad la da el SG de AWS, no la configuración interna de MariaDB.

---

## Seguridad del estado de Terraform

`terraform.tfstate` puede contener contraseñas en texto plano. En el proyecto:

- Está en `.gitignore` → nunca en git.
- Es solo local → solo nosotros tendremos acceso.

En producción se usaría un **remote backend con S3 + cifrado KMS** + DynamoDB para state locking:

```hcl
terraform {
  backend "s3" {
    bucket         = "mi-terraform-state"
    key            = "cloud1/terraform.tfstate"
    region         = "eu-west-3"
    encrypt        = true        # cifrado con KMS
    dynamodb_table = "terraform-locks"  # locking
  }
}
```

---

## Resumen: qué se puede y qué no desde internet

| Desde internet | Hacia | Puede? | Por qué |
|----------------|-------|--------|---------|
| ✅ | LB:80 | Sí | SG-LB permite 0.0.0.0/0:80 |
| ✅ | LB:443 | Sí | SG-LB permite 0.0.0.0/0:443 |
| ❌ | LB:22 | Solo tu IP | SG-LB permite solo my_ip |
| ❌ | Web:80 | No | SG-Web solo permite desde SG-LB |
| ❌ | Web:22 | Solo tu IP | SG-Web permite solo my_ip |
| ❌ | DB:3306 | No | SG-DB solo permite desde SG-Web |
| ❌ | DB:22 | Solo tu IP | SG-DB permite solo my_ip |
| ❌ | EFS:2049 | No | SG-EFS solo permite desde SG-Web |
