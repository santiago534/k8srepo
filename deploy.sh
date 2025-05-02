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

# === CONFIGURACIÓN ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
MOUNT_DIR="$ROOT_DIR/sitio-web"
REPO_SITIO="https://github.com/santiago534/static-website.git"
DEPLOYMENT_NAME="institucional-web"
SERVICE_NAME="institucional-web-svc"

# === CLONAR SITIO WEB SI NO EXISTE ===
if [ ! -d "$MOUNT_DIR" ]; then
  echo -e "\n🌐 Clonando repositorio de sitio web..."
  git clone "$REPO_SITIO" "$ROOT_DIR/static-website"

  if [ -d "$ROOT_DIR/static-website" ]; then
    mv "$ROOT_DIR/static-website" "$MOUNT_DIR"
    echo "✅ Carpeta renombrada de 'static-website' a 'sitio-web'"
  fi
else
  echo -e "\n📁 El sitio web ya está clonado en $MOUNT_DIR"
fi

# === INICIAR MINIKUBE CON VALIDACIÓN DE MOUNT ===
echo -e "\n🧪 Verificando estado de Minikube y montaje..."

if minikube status | grep -q "host: Running"; then
  echo "⚙️  Minikube está corriendo. Verificando si el montaje funciona correctamente..."

  MOUNTED_CONTENT=$(minikube ssh -- ls -A /mnt/sitio-web 2>/dev/null || true)

  if [ -z "$MOUNTED_CONTENT" ]; then
    echo -e "⚠️  Minikube está corriendo pero la carpeta montada está vacía o no accesible."
    echo -e "🔄 Eliminando y reiniciando Minikube con montaje..."
    minikube delete
    minikube start --driver=docker --mount --mount-string="$MOUNT_DIR:/mnt/sitio-web"
  else
    echo "✅ Montaje verificado dentro de Minikube. Continuando..."
  fi
else
  echo "🚀 Iniciando Minikube con montaje..."
  minikube start --driver=docker --mount --mount-string="$MOUNT_DIR:/mnt/sitio-web"
fi

# === HABILITAR ADDONS NECESARIOS ===
echo -e "\n⚙️  Verificando y activando addons..."

for addon in storage-provisioner default-storageclass metrics-server; do
  echo -e "\n➡️  Revisando addon: $addon..."
  
  if minikube addons list | grep -E "^$addon\s+enabled" >/dev/null; then
    echo "✅ El addon '$addon' ya está activo."
  else
    echo "🔄 Activando addon '$addon'..."
    if minikube addons enable "$addon" >/dev/null 2>&1; then
      echo "✅ Addon '$addon' habilitado correctamente."
    else
      echo "❌ Error al habilitar el addon '$addon'."
      exit 1
    fi
  fi
done

# === APLICAR MANIFIESTOS DE KUBERNETES ===
echo -e "\n📦 Aplicando manifiestos..."

# Volumen
if ! kubectl get pvc institucional-web-pvc &>/dev/null; then
  kubectl apply -f "$SCRIPT_DIR/volume/volume.yaml"
  echo "✅ volume.yaml aplicado"
else
  echo "ℹ️  El PVC institucional-web-pvc ya existe. Se omite volume.yaml"
fi

# Deployment
if ! kubectl get deployment institucional-web &>/dev/null; then
  kubectl apply -f "$SCRIPT_DIR/deployment/deployment.yaml"
  echo "✅ deployment.yaml aplicado"
else
  echo "ℹ️  El Deployment institucional-web ya existe. Se omite deployment.yaml"
fi

# Service
if ! kubectl get service institucional-web-svc &>/dev/null; then
  kubectl apply -f "$SCRIPT_DIR/services/service.yaml"
  echo "✅ service.yaml aplicado"
else
  echo "ℹ️  El Service institucional-web-svc ya existe. Se omite service.yaml"
fi

# === ESPERAR QUE LOS PODS ESTÉN EN RUNNING ===
echo -e "\n⏳ Verificando estado de los pods del deployment '$DEPLOYMENT_NAME'..."

until kubectl get deployment "$DEPLOYMENT_NAME" &>/dev/null; do
  echo "⏳ Esperando a que se cree el deployment '$DEPLOYMENT_NAME'..."
  sleep 2
done

until kubectl get pods | grep "$DEPLOYMENT_NAME" &>/dev/null; do
  echo "⏳ Esperando a que se cree algún pod del deployment '$DEPLOYMENT_NAME'..."
  sleep 2
done

EXPECTED_READY=$(kubectl get deployment "$DEPLOYMENT_NAME" -o jsonpath="{.spec.replicas}")
echo "⏳ Esperando que $EXPECTED_READY pod(s) estén en estado Running..."

until [ "$(kubectl get pods | grep "$DEPLOYMENT_NAME" | grep -c '1/1')" -eq "$EXPECTED_READY" ]; do
  echo -n "."
  sleep 2
done

echo -e "\n✅ Todos los pods están ahora en estado Running."

# === MOSTRAR ESTADO DEL CLÚSTER ===
echo -e "\n🔍 Estado del clúster:"

echo -e "\n📦 Pods:"
kubectl get pods

echo -e "\n🌐 Services:"
kubectl get svc

echo -e "\n💾 Persistent Volumes:"
kubectl get pv

echo -e "\n📦 Persistent Volume Claims:"
kubectl get pvc

# === ABRIR LA PÁGINA EN EL NAVEGADOR ===
echo -e "\n🌐 Abriendo el sitio en el navegador..."
minikube service "$SERVICE_NAME"
