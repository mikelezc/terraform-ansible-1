#!/bin/bash
# Cloud-1 tools — menú de gestión del entorno de desarrollo.
#
# Uso:  ./docker/cloud1-tools.sh
# Anula la ruta de la clave SSH con:
#   AWS_KEY_PATH=/ruta/a/cloud-1-key.pem ./docker/cloud1-tools.sh

set -e

# ── Configuración ──────────────────────────────────────────────────────────────
IMAGE="cloud1-tools"
CONTAINER="cloud1-session"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
KEY="${AWS_KEY_PATH:-$HOME/.ssh/cloud-1-key.pem}"
REGION="${AWS_DEFAULT_REGION:-eu-west-3}"

# ── Colores ────────────────────────────────────────────────────────────────────
if [ -t 1 ]; then
  RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[1;33m'
  CYN='\033[0;36m'; BLD='\033[1m'; NC='\033[0m'
else
  RED=''; GRN=''; YLW=''; CYN=''; BLD=''; NC=''
fi

# ── Helpers ────────────────────────────────────────────────────────────────────
info()  { echo -e "${CYN}  $*${NC}"; }
ok()    { echo -e "${GRN}  ✓ $*${NC}"; }
warn()  { echo -e "${YLW}  ! $*${NC}"; }
err()   { echo -e "${RED}  ✗ $*${NC}"; }

container_running() { docker ps  --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER}$"; }
container_exists()  { docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER}$"; }
image_exists()      { docker image inspect "$IMAGE" > /dev/null 2>&1; }

# ── Construcción de imagen ─────────────────────────────────────────────────────
build_image() {
  warn "Imagen '$IMAGE' no encontrada. Construyendo (~3 min la primera vez)..."
  docker build -t "$IMAGE" -f "$SCRIPT_DIR/Dockerfile.tools" "$SCRIPT_DIR"
  ok "Imagen construida."
}

# ── Arranque de contenedor ─────────────────────────────────────────────────────
start_container() {
  if ! image_exists; then build_image; fi

  if [ ! -f "$KEY" ]; then
    err "Clave SSH no encontrada en '$KEY'."
    echo "  Cópiala ahí o define: AWS_KEY_PATH=/ruta/a/cloud-1-key.pem"
    return 1
  fi

  if container_exists && ! container_running; then
    info "Reiniciando contenedor parado..."
    docker start "$CONTAINER" > /dev/null
  elif ! container_exists; then
    info "Creando contenedor '$CONTAINER'..."
    docker run -d \
      --name "$CONTAINER" \
      -v "$PROJECT_ROOT:/workspace" \
      -v "$HOME/.aws:/root/.aws:ro" \
      -v "$KEY:/root/.ssh/cloud-1-key.pem:ro" \
      -e AWS_DEFAULT_REGION="$REGION" \
      "$IMAGE" \
      sleep infinity > /dev/null
  fi
  ok "Contenedor activo."
}

# ── Entrar al contenedor ───────────────────────────────────────────────────────
enter_container() {
  cat <<'HELP'

  ┌──────────────────────────────────────────────────────────────────────────┐
  │  cloud1-tools — contenedor de desarrollo                                 │
  │  Proyecto montado en: /workspace                                         │
  │  Herramientas: terraform · ansible · aws · git · jq                      │
  ├──────────────────────────────────────────────────────────────────────────┤
  │  DESPLIEGUE COMPLETO                                                     │
  │    cd /workspace/terraform && terraform init && terraform apply          │
  │                                                                          │
  │  RELANZAR ANSIBLE (tras escalar o refresh manual)                        │
  │    cd /workspace/ansible                                                 │
  │    ansible-playbook -i inventory.ini playbook.yml                        │
  │                                                                          │
  │  ESCALAR INSTANCIAS WEB                                                  │
  │    cd /workspace/terraform                                               │
  │    terraform apply -var="web_desired=4"                                  │
  │                                                                          │
  │  VER OUTPUTS (URL, IPs...)                                               │
  │    cd /workspace/terraform && terraform output                           │
  │                                                                          │
  │  DESTRUIR TODA LA INFRA AWS                                              │
  │    cd /workspace/terraform && terraform destroy                          │
  │                                                                          │
  │  SALIR DEL CONTENEDOR                                                    │
  │    exit                                                                  │
  └──────────────────────────────────────────────────────────────────────────┘

HELP
  docker exec -it "$CONTAINER" bash
}

# ── Menú: entrar/arrancar ──────────────────────────────────────────────────────
action_enter() {
  if container_running; then
    info "Contenedor ya activo — conectando..."
  else
    start_container || return 1
  fi
  enter_container
}

# ── Menú: terraform autocomplete ──────────────────────────────────────────────
action_autocomplete() {
  if ! container_running; then
    warn "El contenedor no está activo. Arráncalo primero (opción 1)."
    return
  fi

  # Comprueba si ya está instalado
  if docker exec "$CONTAINER" grep -q 'terraform' /root/.bashrc 2>/dev/null; then
    ok "Terraform autocomplete ya estaba instalado en el contenedor."
    info "Entrará en efecto en la próxima sesión bash ('exit' y vuelve a entrar)."
    return
  fi

  info "Instalando Terraform autocomplete en /root/.bashrc del contenedor..."
  docker exec "$CONTAINER" bash -c 'terraform -install-autocomplete 2>/dev/null && echo "OK"'
  ok "Instalado. Efecto en la próxima sesión bash."
  info "Pista: sal (exit) y vuelve a entrar (opción 1) para activarlo."
}

# ── Menú: limpiar Docker ───────────────────────────────────────────────────────
action_clean_docker() {
  echo ""
  warn "Esta opción borra el contenedor '$CONTAINER' y libera sus recursos locales."
  warn "No afecta a la infraestructura AWS."
  printf "  ¿Continuar? (s/N): "
  read -r answer
  [[ "$answer" =~ ^[sS]$ ]] || { info "Cancelado."; return; }

  if container_running; then
    info "Parando contenedor..."
    docker stop "$CONTAINER" > /dev/null && ok "Contenedor parado."
  fi
  if container_exists; then
    info "Borrando contenedor..."
    docker rm "$CONTAINER" > /dev/null && ok "Contenedor borrado."
  fi

  echo ""
  printf "  ¿Borrar también la imagen '%s' (~1 GB)? (s/N): " "$IMAGE"
  read -r answer2
  if [[ "$answer2" =~ ^[sS]$ ]]; then
    docker rmi "$IMAGE" && ok "Imagen borrada."
  fi

  info "Limpiando volúmenes anónimos huérfanos..."
  docker volume prune -f > /dev/null && ok "Volúmenes limpiados."
  echo ""
  ok "Limpieza Docker completada."
}

# ── Menú: limpiar AWS (emergency cleanup) ─────────────────────────────────────
action_clean_aws() {
  echo ""
  warn "ATENCIÓN: Esto borra TODOS los recursos AWS del proyecto cloud1."
  warn "Ejecutará terraform destroy y limpiará recursos huérfanos manualmente."
  printf "  ¿Continuar? (s/N): "
  read -r answer
  [[ "$answer" =~ ^[sS]$ ]] || { info "Cancelado."; return; }

  if ! container_running; then
    info "Arrancando contenedor para ejecutar el cleanup..."
    start_container || return 1
  fi

  docker exec -it "$CONTAINER" bash /workspace/docker/cloud1-cleanup.sh
}

# ── Estado del contenedor ──────────────────────────────────────────────────────
container_status() {
  if container_running; then
    echo -e "  Estado: ${GRN}${BLD}● ACTIVO${NC}"
  elif container_exists; then
    echo -e "  Estado: ${YLW}${BLD}○ PARADO${NC}"
  else
    echo -e "  Estado: ${RED}${BLD}✗ NO EXISTE${NC}"
  fi
  if image_exists; then
    echo -e "  Imagen: ${GRN}construida${NC}"
  else
    echo -e "  Imagen: ${YLW}no construida (se construirá al iniciar)${NC}"
  fi
}

# ── Menú principal ─────────────────────────────────────────────────────────────
main() {
  while true; do
    echo ""
    echo -e "${BLD}  ┌─────────────────────────────────────────────┐${NC}"
    echo -e "${BLD}  │         Cloud-1 Development Tools           │${NC}"
    echo -e "${BLD}  └─────────────────────────────────────────────┘${NC}"
    container_status
    echo ""
    echo "  1) Iniciar / Entrar al contenedor"
    echo "  2) Instalar Terraform autocomplete"
    echo "  3) Limpiar Docker  (borrar contenedor e imagen local)"
    echo "  4) Limpiar AWS     (emergency cleanup — borra toda la infra)"
    echo "  5) Salir"
    echo ""
    printf "  Elige una opción: "
    read -r opt

    case "$opt" in
      1) action_enter ;;
      2) action_autocomplete ;;
      3) action_clean_docker ;;
      4) action_clean_aws ;;
      5) echo ""; exit 0 ;;
      *) warn "Opción no válida." ;;
    esac
  done
}

main
