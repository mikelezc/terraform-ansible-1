# 05 — Ansible: Conceptos y Archivos del Proyecto

---

## Qué es Ansible?

Ansible es una herramienta de automatización de configuración. Mientras Terraform crea la infraestructura (las máquinas), Ansible configura lo que hay dentro (instala software, copia archivos, arranca servicios).

### Push vs Pull

**Ansible = Push**: desde la máquina local nos conectamos a los servidores remotos via SSH y ejecutamos las tareas. No hay agente instalado en los servidores.

Evitamos la complejidad de otras herramientas **Pull** como Puppet o Chef, donde los servidores descargan periódicamente su configuración de un servidor central. Ansible es más simple: solo necesitamos SSH (por eso la recomienda el subject).

### Idempotencia

Una operación es idempotente si ejecutarla múltiples veces produce el mismo resultado que ejecutarla una vez.

Ansible está diseñado para ser idempotente: si ejecutamos el playbook y el servidor ya está configurado correctamente, Ansible detecta que no hay nada que cambiar y no toca nada. Esto permite ejecutar `ansible-playbook` repetidamente sin miedo.

Por ejemplo, el módulo `apt` de Ansible comprueba si el paquete ya está instalado antes de instalarlo. Si lo está, marca la tarea como `ok` (sin cambios), no como `changed`.

---

## Inventario (`inventory.ini`)

El inventario dice a Ansible a qué servidores conectarse y con qué credenciales.

En este proyecto el inventario es generado automáticamente por Terraform (`inventory.tf`) con las IPs reales de las instancias:

```ini
[lb]                                                          # grupo "lb"
51.44.147.13 ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/cloud-1-key.pem

[db]                                                          # grupo "db"
15.237.190.15 ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/cloud-1-key.pem

[all:vars]                                                    # variables para TODOS
db_private_ip=172.31.7.213
efs_dns_name=fs-0d2b12c944e407d1e.efs.eu-west-3.amazonaws.com
cloudfront_domain=d1luk2m7zozc7h.cloudfront.net
asg_name=cloud1-web-asg
aws_region=eu-west-3
db_password=3333
```

**Grupos**: agrupan hosts. El playbook puede correr en todos los hosts de un grupo.
**`[all:vars]`**: variables disponibles para todos los hosts y roles.

---

## `ansible.cfg` — Configuración de Ansible

```ini
[defaults]
inventory             = inventory.ini     # inventario por defecto
host_key_checking     = False             # no pide confirmar fingerprint SSH
retry_files_enabled   = False             # no crea .retry en caso de error
stdout_callback       = yaml              # output más legible

[privilege_escalation]
become        = True                      # sudo por defecto
become_method = sudo
become_user   = root
```

**`host_key_checking = False`**: normalmente SSH pide confirmar el fingerprint de un nuevo servidor. Para automatización esto es un problema. Lo deshabilitamos porque confiamos en que las IPs del inventario son correctas (vienen de Terraform).

---

## Playbooks (`playbook.yml`, `reset.yml`)

Un playbook es el archivo maestro que define qué hacer y en qué hosts.

```yaml
---
- name: Configure load balancer    # descripción del play
  hosts: lb                        # grupo del inventario
  become: yes                      # ejecutar como root (sudo)

  roles:
    - docker                       # rol 1
    - loadbalancer                 # rol 2

- name: Configure database server
  hosts: db
  become: yes

  roles:
    - docker
    - database
```

Un playbook puede tener múltiples **plays**. Cada play se aplica a un grupo de hosts y aplica uno o más roles. Los plays se ejecutan en orden.

**`become: yes`**: Ansible conecta como `ubuntu` (el usuario del inventario) y luego hace `sudo su root` para ejecutar las tareas con privilegios de root.

---

## Roles

Un rol es una unidad reutilizable de configuración. Agrupa tareas relacionadas con sus templates, archivos y variables.

### Estructura de un rol

