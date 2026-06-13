# 06 — Docker, Docker Compose y cloud-init

---

## Docker

Docker es una plataforma de contenedores. Un contenedor es un proceso aislado que incluye todo lo que necesita para funcionar (código, runtime, librerías, configuración) sin depender del sistema operativo del host.

### Contenedor vs Máquina Virtual

| | Contenedor | Máquina Virtual |
|--|------------|-----------------|
| Aislamiento | Proceso del SO | SO completo |
| Tamaño | MB | GB |
| Arranque | Segundos | Minutos |
| Overhead | Mínimo | Alto |
| Aislamiento | Menos | Más |

Los contenedores comparten el kernel del host pero tienen su propio sistema de archivos, red y procesos.

### Por qué contenedores en Cloud-1

El subject exige: **1 proceso = 1 contenedor**. Cada servicio (MariaDB, WordPress PHP-FPM, Nginx, phpMyAdmin) corre en su propio contenedor independiente. Esto replica lo que se hizo en Inception, pero usando imágenes oficiales de Docker Hub en lugar de imágenes personalizadas.

---

## Imágenes Docker

Una imagen es una plantilla inmutable a partir de la cual se crean contenedores.

### Imágenes oficiales usadas

| Imagen | Versión | Qué incluye |
|--------|---------|-------------|
| `nginx:latest` | latest | Nginx web server |
| `wordpress:6-fpm` | 6.x | WordPress + PHP-FPM |
| `mariadb:10.6` | 10.6 | MariaDB database |
| `phpmyadmin:latest` | latest | phpMyAdmin UI |

**Por qué versión específica en MariaDB (`10.6`) pero `latest` en Nginx y phpMyAdmin**:
- MariaDB 10.6 es LTS (Long Term Support). Pintar la versión evita sorpresas en upgrades automáticos.
- Nginx y phpMyAdmin tienen menos cambios disruptivos entre versiones.

**`wordpress:6-fpm`**: la variante `-fpm` incluye PHP-FPM (FastCGI Process Manager) en lugar de Apache. Esto permite usar Nginx como servidor web externo que se comunica con PHP-FPM via FastCGI en el puerto 9000.

---

## Docker Compose

Docker Compose define y gestiona múltiples contenedores como una unidad.

### `docker-compose.web.yml` (instancias web)

```yaml
version: '3.8'

services:
  nginx:
    image: nginx:latest
    restart: always
    ports:
      - "80:80"             # host:contenedor
    volumes:
      - /home/ubuntu/data/wordpress:/var/www/html:ro  # bind mount, read-only
      - /home/ubuntu/data/nginx/nginx.conf:/etc/nginx/conf.d/default.conf:ro
    networks:
      - inception_network

  wordpress:
    image: wordpress:6-fpm
    restart: always
    environment:
      WORDPRESS_DB_HOST: "${db_private_ip}:3306"  # IP privada de EC2-DB
      WORDPRESS_DB_USER: ${DB_USER}                # del .env
      WORDPRESS_DB_PASSWORD: ${DB_PASSWORD}
    volumes:
      - /home/ubuntu/data/wordpress:/var/www/html  # misma carpeta que nginx (EFS)
    expose:
      - "9000"             # solo visible en la red Docker, no en el host
    networks:
      - inception_network

  phpmyadmin:
    image: phpmyadmin:latest
    restart: always
    environment:
      PMA_HOST: "${db_private_ip}"
      PMA_PORT: "3306"
    expose:
      - "80"
    networks:
      - inception_network

networks:
  inception_network:
    driver: bridge
```

### Conceptos clave de Docker Compose

**`ports` vs `expose`**:
- `ports: ["80:80"]` → mapea el puerto del contenedor al puerto del host. Accesible desde fuera.
- `expose: ["9000"]` → declara que el contenedor escucha en ese puerto, pero solo visible para otros contenedores en la misma red Docker. El host no puede acceder.

Nginx expone 80 al exterior. WordPress y phpMyAdmin solo son accesibles desde Nginx dentro de la red Docker.

