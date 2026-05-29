# Guía de despliegue de Cloud-1 en AWS

Esta guía está pensada para configurar la infraestructura en Amazon Web Services (AWS) de forma segura, manteniéndonos estrictamente dentro de la **Capa Gratuita (Free Tier)** para evitar cargos, y finalizando con la ejecución del script de Ansible.

El *Subject* de Cloud-1 hace especial énfasis en el manejo de costes y la responsabilidad sobre recursos reales en la nube.

---

## 1. Capa Gratuita de AWS

Cuando creamos una cuenta nueva en AWS, obtendremos 12 meses de "Free Tier". Para este proyecto, debemos tener en cuenta:

- **Instancia (EC2)**: Tenemos derecho a **750 horas al mes** de una instancia `t2.micro` o `t3.micro`. 
Por lo que si mantienes **una sola** instancia encendida 24/7 en el mes, no nos cobrarán (un mes tiene máximo 744 horas), pero si enciendemos dos a la vez, el tiempo se consume el doble de rápido.

- **Almacenamiento (EBS)**: Tenemos derecho a **30 GB de almacenamiento SSD** (gp2 o gp3) al mes.

- **IPs Elásticas (Elastic IPs)**: Son gratuitas **siempre y cuando estén asociadas a una instancia EC2 encendida**. Si apagas tu instancia y dejas la IP Elástica reservada, AWS te cobrará unos céntimos por hora. **Esto un error muy común**

> **IMPORTANTE**: Cuando no estemos trabajando con el proyecto, **detendremos (Stop)** la instancia EC2. 

Al detenerla, el cobro por hora de la instancia cesa, pero no ocurrirá con la Elastic IP (la liberaremos la liberaremos).

---

## 2. Creación y Lanzamiento de la Máquina Virtual (EC2)

1. Entramos a la [Consola de Administración de AWS](https://aws.amazon.com/es/console/) y buscamos el servicio **EC2**.

2. Arriba a la derecha, verificamos en qué Región estamos.
Para el proyecto elegiremos *París (eu-west-3)* ya que es mejor una región europea para tener menor latencia.

3. Hacemos clic en el botón naranja **Launch Instance (Lanzar Instancia)**.

### Configuración de la Instancia:

- **Name**: `cloud-1-server`

- **AMI (Amazon Machine Image)**: Seleccionamos **Ubuntu** y nos aseguramos de escoger `Ubuntu Server 22.04 LTS (HVM), SSD Volume Type`. Revisamos bien que debajo ponga "Free tier eligible".

- **Instance Type**: Selecciona `t2.micro` (o `t3.micro` si t2 no está disponible en esa zona). Ambas son elegibles para la capa gratuita.

- **Key Pair (Login)**: 
  - Esto es fundamental para conectarnos por SSH. Hacemos clic en **Create new key pair**.
  - **Name**: `cloud-1-key`
  - **Type**: RSA
  - **Format**: `.pem` (ideal para Mac/Linux).
  - Hacemos clic en *Create* y el archivo `.pem` se descargará en el ordenador. **Guardamos bien este archivo**, lo necesitamos para que Ansible se conecte. Lo moveremos a `~/.ssh/cloud-1-key.pem` con los permisos `chmod 400 ~/.ssh/cloud-1-key.pem`

---

## 3. Configuración de Seguridad (Security Group)

El Subject especifica estrictamente que: *"Only ports 80 (HTTP), 443 (HTTPS), and 22 (SSH) must be accessible from outside. All other ports should be blocked."*

En la sección **Network Settings** al lanzar la instancia:

1. Marcamos **Create security group**.

2. Marcamos las siguientes tres casillas:
   - **Allow SSH traffic from** -> *Anywhere* (0.0.0.0/0) o preferiblemente *My IP* (por seguridad).
   - **Allow HTTP traffic from the internet** (Abre el puerto 80).
   - **Allow HTTPS traffic from the internet** (Abre el puerto 443).

3. **Storage (Almacenamiento)**: AWS nos dará 8 GB por defecto. Más que suficiente para Ubuntu y los pocos contenedores de Docker. Lo dejamos así.

4. Por último: clic en **Launch Instance**.

---

## 4. Configurar el Despliegue (Ansible)

Una vez la instancia EC2 esté en estado *Running*, hacemos clic sobre ella para ver los detalles. Copiamos su **Public IPv4 address**.

### Paso A: Preparamos el Inventario

Abrimos el archivo `inventory.ini` dentro de la carpeta `42_Cloud-1` y lo modificamos de la siguiente manera:

```ini
[cloud_1_servers]
# Sustituye <TU_IP_PUBLICA> por la IP que hemos copiado (ublic IPv4 address de ec2)
# Sustituye <RUTA_A_TU_ARCHIVO_PEM> por la ruta donde guardamos el archivo de claves
aws_server ansible_host=<TU_IP_PUBLICA> ansible_user=ubuntu ansible_ssh_private_key_file=<RUTA_A_TU_ARCHIVO_PEM>
```

Ejemplo de cómo debería quedar:
```ini
[cloud_1_servers]
aws_server ansible_host=3.250.150.99 ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/cloud-1-key.pem
```

*Nota: La AMI oficial de Ubuntu en AWS siempre utiliza `ubuntu` como usuario por defecto.*

### Paso B: Ejecutamos Ansible

Abriremos una terminal, nos situamos en la carpeta del repo (`42_Cloud-1`) y ejecutamos:

```bash
ansible-playbook -i inventory.ini playbook.yml
```

Qué ocurrirá a continuación:

1. Ansible usará la llave `.pem` para conectarse como `ubuntu` a la máquina EC2 en AWS.
2. Pedirá permisos de root (`become: yes`) automáticamente.
3. El rol `docker` instalará Docker y configurará los servicios desde cero.
4. El rol `inception` montará el árbol de carpetas persistentes, copiará el `.env`, creará los certificados SSL auto-firmados de Nginx y desplegará toda la arquitectura de contenedores de WordPress, MariaDB y phpMyAdmin en el servidor.

---

## 5. Puntos clave

El Subject detalla algunos puntos a tener en cuenta:

- **Usuario Root**: "The student must connect as root using their email address or login as the root account."
  - En AWS, entramos como `ubuntu`. Si en la evaluación nos piden estar como root puro, simplemente nos conectaremos a ec2 con `ssh -i ~/.ssh/cloud-1-key.pem ubuntu@IP` y una vez dentro ejecutaremos `sudo su -` para ser el usuario root de cara a la evaluación.
  
- **Probamos la Redirección y los Certificados**: 
  - Abrimos en el navegador `http://IP`, el servidor Nginx forzará automáticamente que pasemos a usar HTTPS `https://IP`. Saldrá un aviso de "Sitio no seguro" (ya que el certificado SSL es auto-firmado, no emitido por Let's Encrypt), le daremos a "Configuración Avanzada > Continuar de todos modos" y veremos WordPress.
  - El acceso a phpMyAdmin será visitando `https://IP/phpmyadmin/`.

- **Probando la Persistencia de los Datos**:
  - Esto debe ocurrir al reiniciar la máquina desde la consola de AWS. Al reiniciarse, AWS puede cambiar la IP pública (si no usamos una Elastic IP), pero todos los datos de `/home/ubuntu/data/` persistirán intactos. Cuando actualicemos, el archivo `inventory.ini` con la nueva IP e intentemos volver a conectar por SSH, la web y base de datos seguirán vivas y funcionando gracias a los volúmenes de Docker que configuramos en Ansible.
