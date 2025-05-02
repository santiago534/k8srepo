
#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Script de despliegue automático en Kubernetes usando Minikube
# Despliega una web estática montada desde el host como volumen persistente.
# Autor: Santiago Galdos
# Fecha: 2025-05
# =============================================================================

# === VALIDACIÓN DE DEPENDENCIAS ===
for cmd in git kubectl minikube docker; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo -e "\n❌ Error: La herramienta '$cmd' no está instalada o no está en el PATH.\n"
    exit 1
  fi
done
# === CONFIGURACIÓN DE VARIABLES ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOUNT_DIR="./sitio-web"
MANIFIESTOS_DIR="./k8srepo"

REPO_SITIO="https://github.com/santiago534/static-website.git"
REPO_MANIFIESTOS="https://github.com/santiago534/k8srepo.git"

PROFILE="sitio-web-profile"
NAMESPACE="sitio-web-ns"
CONTEXT="sitio-web-context"

DEPLOYMENT_NAME="institucional-web"
SERVICE_NAME="institucional-web-svc"

# =============================================================================
# CLONAR Y VERIFICAR REPOSITORIOS
# =============================================================================

echo -e "\n Preparando entorno de archivos..."

# Clonar sitio web
if [ ! -d "$MOUNT_DIR" ]; then
  echo " Clonando repositorio de sitio web..."
  git clone "$REPO_SITIO" "./static-website"
  mv "./static-website" "$MOUNT_DIR"
  echo " Carpeta renombrada de 'static-website' a 'sitio-web'"
else
  echo " Sitio web ya clonado en $MOUNT_DIR"
fi

# Verificar archivos esenciales
if [[ ! -f "$MOUNT_DIR/index.html" || ! -f "$MOUNT_DIR/style.css" ]]; then
  echo " Error: Faltan archivos esenciales (index.html o style.css) en el sitio web."
  exit 1
fi

# Clonar manifiestos
if [ ! -d "$MANIFIESTOS_DIR" ]; then
  echo " Clonando manifiestos Kubernetes..."
  git clone "$REPO_MANIFIESTOS" "$MANIFIESTOS_DIR"
else
  echo " Manifiestos ya clonados en $MANIFIESTOS_DIR"
fi

# Verificar archivos críticos
for file in "$MANIFIESTOS_DIR/volume/volume.yaml" "$MANIFIESTOS_DIR/deployment/deployment.yaml" "$MANIFIESTOS_DIR/services/service.yaml"; do
  if [ ! -f "$file" ]; then
    echo " Error: No se encontró el archivo requerido: $file"
    exit 1
  fi
done


# =============================================================================
# INICIAR MINIKUBE CON PERFIL DEDICADO Y MONTAJE
# =============================================================================

echo -e "\n🚀 Iniciando entorno Minikube (perfil: $PROFILE)..."

if minikube status -p "$PROFILE" | grep -q "host: Running"; then
  echo "⚙️  Minikube ya está corriendo en perfil '$PROFILE'. Verificando montaje..."
  MOUNTED_CONTENT=$(minikube -p "$PROFILE" ssh -- ls -A /mnt/sitio-web 2>/dev/null || true)
  if [ -z "$MOUNTED_CONTENT" ]; then
    echo "⚠️  Montaje vacío. Reiniciando perfil '$PROFILE' con montaje..."
    minikube delete -p "$PROFILE"
    minikube start -p "$PROFILE" --driver=docker --mount --mount-string="$MOUNT_DIR:/mnt/sitio-web"
  else
    echo "✅ Montaje correcto en /mnt/sitio-web"
  fi
else
  echo "🚀 Iniciando Minikube con perfil '$PROFILE'..."
  minikube start -p "$PROFILE" --driver=docker --mount --mount-string="$MOUNT_DIR:/mnt/sitio-web"
fi

# =============================================================================
# CONTEXTO Y NAMESPACE DEDICADO
# =============================================================================

echo -e "\n🔧 Configurando contexto y namespace..."

kubectl config set-context "$CONTEXT" --cluster="$PROFILE" --user="$PROFILE" --namespace="$NAMESPACE" >/dev/null 2>&1 || true
kubectl config use-context "$CONTEXT" >/dev/null 2>&1

kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 || kubectl create namespace "$NAMESPACE"

# =============================================================================
# HABILITAR ADDONS NECESARIOS
# =============================================================================

echo -e "\n⚙️  Activando addons necesarios..."

for addon in storage-provisioner default-storageclass metrics-server; do
  echo -e "\n➡️  Revisando addon: $addon..."
  if minikube addons list -p "$PROFILE" | grep -E "^$addon\s+enabled" >/dev/null; then
    echo "✅ El addon '$addon' ya está activo."
  else
    echo "🔄 Activando addon '$addon'..."
    minikube addons enable "$addon" -p "$PROFILE" >/dev/null 2>&1 && echo "✅ Habilitado"
  fi
done

# =============================================================================
# APLICAR MANIFIESTOS DE KUBERNETES
# =============================================================================

echo -e "\n📦 Aplicando manifiestos..."

if ! kubectl get pvc institucional-web-pvc >/dev/null 2>&1; then
  kubectl apply -f "$MANIFIESTOS_DIR/volume/volume.yaml"
else
  echo "ℹ️  PVC ya existe. Se omite."
fi

if ! kubectl get deployment "$DEPLOYMENT_NAME" >/dev/null 2>&1; then
  kubectl apply -f "$MANIFIESTOS_DIR/deployment/deployment.yaml"
else
  echo "ℹ️  Deployment ya existe. Se omite."
fi

if ! kubectl get service "$SERVICE_NAME" >/dev/null 2>&1; then
  kubectl apply -f "$MANIFIESTOS_DIR/services/service.yaml"
else
  echo "ℹ️  Service ya existe. Se omite."
fi

# =============================================================================
# ESPERAR A QUE LOS PODS ESTÉN LISTOS
# =============================================================================

echo -e "\n⏳ Esperando que los pods estén en estado Running..."

until kubectl get deployment "$DEPLOYMENT_NAME" >/dev/null 2>&1; do
  echo "⏳ Esperando creación del deployment..."
  sleep 2
done

until kubectl get pods | grep "$DEPLOYMENT_NAME" >/dev/null 2>&1; do
  echo "⏳ Esperando creación de pods..."
  sleep 2
done

EXPECTED_READY=$(kubectl get deployment "$DEPLOYMENT_NAME" -o jsonpath="{.spec.replicas}")
echo "⏳ Esperando que $EXPECTED_READY pod(s) estén en estado Running..."

until [ "$(kubectl get pods | grep "$DEPLOYMENT_NAME" | grep -c '1/1')" -eq "$EXPECTED_READY" ]; do
  echo -n "."
  sleep 2
done

echo -e "\n✅ Todos los pods están ahora en estado Running."

# =============================================================================
# ESTADO FINAL Y ACCESO
# =============================================================================

echo -e "\n🔍 Estado del clúster (namespace: $NAMESPACE):"

echo -e "\n📦 Pods:"
kubectl get pods

echo -e "\n🌐 Services:"
kubectl get svc

echo -e "\n💾 Persistent Volumes:"
kubectl get pv

echo -e "\n📦 Persistent Volume Claims:"
kubectl get pvc

echo -e "\n🌐 Abriendo el sitio en el navegador..."
minikube service "$SERVICE_NAME" -p "$PROFILE" -n "$NAMESPACE"
