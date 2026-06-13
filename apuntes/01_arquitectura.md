# 01 — Arquitectura del Sistema

## El problema que resuelve Cloud-1

En el proyecto del que partí para hacer este, fué "Inception" (el cuál puede encontrar en mi GitHub) en aquél proyecto, levantamos WordPress en un único servidor. 
Eso tiene un problema fundamental: si ese servidor cae, el sitio cae con él. No tenemos alta disponibilidad, no puede escalar, por lo tanto el servidor es un punto único de fallo (*Single Point of Failure*, SPOF).

En Cloud-1 resolvemos esto distribuyendo la carga entre varias máquinas (EC2) y añadiendo mecanismos de recuperación automática. El resultado es una infraestructura con:

- **Alta disponibilidad**: si un servidor web cae, los demás absorben el tráfico.
- **Escalabilidad horizontal**: podemos añadir más servidores web simplemente cambiando el valor de una variable.
- **CDN**: los assets estáticos se podrían servir desde nodos cercanos al usuario usando Cloudfront.
- **Base de datos separada**: la DB no comparte máquina con los servidores web pudiendo desacoplarla para dar servicio al número de instancias que necesitemos lanzar.

---

## Diagrama de arquitectura

```
                        INTERNET
                           │
                           ▼
              ┌─────────────────────────┐
              │   AWS CloudFront (CDN)  │
              │   Cachea /wp-content/*  │
              │   Termina HTTPS         │
              └────────────┬────────────┘
                           │ HTTP (puerto 80)
                           ▼
              ┌─────────────────────────┐
              │  EC2-LB                 │
              │  Nginx Load Balancer    │  ← Elastic IP (IP fija)
              │  Puertos: 80, 443       │
              └──────┬──────────┬───────┘
                     │          │  Round-robin
           ┌─────────┘          └──────────┐
           ▼                               ▼
  ┌─────────────────┐          ┌─────────────────┐
  │  EC2-Web-1      │          │  EC2-Web-2      │
  │  Nginx (rev.    │          │  Nginx (rev.    │
  │  proxy)         │          │  proxy)         │
  │  WordPress FPM  │          │  WordPress FPM  │
  │  phpMyAdmin     │          │  phpMyAdmin     │
  └────────┬────────┘          └────────┬────────┘
           │                            │
           └────────────┬───────────────┘
                        │ puerto 3306 (privado)
                        ▼
              ┌─────────────────────────┐
              │  EC2-DB                 │
              │  MariaDB                │
              └─────────────────────────┘

  EFS ──── montado en /home/ubuntu/data/wordpress
           en EC2-Web-1 Y EC2-Web-2

  S3  ──── configuración que cloud-init descarga al arrancar
```

---

## Componentes usados en AWS

### CloudFront — CDN

**Qué es**: red de distribución de contenido de AWS. Tiene nodos (*edge locations*) en todo el mundo. Cuando un usuario pide un archivo, CloudFront lo sirve desde el nodo más cercano en lugar de desde el servidor de origen.

**Por qué se ha usado**:
- El subject exige un mecanismo CDN.
- Los assets estáticos de WordPress (`/wp-content/themes/*/style.css`, imágenes) son los mismos para todos los usuarios. Tiene sentido cachearlos.
- CloudFront termina HTTPS: el usuario ve el certificado aunque el LB use HTTP internamente.

**Cómo está configurado**:
- Origen: la IP pública del EC2-LB.
- Comportamiento por defecto: sin caché (contenido dinámico como páginas WP).
- Comportamientos específicos: `/wp-content/*` y `/wp-includes/*` con caché de 1 día.
- `WP_CONTENT_URL` en `wp-config.php` apunta a la URL de CloudFront para que WordPress use el CDN para sus assets.

---

### EC2-LB — Nginx Load Balancer

**Qué es**: una instancia EC2 con Nginx corriendo en Docker, actuando como balanceador de carga.

**Por qué Nginx y no el ALB de AWS**:
- AWS Application Load Balancer (ALB) no tiene free tier y cuesta ~$0.016/hora.
- Nginx en una EC2 t3.micro entra en el free tier (750 horas/mes).
- Nginx es el mismo servidor del proyecto Inception, por lo tanto, aunque resulta más complejo de desarrollar que el ALB nativo de AWS, he pensado que ejemplifica mejor como podría ser una refactorización directa real partiendo de la arquitectura previa.

**Cómo funciona el balanceo**:
```nginx
upstream wordpress_backends {
    server 172.31.x.x:80 max_fails=3 fail_timeout=30s;
    server 172.31.y.y:80 max_fails=3 fail_timeout=30s;
}
```
Nginx distribuye las peticiones en *round-robin* (una a cada backend por turno). Con `max_fails=3 fail_timeout=30s`, si un backend falla 3 veces en 30 segundos, Nginx lo marca como inactivo y deja de enviarle tráfico (*passive health check*).

**Elastic IP**: la EC2-LB tiene una IP pública fija. Esto es importante porque CloudFront necesita un origen estable, y si configuramos DuckDNS para obtener un DNS para nuestro proyecto (como veremos más adelante), lo apuntaremos a esta IP.

