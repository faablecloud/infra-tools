#!/bin/sh

# La opción -e hace que el script falle inmediatamente si cualquier comando devuelve un error.
# Esto es vital en Kubernetes para que el Pod se marque como "Error" si algo sale mal.
set -e

echo "Iniciando script de actualización de ECR..."

# 1. Validar que las variables de entorno necesarias existan
# Se añade TARGET_NAMESPACES a la lista de validación obligatoria
if [ -z "$AWS_REGION" ] || [ -z "$AWS_ACCOUNT" ] || [ -z "$DOCKER_SECRET_NAME" ] || [ -z "$TARGET_NAMESPACES" ]; then
  echo "❌ ERROR: Faltan variables de entorno obligatorias."
  echo "Asegúrate de definir: AWS_REGION, AWS_ACCOUNT, DOCKER_SECRET_NAME y TARGET_NAMESPACES."
  exit 1
fi
# Asignar namespace por defecto si no viene como variable de entorno
NAMESPACE="${NAMESPACE:-default}"

# 2. Obtener la contraseña de ECR
echo "Obteniendo token de AWS ECR en la región ${AWS_REGION}..."
ECR_TOKEN=$(aws ecr get-login-password --region "${AWS_REGION}")

# 3. Actualizar el secreto EN SU SITIO (create --dry-run | apply), con la
#    anotación del replicator dentro del mismo manifiesto.
#
#    ⚠️ No borrarlo y volver a crearlo: kubernetes-replicator ve el borrado,
#    elimina las copias de todos los namespaces destino y, al recrearse el
#    origen, su caché todavía las cree existentes, intenta actualizarlas y falla
#    con «not found». Esos namespaces se quedaban sin secret desde la hora en
#    punto hasta la resincronización (~:24) y cualquier pull en ese hueco
#    fallaba: reports-production-activations (03:15) murió por deadline el
#    24 y el 25-10-2026.
echo "Actualizando secreto (${DOCKER_SECRET_NAME}) en ${NAMESPACE}, replicado a ${TARGET_NAMESPACES}..."
kubectl create secret docker-registry "${DOCKER_SECRET_NAME}" \
  --docker-server="https://${AWS_ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com" \
  --docker-username=AWS \
  --docker-password="${ECR_TOKEN}" \
  --namespace="${NAMESPACE}" \
  --dry-run=client -o yaml \
  | kubectl annotate --local -f - --overwrite -o yaml \
      replicator.v1.mittwald.de/replicate-to="${TARGET_NAMESPACES}" \
  | kubectl apply -f -

echo "✅ Secret was successfully updated at $(date)"
