# Apuntes Cloud-1 — Índice

Con estos apuntes quiero documentar mi proyecto Cloud-1 en profundidad: qué hace cada archivo, por qué se tomaron las decisiones de diseño, y qué conceptos teóricos hay detrás de cada herramienta. Están pensados para dos usos:

1. **Presentar el proyecto** en la defensa de 42 con rigor técnico.
2. **Arrancar el estudio** de la certificación HashiCorp Certified: Terraform Associate.

Con ellos quiero documentar también cual fué mi proceso de aprendizaje hacia el mundo de IaC (Terraform) una vez que superé la certificación de AWS - Solutions Architect Associate.

---

## Contenidos de esta carpeta

| Archivo | Contenido |
|---------|-----------|
| [01_arquitectura.md](01_arquitectura.md) | Visión global del sistema, por qué cada componente, flujo de datos |
| [02_terraform_core.md](02_terraform_core.md) | Conceptos fundamentales de Terraform (IaC, state, workflow, HCL) |
| [03_terraform_archivos.md](03_terraform_archivos.md) | Cada archivo `.tf` del proyecto explicado línea a línea |
| [04_aws_servicios.md](04_aws_servicios.md) | Cada servicio de AWS usado: qué es, por qué se eligió, cómo funciona |
| [05_ansible_conceptos.md](05_ansible_conceptos.md) | Ansible: inventario, playbooks, roles, templates Jinja2, idempotencia |
| [06_docker_cloudinit.md](06_docker_cloudinit.md) | Docker, Docker Compose, cloud-init y cómo encajan en la arquitectura |
| [07_seguridad.md](07_seguridad.md) | Seguridad en capas: SGs, IAM, secretos, TLS, principio de mínimo privilegio |
| [08_certificacion_terraform.md](08_certificacion_terraform.md) | Hoja de ruta para la Terraform Associate: qué cubre el proyecto, qué falta |

---

**Para la defensa del proyecto**: `01_arquitectura.md` y `04_aws_servicios.md`. Son los que más respuestas generan en la corrección.

**Para la certificación**: empiezaríamos por `02_terraform_core.md` y `03_terraform_archivos.md`, luego saltaríamos a `08_certificacion_terraform.md` para ver el roadmap completo.

Sin embargo es interesante seguirlos en orden para tener todo el contexto lo más claro posible.