```
roles/
  docker/
    tasks/
      main.yml          # ← SIEMPRE se ejecuta al invocar el rol
  loadbalancer/
    tasks/
      main.yml
    templates/
      nginx.lb.conf.j2  # plantillas Jinja2
      docker-compose.lb.yml.j2
  database/
    tasks/
      main.yml
    templates/
      docker-compose.db.yml.j2
      .env.db.j2
    files/
      .env.db            # archivos estáticos (sin templating)
```

---

## Rol `docker` — Instalar Docker

Se aplica a LB y DB. Gestiona dos casos (Ubuntu/Debian con `apt`, Amazon Linux con `dnf/yum`) aunque en este proyecto siempre usamos Ubuntu.

Tareas:
1. `apt install docker.io python3-pip`
2. `systemctl enable docker && systemctl start docker`
3. Descarga docker-compose v2.24.5 de GitHub
4. Crea symlink para `docker compose` (plugin)
5. Instala módulo Python `python3-docker` (para que Ansible pueda interactuar con Docker via módulo `docker_container`)

**`when: ansible_pkg_mgr == 'apt'`**: condición. Solo ejecuta la tarea en sistemas que usan `apt`. En Amazon Linux usaría `dnf` o `yum`.

---

## Rol `loadbalancer` — Configurar Nginx LB

El rol más interesante del proyecto porque combina generación dinámica de configuración con consulta de recursos externos (AWS).

### Tarea clave: descubrir IPs del ASG

```yaml
- name: Get web instance private IPs from ASG
  shell: >
    aws ec2 describe-instances
    --filters "Name=tag:aws:autoscaling:groupName,Values={{ asg_name }}"
              "Name=instance-state-name,Values=running"
    --query "Reservations[].Instances[].PrivateIpAddress"
    --output json --region {{ aws_region }}
  register: web_ips_raw
  delegate_to: localhost    # ejecuta en tu máquina local, no en el LB
  become: no                # no necesita sudo para correr en local

- set_fact:
    web_instance_ips: "{{ web_ips_raw.stdout | from_json }}"
```

**`delegate_to: localhost`**: por defecto Ansible ejecuta las tareas en el host remoto. Con `delegate_to: localhost`, la ejecuta en tu máquina local. Útil para consultar la API de AWS (que solo tu máquina tiene credenciales para hacer).

**`register`**: guarda el output de un comando en una variable.
**`set_fact`**: define una nueva variable. `from_json` convierte el string JSON en una lista Python.

Después de esto, `web_instance_ips` es algo como `['172.31.45.90', '172.31.12.196']`.

### Template Nginx con upstream dinámico

```jinja2
upstream wordpress_backends {
{% for ip in web_instance_ips %}
    server {{ ip }}:80 max_fails=3 fail_timeout=30s;
{% endfor %}
}
```

Jinja2 itera sobre la lista de IPs y genera una línea `server` por cada instancia. Si hay 2 instancias, genera 2 líneas; si hay 4, genera 4.

### Generación del certificado SSL

```yaml
- name: Generate OpenSSL CSR
  openssl_csr:
    country_name: "ES"
    state_or_province_name: "Madrid"
    locality_name: "Madrid"
    organization_name: "42 Madrid"
    organizational_unit_name: "Cloud-1"
    common_name: "{{ cloudfront_domain }}"
```

El módulo `openssl_csr` de Ansible genera un Certificate Signing Request con los campos especificados. Luego `openssl_certificate` lo auto-firma. El resultado es un certificado válido pero no de confianza para los navegadores (sin CA reconocida).

---

## Rol `database` — Desplegar MariaDB

Tareas:
1. Crear directorios `/home/ubuntu/data/mariadb` y `/home/ubuntu/db`
2. Template `.env.db.j2` → `/home/ubuntu/db/.env` (con credenciales de `[all:vars]`)
3. Template `docker-compose.db.yml.j2` → `/home/ubuntu/db/docker-compose.yml`
4. `docker compose up -d`
5. Espera a que MariaDB esté escuchando en el puerto 3306

### Template `.env.db.j2`

```jinja2
DB_NAME={{ db_name }}
DB_USER={{ db_user }}
DB_PASSWORD={{ db_password }}
DB_ROOT_PASSWORD={{ db_root_password }}
```

