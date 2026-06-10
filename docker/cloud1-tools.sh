#!/bin/bash
# Construye (si hace falta) el contenedor de herramientas y abre una shell interactiva.
# Uso: ./docker/cloud1-tools.sh
# Desde dentro del contenedor ya tienes: terraform, ansible, aws cli.

set -e

IMAGE_NAME="cloud1-tools"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Variables de entorno esperadas (o las busca en ~/.aws)
AWS_KEY_PATH="${AWS_KEY_PATH:-$HOME/.ssh/cloud-1-key.pem}"

# Comprobar que el .pem existe
if [ ! -f "$AWS_KEY_PATH" ]; then
  echo "ERROR: No encuentro la clave SSH en '$AWS_KEY_PATH'."
  echo "  Cópiala ahí o define la variable: AWS_KEY_PATH=/ruta/a/cloud-1-key.pem"
  exit 1
fi

# Construir imagen si no existe
if ! docker image inspect "$IMAGE_NAME" > /dev/null 2>&1; then
  echo ">>> Construyendo imagen $IMAGE_NAME (solo la primera vez, ~3 min)..."
  docker build -t "$IMAGE_NAME" -f "$SCRIPT_DIR/Dockerfile.tools" "$SCRIPT_DIR"
fi

echo ">>> Entrando en el contenedor (proyecto montado en /workspace)..."
echo "    Comandos disponibles: terraform, ansible, ansible-playbook, aws"
echo ""

docker run --rm -it \
  -v "$PROJECT_ROOT:/workspace" \
  -v "$HOME/.aws:/root/.aws:ro" \
  -v "$AWS_KEY_PATH:/root/.ssh/cloud-1-key.pem:ro" \
  -e AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-eu-west-3}" \
  "$IMAGE_NAME" \
  bash
