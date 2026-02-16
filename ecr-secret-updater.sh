#!/bin/sh

# La opción -e hace que el script falle inmediatamente si cualquier comando devuelve un error.
# Esto es vital en Kubernetes para que el Pod se marque como "Error" si algo sale mal.
set -e

echo "Iniciando script de actualización de ECR..."

# 1. Validar que las variables de entorno necesarias existan
if [ -z "$AWS_REGION" ] || [ -z "$AWS_ACCOUNT" ] || [ -z "$DOCKER_SECRET_NAME" ]; then
  echo "❌ ERROR: Faltan variables de entorno. Asegúrate de definir AWS_REGION, AWS_ACCOUNT y DOCKER_SECRET_NAME en el Pod."
  exit 1
fi

# Asignar namespace por defecto si no viene como variable de entorno
NAMESPACE="${NAMESPACE:-default}"

# 2. Obtener la contraseña de ECR
echo "Obteniendo token de AWS ECR en la región ${AWS_REGION}..."
ECR_TOKEN=$(aws ecr get-login-password --region "${AWS_REGION}")

# 3. Eliminar el secreto antiguo si existe
echo "Eliminando secreto antiguo (${DOCKER_SECRET_NAME}) en el namespace ${NAMESPACE}..."
kubectl delete secret --ignore-not-found "${DOCKER_SECRET_NAME}" -n "${NAMESPACE}"

# 4. Crear el nuevo secreto de Docker Registry
echo "Creando nuevo secreto..."
kubectl create secret docker-registry "${DOCKER_SECRET_NAME}" \
  --docker-server="https://${AWS_ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com" \
  --docker-username=AWS \
  --docker-password="${ECR_TOKEN}" \
  --namespace="${NAMESPACE}"

# 5. Anotar el secreto para que kubernetes-replicator lo copie
TARGET_NAMESPACES=faableauth,faable-deploy,argocd
echo "Anotando el secreto para replicación en $TARGET_NAMESPACES..."
kubectl annotate secret "${DOCKER_SECRET_NAME}" replicator.v1.mittwald.de/replicate-to="${TARGET_NAMESPACES}" --namespace="${NAMESPACE}"

echo "✅ Secret was successfully updated at $(date)"