Las variables vienen de `[all:vars]` del inventario (que Terraform generó con los valores de `terraform.tfvars`). Esto garantiza que las credenciales de la DB y las que usan las instancias web son exactamente las mismas.

---

## Templates Jinja2

Ansible usa Jinja2 como motor de templates (el mismo que usa Flask, Django, etc. en Python).

### Sintaxis

```jinja2
{{ variable }}              # interpolación de variable
{% if condicion %}          # condicional
  ...
{% endif %}
{% for item in lista %}     # bucle
  server {{ item }}:80;
{% endfor %}
{{ lista | from_json }}     # filtro (from_json, to_json, upper, lower, length...)
{{ variable | default('valor_por_defecto') }}
```

### Diferencia con templates de Terraform

| Terraform `.tpl` | Ansible `.j2` |
|------------------|---------------|
| `${variable}` | `{{ variable }}` |
| `%{ for ... }%` | `{% for ... %}` |
| Generado en tu máquina local | Generado en el servidor remoto |

---

## Módulos de Ansible usados en el proyecto

| Módulo | Qué hace | Donde se usa |
|--------|----------|--------------|
| `apt` | Instala paquetes (Ubuntu) | docker role |
| `systemd` | Gestiona servicios | docker role |
| `get_url` | Descarga archivos HTTP | docker role (docker-compose binario) |
| `file` | Crea directorios, gestiona permisos | todos los roles |
| `template` | Renderiza Jinja2 y copia al servidor | todos los roles |
| `copy` | Copia archivos sin templating | database role |
| `command` | Ejecuta comandos (no idempotente) | docker compose up |
| `shell` | Ejecuta comandos con shell (pipes, etc.) | consulta ASG IPs |
| `openssl_privatekey` | Genera clave privada RSA | loadbalancer role |
| `openssl_csr` | Genera CSR | loadbalancer role |
| `openssl_certificate` | Genera certificado auto-firmado | loadbalancer role |
| `pip` | Instala módulos Python | loadbalancer role |
| `set_fact` | Define variables dinámicas | loadbalancer role |
| `wait_for` | Espera a que un puerto esté disponible | database role |
| `debug` | Muestra mensajes | loadbalancer role |
| `fail` | Falla con un mensaje si condición | loadbalancer role |

---

## Variables en Ansible

Las variables pueden venir de múltiples sitios (en orden de precedencia, de menos a más prioritaria):

1. Defaults del rol (`roles/X/defaults/main.yml`) — menor prioridad
2. Variables del inventario (`[all:vars]`, `[group:vars]`)
3. `group_vars/all.yml`
4. Variables del playbook (`vars:` en el play)
5. `set_fact` en tiempo de ejecución
6. Flag `-e "variable=valor"` en línea de comandos — mayor prioridad

En el proyecto las variables principales vienen de `[all:vars]` del inventario (generado por Terraform). Así Terraform y Ansible comparten la misma fuente de verdad.

---

## `group_vars/all.yml`

```yaml
deploy_user: ubuntu
```

Variables definidas aquí están disponibles en todos los hosts y todos los roles. Solo usamos `deploy_user` para saber qué usuario de sistema usa Ubuntu 22.04 (es `ubuntu`, no `ec2-user` como en Amazon Linux).

---

## `reset.yml` — Limpiar el entorno

```yaml
- name: Reset load balancer
  hosts: lb
  tasks:
    - name: Stop Nginx LB
      command: docker compose -f /home/ubuntu/lb/docker-compose.yml down -v

    - name: Prune Docker
      command: docker system prune -a --volumes -f

    - name: Remove LB directory
      file: path=/home/ubuntu/lb state=absent
```

Útil para demostrar a un corrector que el despliegue es reproducible desde cero: reset → deploy → funciona.

`ignore_errors: true` en las tareas de docker porque si los contenedores ya estaban parados, el comando fallaría. Con `ignore_errors` Ansible continúa aunque una tarea falle.