---

### EC2-Web-1 y EC2-Web-2 (Servidores Web)

**Qué son**: instancias EC2 gestionadas por un Auto Scaling Group (ASG) de AWS. Cada una corre en Docker:
- **Nginx**: metemos otro nginx por instancia (a parte del del nodo que usamos como LB) este actúa como reverse proxy, recibe peticiones del LB y las pasa a WordPress FPM.
- **WordPress PHP-FPM**: procesa las peticiones PHP.
- **phpMyAdmin**: interfaz web para la base de datos.

**Por qué PHP-FPM**:
- PHP-FPM (FastCGI Process Manager) es un gestor de procesos PHP independiente de Nginx. Permite escalar los workers PHP por separado.
- El protocolo entre Nginx y PHP-FPM es FastCGI (puerto 9000).

**Por qué están en un Auto Scaling Group**:
- El ASG mantiene siempre un mínimo de 2 instancias.
- Si una instancia falla, el ASG la termina y lanza una nueva automáticamente.
- Permite escalar: `terraform apply -var="web_desired=4"` añade 2 instancias más sin tocar nada manual.

**Cómo se configuran solas (cloud-init)**:
Al arrancar, cada instancia ejecuta un script (`user_data.sh.tpl`) que:
1. Instala Docker.
2. Monta el EFS.
3. Descarga la configuración (docker-compose.yml, nginx.conf, .env) del bucket S3.
4. Arranca los contenedores.
5. Instala WP-CLI y, si WordPress no está instalado, lo instala automáticamente.

---

### EC2-DB — Base de Datos

**Qué es**: una instancia EC2 con MariaDB corriendo en Docker.

**Por qué separada de los servidores web**:
- Separar la DB es lo que tiene sentido en nuestra arquitectura porque los servidores web pueden escalar horizontalmente mientras la DB permanece estable.
- Permite aplicar diferentes Security Groups: el puerto 3306 solo es accesible desde los servidores web, nunca desde internet.

**Por qué MariaDB y no RDS**:
- RDS (Relational Database Service de AWS) es una base de datos gestionada. Tiene réplicas automáticas, backups, etc.
- Para este proyecto de 42, RDS tendría coste y complejidad innecesarios.
- MariaDB en Docker con volumen local da la misma funcionalidad a nivel de proyecto y además es similar al proyecto Inception del que partíamos.

---

### EFS — Almacenamiento Compartido

**Qué es**: Elastic File System, un sistema de archivos de red de AWS basado en NFS.

**El problema que resuelve**:
Si el usuario de WordPress sube una imagen, esa imagen se guarda en `/wp-content/uploads/` del servidor web que atendió la petición. Cuando el LB envía la siguiente petición al otro servidor, ese servidor no tiene la imagen → el sitio falla.

EFS resuelve esto: ambos servidores web montan el mismo sistema de archivos en `/home/ubuntu/data/wordpress`. Cuando uno escribe un archivo, el otro lo ve inmediatamente.

**Podemos usarlo en free tier**: 5 GB de almacenamiento estándar al mes (da de sobra para desplegar este proyecto sin incurrir en gastos).

---

### S3 — Repositorio de Configuración

**Qué es**: Simple Storage Service, almacenamiento de objetos de AWS.

**El problema que resuelve**:
Las instancias web se crean automáticamente por el ASG y necesitan su configuración (docker-compose.yml, nginx.conf, .env). Ansible no configura las instancias web directamente. La solución aplicada sería por tanto: Terraform renderiza los archivos de configuración con las variables correctas (IP de la DB, dominio de CloudFront, credenciales) y los sube a S3. Cuando arranca una instancia, cloud-init los descarga.

**Seguridad**: el bucket es privado. Solo las instancias de nuestra VPC podrán leerlo.

---

## Flujo de datos completo

### Petición de un usuario (sin caché):
```
Browser → CloudFront → Nginx LB → Nginx Web → WordPress FPM → MariaDB
                                                            ↗
                                               EFS (ficheros estáticos)
```

### Petición de CSS (con caché en CloudFront):
```
Browser → CloudFront (cache HIT) → Browser
```
CloudFront sirve el CSS desde su caché sin llegar al servidor.

### Arranque de una nueva instancia web:
```
ASG lanza EC2 → cloud-init descarga config de S3 → monta EFS → docker compose up
             → WP-CLI comprueba si WP está instalado → si no, lo instala
```

---

## Decisiones de diseño y sus alternativas

| Decisión | Alternativa considerada | Por qué se eligió esta |
|----------|------------------------|----------------------|
| Nginx LB en EC2 | AWS ALB | Gratuito (free tier), explicable en defensa |
| MariaDB en Docker | AWS RDS | Sin coste extra, suficiente para el proyecto |
| EFS para wp-content | S3 + plugin WP | EFS es transparente, no requiere plugin |
| S3 para config | Ansible en web instances | ASG necesita auto-configuración sin intervención |
| CloudFront | Sin CDN | Requisito del subject |
| ASG para web | EC2 fijo × 2 | Alta disponibilidad, escalado dinámico |