**`restart: always`**: si el contenedor se para (crash, reinicio del servidor), Docker lo reinicia automáticamente. Esto es clave para la persistencia del servicio tras un reinicio de la instancia.

**`volumes`** (bind mounts):
```yaml
- /home/ubuntu/data/wordpress:/var/www/html
```
El directorio `/home/ubuntu/data/wordpress` del host se monta en `/var/www/html` dentro del contenedor. Como `/home/ubuntu/data/wordpress` está en EFS, los archivos son compartidos entre instancias.

**Red Docker (`inception_network`)**: red interna bridge. Los contenedores se comunican por nombre de servicio (`wordpress`, `phpmyadmin`) en lugar de IP. La red es privada al docker-compose.

### Comunicación Nginx → WordPress (FastCGI)

```nginx
location ~ \.php$ {
    fastcgi_pass wordpress:9000;  # "wordpress" = nombre del servicio Docker
    ...
}
```

Nginx pasa las peticiones PHP al contenedor WordPress via FastCGI. `wordpress:9000` funciona porque Docker resuelve el nombre `wordpress` a la IP del contenedor dentro de la red `inception_network`.

### Comunicación Nginx → phpMyAdmin (reverse proxy)

```nginx
location /phpmyadmin/ {
    proxy_pass http://phpmyadmin/;
}
```

Las peticiones a `/phpmyadmin/` se redirigen al contenedor phpMyAdmin.

---

## `docker-compose.lb.yml` (instancia LB)

```yaml
services:
  nginx-lb:
    image: nginx:latest
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /home/ubuntu/lb/nginx.conf:/etc/nginx/conf.d/default.conf:ro
      - /home/ubuntu/lb/ssl:/etc/nginx/ssl:ro
```

Solo Nginx, sin otros servicios. Los volúmenes montan la configuración de nginx y los certificados SSL.

---

## `docker-compose.db.yml` (instancia DB)

```yaml
services:
  mariadb:
    image: mariadb:10.6
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: ${DB_ROOT_PASSWORD}
      MYSQL_DATABASE: ${DB_NAME}
      MYSQL_USER: ${DB_USER}
      MYSQL_PASSWORD: ${DB_PASSWORD}
    volumes:
      - /home/ubuntu/data/mariadb:/var/lib/mysql
    ports:
      - "3306:3306"   # expuesto al host para que los web servers conecten
```

A diferencia de los web servers donde MariaDB usaba `expose`, aquí usamos `ports` para que la IP privada de EC2-DB sea accesible desde las otras instancias via el puerto 3306.

**`/home/ubuntu/data/mariadb:/var/lib/mysql`**: los datos de MariaDB se guardan en el host. Si el contenedor se reinicia, los datos persisten.

---

## cloud-init (`user_data.sh.tpl`)

cloud-init es el estándar de la industria para inicialización de instancias cloud en el primer arranque.

### Cuándo se ejecuta

Una sola vez: la primera vez que la instancia arranca. Si la instancia se reinicia, cloud-init no vuelve a ejecutarse (a menos que los metadatos indiquen lo contrario).

### Cómo AWS lo gestiona

Cuando Terraform crea el Launch Template, incluye el script cloud-init como `user_data` (codificado en base64). Cuando el ASG crea una nueva instancia a partir de ese template, AWS pasa el user_data a la instancia a través del *Instance Metadata Service* (IMDS). cloud-init lo lee y lo ejecuta.

### Secuencia del script en el proyecto

