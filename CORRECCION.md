# Guía para la Defensa y Corrección de Cloud-1

Esta guía contiene los puntos clave, comandos y explicaciones necesarias para defender tu proyecto frente a un evaluador, asegurando que cubres todos los huecos del *Subject*.

## 1. Demostrar el Control Absoluto del Entorno (Reset y Deploy)
El evaluador querrá ver que tu infraestructura como código (IaC) funciona desde cero y no está "amañada" ni pre-configurada manualmente.

**Cómo demostrarlo:**
1. Conéctate a tu máquina e invita al evaluador a ver que hay cosas en ejecución (`docker ps`).
2. En tu ordenador local, ejecuta el reseteo total:
   ```bash
   ansible-playbook -i inventory.ini reset.yml
   ```
3. Vuelve a mostrar la máquina al evaluador (`docker ps -a`, `docker images`). Verá que todo ha desaparecido, no hay contenedores, imágenes ni persistencia (carpeta `~/data` borrada).
4. Despliega la magia con un comando:
   ```bash
   ansible-playbook -i inventory.ini playbook.yml
   ```
5. Muestra cómo se vuelve a descargar todo, se inyecta la IP dinámica y levantan los 4 contenedores automáticamente.

## 2. El Sistema Operativo y la Idempotencia (Ubuntu vs Amazon Linux)
El subject pide explícitamente: *"assuming only an Ubuntu 22.04 LTS-like OS"*.
- **El Truco**: Tu Ansible está programado con **condicionales**. Funciona tanto en **Amazon Linux 2023** (usando `dnf` y `python3-pip` genérico) como en **Ubuntu 22.04** (usando `apt`).
- **Defensa**: Si el evaluador te trae una máquina Ubuntu que acaba de crear, solo pídele su IP y su usuario, ponlo en el `inventory.ini` y dale a desplegar. Tu Ansible detectará el sistema y usará los comandos de Ubuntu automáticamente.

## 3. Demostrar la Seguridad de los Puertos
El subject indica: *"Only ports 80, 443, and 22 must be accessible from outside. All other ports should be blocked. Not possible to connect directly to your database from the internet."*

**Cómo demostrarlo:**
1. Entra en tu consola de AWS -> EC2 -> Instancias -> Selecciona tu máquina -> Pestaña "Security" (Seguridad).
2. Enséñale las **Inbound Rules** (Reglas de entrada). Sólo deben estar abiertos:
   - Puerto `22` (SSH)
   - Puerto `80` (HTTP)
   - Puerto `443` (HTTPS)
3. Abre tu archivo `docker-compose.yml.j2`. 
4. Enséñale que MariaDB utiliza **`expose: "3306"`** (apertura nativa solo local para Docker) y no **`ports: "3306:3306"`** (que la expondría a internet). Así garantizas que Nginx la ve, pero un atacante desde internet no.

## 4. Validación del "Root Account" / Anti-Cheating
El subject manda que debe conectarse como cuenta raíz y vinculada a tu correo, para evitar presentar la máquina de otro alumno.

**Cómo demostrarlo:**
1. Muestra que has iniciado sesión en la consola de AWS con tu correo de 42 o correo personal que pueda identificarte.
2. Al estar dentro del SSH de la máquina como `ec2-user` o `ubuntu`, ejecuta `sudo su -`.
3. Tu *prompt* cambiará a `root@ip-X-X-X-X`. Esto demuestra que tienes total control de super-administrador del servidor.

## 5. El "Free Tier" y los Costes Ocultos
El subject es muy claro en que debes cuidar los recursos (*oversize your resources*).
- **Cómo demostrarlo**: Enséñale que tu instancia EC2 es una **t2.micro** o **t3.micro** y no un monstruo de 16GB de RAM. Demuestra que no tienes servicios anexos contratados.
- **Acción final**: Cuando te pongan la nota, y delante de él/ella, entra a tu AWS y pulsa **Detener Instancia** para dejar constancia de que sabes prever gastos.