# Cloud-1: Despliegue Automatizado de Inception

Este documento es una guía diseñada para explicar los conceptos clave, la arquitectura subyacente y los pasos necesarios para desplegar y mantener la infraestructura en la nube. 

---

## 1. Conceptos Fundamentales del Proyecto

A diferencia de Inception (donde creábamos las imágenes base de Docker desde cero usando Alpine/Debian), el objetivo principal de Cloud-1 es aprender sobre **Infraestructura como Código (IaC)** y **Automatización**.

### Infraestructura como Código (IaC) con Ansible
Ansible es una herramienta de automatización que nos permite escribir scripts (conocidos como *Playbooks*) sobre cómo debe configurarse un servidor. 

En lugar de conectarte por SSH a un servidor y ejecutar comandos a mano para instalar Docker o configurar Nginx, Ansible lo hace de forma predecible e idempotente (se puede ejecutar múltiples veces y solo aplicará cambios si es necesario).

### Parte obligatoria

La regla de oro de este proyecto es **1 contenedor = 1 proceso**.

Tenemos 4 servicios fundamentales, cada uno corriendo en su propio contenedor utilizando imágenes oficiales:

- **Nginx**: Servidor web y *Reverse Proxy*.
- **WordPress (PHP-FPM)**: Contiene la lógica en PHP para la página web.
- **MariaDB (MySQL)**: Motor de base de datos relacional.
- **phpMyAdmin**: Interfaz gráfica para gestionar la base de datos.

### Seguridad y Enrutamiento (TLS)

- **Cifrado (HTTPS)**: El servidor Nginx incluye certificados SSL/TLS (generados automáticamente mediante Ansible) para encriptar la conexión.

- **Puertos cerrados**: Toda la comunicación pasa a través del puerto `443` (HTTPS) o `80` (HTTP, el cual redirige a HTTPS). Los contenedores de base de datos (`3306`) y WordPress (`9000`) solo son accesibles desde dentro de la red privada de Docker, garantizando así la seguridad de tu base de datos.

---

## 2. Arquitectura de Ansible

El código está estructurado en *Roles* para mantener un diseño limpio, reutilizable y escalable:

- **`ansible.cfg`**: Archivo principal de configuración de Ansible.
- **`inventory.ini`**: Fichero donde indicamos a Ansible las direcciones IP de nuestros servidores de destino y los usuarios para conectarnos.
- **`playbook.yml`**: El archivo maestro del proyecto, manejado por Ansible.
- **Rol `docker`**: 
  - Su propósito es preparar el servidor remoto desde cero. 
  - Instala dependencias, añade las claves GPG de Docker y finalmente instala el motor de Docker y Docker Compose.
- **Rol `inception`**: 
  - Contiene las tareas para la aplicación. 
  - Crea las carpetas persistentes (`/data/wordpress`, `/data/mariadb`).
  - Genera automáticamente certificados SSL usando OpenSSL.
  - Genera (usando plantillas de Jinja2 `.j2`) el archivo `nginx.conf` y `docker-compose.yml` dinámicamente con las variables.
  - Inicia el clúster con `docker compose up -d`.

---

## 3. Guía de Despliegue

Para desplegar este proyecto, necesitamos un servidor remoto (por ejemplo, una máquina en AWS, GCP, Scaleway o una máquina virtual local tipo Multipass/Vagrant) que ejecute **Amazon Linux** (o cualquier distro compatible con Docker).

Nosotros utilizaremos un EC2 en AWS.

### Paso 1: Preparación local

Nos aseguraremos de tener Ansible instalado en el ordenador desde el cual vamos a ejecutar el despliegue:

```bash
# En nuestro caso hemos utilizado Mac (homebrew):
brew install ansible

# En Ubuntu local:
sudo apt update && sudo apt install ansible
```

### Paso 2: Configurar el Inventario

Abrimos el archivo `inventory.ini`. Vemos algo como esto:

```ini
[cloud_1_servers]
target_server ansible_host=localhost ansible_connection=local
```

Lo cambiaremos por la IP real de nuestro servidor y el usuario remoto (por lo general `root` o `ec2-user` en Amazon Linux):

```ini
[cloud_1_servers]
servidor_produccion ansible_host=203.0.113.50 ansible_user=ec2-user
```

### Paso 3: Configurar Secretos (Opcional)

En `roles/inception/files/.env.example` encontraremos las contraseñas base. Podemos editarlas. Ansible copiará este fichero automáticamente al servidor en el despliegue.

*Importante:* Nunca subiremos contraseñas reales a GitHub. Por eso usamos un `.env.example`.

### Paso 4: Ejecutar el Despliegue

Lanzamos Ansible con el siguiente comando:
```bash
ansible-playbook -i inventory.ini playbook.yml
```
  Ansible se conectará a la máquina, instalará Docker, montará la arquitectura y generará automáticamente los certificados SSL, la inyección de las variables de IP dinámica (`HTTP_HOST`) y arrancará los contenedores. Solo con este comando levantarás toda la infraestructura en cualquier IP pública.

  ### Paso 5: Limpiar el entorno para la Demostración (Reset)

  Para las evaluaciones (o si quieres dejar el EC2 completamente en blanco), puedes destruir fácilmente todo el entorno para demostrar su completo funcionamiento automatizado usando nuestro Playbook de reset:
  
  ```bash
  ansible-playbook -i inventory.ini reset.yml
  ```
  Este playbook:
  1. Detendrá todos los servicios (`docker compose down -v`).
  2. Eliminará todas las imágenes locales forzando a descargarlas de nuevo (`docker system prune -a --volumes -f`).
  3. Eliminará la carpeta estructural completa del proyecto en el servidor remoto (`~/inception`).
  4. Borrará todo el sistema de permanencia de las bases de datos y la web (`~/data`).

  Dejando la máquina completamente virgen para volver a lanzar un `playbook.yml`.

  ### Paso 6: Verificación

  Abrimos tu navegador y entramos a:
  - `https://<IP_DE_TU_SERVIDOR>` (redirigirá a HTTPS y mostrará WordPress de manera correcta indiferentemente de lo que cambie tu IP).
## 4. Puntos Importantes 

El *Subject* del proyecto nos destaca varios detalles cruciales:

1. **Gestión de Costes (The Cloud is just someone else's computer)**:
   - Somos los responsables de encender y **apagar** los servidores. Si olvidamos apagar una máquina en AWS se pueden incurrir en costos. Apagaremos todo al finalizar.
   - No sobredimensionaremos la máquina que utilizaremos (no elejiremos una máquina grande de 16GB de RAM cuando una micro de 1GB es suficiente para este proyecto).

2. **Acceso Seguro (Ports)**:
   - Muy importante que la base de datos y la red interna de docker no estén expuestas al exterior de forma pública. Los únicos puertos que deben estar abiertos en la máquina (en el *Security Group*) son el `22` (SSH), el `80` (HTTP) y el `443` (HTTPS).

3. **Reinicio y Persistencia**:
   - El sitio debe aguantar reinicios bruscos de servidor. Gracias al parámetro `restart: always` en Docker Compose y a los volúmenes configurados para `/data/mariadb` y `/data/wordpress`, si la máquina se apaga y se vuelve a encender, todos los artículos, imágenes y bases de datos se restaurarán automáticamente sin intervención humana.

4. **El usuario Root**:
   - Deberemos poder conectarnos como `root` en el servidor y demostrar que el sistema funciona bajo las especificaciones técnicas pedidas.