```bash
# 1. Instalar dependencias
apt-get install -y docker.io nfs-common awscli openssl

# 2. Instalar Docker Compose
curl -fsSL "https://github.com/docker/compose/.../docker-compose-linux-x86_64" -o /usr/local/bin/docker-compose

# 3. Crear directorios
mkdir -p /home/ubuntu/data/wordpress /home/ubuntu/inception

# 4. Montar EFS (con reintentos)
for i in $(seq 1 10); do
  if mount -t nfs4 "${efs_dns_name}:/" /home/ubuntu/data/wordpress; then
    break
  fi
  sleep 15
done
# Añadir al fstab para persistir tras reinicios

# 5. Descargar configuración de S3 (con reintentos)
for i in $(seq 1 10); do
  if aws s3 cp s3://${s3_bucket}/docker-compose.web.yml /home/ubuntu/inception/docker-compose.yml; then
    break
  fi
  sleep 10
done

# 6. Generar certificado SSL auto-firmado
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /home/ubuntu/data/nginx/ssl/server.key \
  -out /home/ubuntu/data/nginx/ssl/server.crt

# 7. Arrancar contenedores
docker-compose up -d

# 8. Esperar wp-config.php (WordPress inicializa la BD y genera este fichero)
for i in $(seq 1 24); do
  if [ -f /home/ubuntu/data/wordpress/wp-config.php ]; then break; fi
  sleep 5
done

# 9. Patch wp-config.php
sed -i "..." $WPCONFIG   # añade WP_HOME, WP_SITEURL, WP_CONTENT_URL

# 10. Instalar WP-CLI y auto-instalar WordPress
docker exec -u root wordpress bash -c "
  curl -o /usr/local/bin/wp https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
  chmod +x /usr/local/bin/wp
"
if ! docker exec wordpress wp core is-installed --allow-root; then
  docker exec wordpress wp core install \
    --url="https://${cloudfront_domain}" \
    --title="${wp_title}" \
    --admin_user="${wp_admin_user}" \
    --admin_password="${wp_admin_password}" \
    ...
fi
```

### Por qué los reintentos en EFS y S3

Al arrancar una instancia, es posible que:
- El EFS Mount Target no esté todavía en estado `available`.
- El IAM Role no se haya propagado completamente (puede tardar varios segundos).

Los bucles con `sleep` son una solución simple y robusta para estas condiciones de carrera.

### WP-CLI en Docker

WP-CLI es la herramienta de línea de comandos oficial de WordPress. Permite instalar WordPress, crear usuarios, instalar plugins, etc. desde la terminal.

```bash
docker exec -u root wordpress wp core install \
  --url="https://xxx.cloudfront.net" \
  --admin_user="admin" \
  --admin_password="password" \
  --allow-root
```

`docker exec -u root wordpress` ejecuta un comando dentro del contenedor `wordpress` como usuario `root`. `wp core is-installed` comprueba si WordPress ya está instalado — si lo está (porque otra instancia del ASG ya lo instaló en EFS), no lo instala de nuevo.

### `$${i}` vs `${variable}` en templates Terraform

En el script de cloud-init, que es un template Terraform:

```bash
for i in $(seq 1 10); do       # $(seq ...) — bash, no interpolado por Terraform
  echo "intento $i"             # $i — bash variable, no interpolado (sin llaves)
  echo "intento $${i}x5s"      # $${i} → genera ${i} literal (solo si hubiera llaves)
  mount "${efs_dns_name}:/"     # ${efs_dns_name} — INTERPOLADO por Terraform
done
```

Terraform solo interpola `${...}` con llaves. La variable bash `$i` (sin llaves) no la interpola. Solo hay que escapar con `$$` cuando usas llaves: `$${i}` genera `${i}` literal en bash.

---

## `wp-config.php` — Configuración de WordPress

WordPress lee su configuración de este archivo PHP. Lo parcha cloud-init para adaptar WordPress al entorno cloud:

```php
// CLOUD1 MANAGED BLOCK
define( 'WP_HOME', 'https://' . $_SERVER['HTTP_HOST'] );
define( 'WP_SITEURL', 'https://' . $_SERVER['HTTP_HOST'] );
define( 'WP_CONTENT_URL', 'https://d1abc.cloudfront.net/wp-content' );
// END CLOUD1 MANAGED BLOCK
```

**`$_SERVER['HTTP_HOST']`**: usa el host de la petición actual. Así WordPress funciona con cualquier URL (la de CloudFront, la IP directa del LB, etc.) sin hardcodear ninguna.

**`WP_CONTENT_URL`**: dice a WordPress dónde están los assets estáticos. Al apuntar a CloudFront, los links de CSS/JS/imágenes en el HTML generado por WordPress apuntarán a la CDN.
