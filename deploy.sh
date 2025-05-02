#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Script de despliegue automático en Kubernetes usando Minikube
# Despliega una web estática montada desde el host como volumen persistente.
# Autor: santi 💻
# Fecha: 2025-05
# -----------------------------------------------------------------------------

# === VALIDACIÓN DE DEPENDENCIAS ===
for cmd in git kubectl minikube docker; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "❌ Error: La herramienta '$cmd' no está instalada o no está en el PATH."
    exit 1
  fi
done

# === CONFIGURACIÓN ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"  # Ruta absoluta del script
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
MOUNT_DIR="$ROOT_DIR/sitio-web"
REPO_SITIO="https://github.com/santiago534/static-website.git"
DEPLOYMENT_NAME="institucional-web"
SERVICE_NAME="institucional-web-svc"

# === CLONAR SITIO WEB SI NO EXISTE ===
if [ ! -d "$MOUNT_DIR" ]; then
  echo "🌐 Clonando repositorio de sitio web..."
  git clone "$REPO_SITIO" "$MOUNT_DIR"
else
  echo "📁 El sitio web ya está clonado en $MOUNT_DIR"
fi

# === INICIAR MINIKUBE CON MOUNT ===
echo "🚀 Iniciando Minikube con el volumen montado..."
minikube start --driver=docker \
  --mount --mount-string="$MOUNT_DIR:/mnt/sitio-web"

# === HABILITAR ADDONS NECESARIOS ===
echo "⚙️  Activando addons..."
minikube addons enable storage-provisioner
minikube addons enable default-storageclass
minikube addons enable metrics-server

# === APLICAR MANIFIESTOS DE KUBERNETES ===
echo "📦 Aplicando manifiestos..."
kubectl apply -f "$SCRIPT_DIR/volume/volume.yaml"
kubectl apply -f "$SCRIPT_DIR/deployment/deployment.yaml"
kubectl apply -f "$SCRIPT_DIR/services/service.yaml"

# === ESPERAR QUE LOS PODS ESTÉN EN RUNNING ===
echo "⏳ Esperando que los pods estén en estado Running..."
until kubectl get pods | grep "$DEPLOYMENT_NAME" | grep -q "1/1"; do
  echo -n "."
  sleep 2
done
echo -e "\n✅ Todos los pods están listos."

# === MOSTRAR ESTADO DEL CLUSTER ===
echo "🔍 Estado del clúster:"
kubectl get pods
kubectl get svc
kubectl get pv
kubectl get pvc

# === ABRIR LA PÁGINA EN EL NAVEGADOR ===
echo "🌐 Abriendo el sitio en el navegador..."
minikube service "$SERVICE_NAME"
