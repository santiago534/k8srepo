#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Despliegue automático en Minikube de un sitio web estático con Kubernetes
# Autor: Santiago Galdos - Mayo 2025
# =============================================================================

# === VERIFICACIÓN DE HERRAMIENTAS REQUERIDAS ===
for herramienta in git kubectl minikube docker; do
  if ! command -v "$herramienta" >/dev/null 2>&1; then
    echo -e "\n❌ No se encontró la herramienta '$herramienta' en el sistema. Verificá que esté instalada y accesible desde el PATH.\n"
    exit 1
  fi
done

# === CONFIGURACIÓN INICIAL ===
RUTA_SCRIPT="${BASH_SOURCE[0]:-$0}"
CARPETA_BASE="$(cd "$(dirname "$RUTA_SCRIPT")" && pwd)"
CARPETA_SITIO="./sitio-web"
CARPETA_K8S="./k8srepo"

REPO_WEB="https://github.com/santiago534/static-website.git"
REPO_K8S="https://github.com/santiago534/k8srepo.git"

PERFIL_MINIKUBE="sitio-web-profile"
NS_K8S="sitio-web-ns"
CTX_K8S="sitio-web-context"

DEPLOYMENT_WEB="institucional-web"
SERVICIO_WEB="institucional-web-svc"

# =============================================================================
# DESCARGA Y VALIDACIÓN DE ARCHIVOS
# =============================================================================

echo -e "\n🔍 Preparando el entorno de trabajo..."

# Clonado del repositorio del sitio web
if [ ! -d "$CARPETA_SITIO" ]; then
  echo "📥 Descargando el sitio web..."
  git clone "$REPO_WEB" "./static-website"
  mv "./static-website" "$CARPETA_SITIO"
  echo "📁 Se renombró la carpeta a 'sitio-web'"
else
  echo "📁 El sitio web ya fue descargado anteriormente en '$CARPETA_SITIO'"
fi

# Verificación de archivos esenciales
if [[ ! -f "$CARPETA_SITIO/index.html" || ! -f "$CARPETA_SITIO/style.css" ]]; then
  echo "⚠️ No se encuentran los archivos requeridos: index.html y/o style.css"
  exit 1
fi

# Clonado del repositorio de manifiestos Kubernetes
if [ ! -d "$CARPETA_K8S" ]; then
  echo "📥 Clonando los manifiestos de Kubernetes..."
  git clone "$REPO_K8S" "$CARPETA_K8S"
else
  echo "📁 Los manifiestos ya están disponibles en '$CARPETA_K8S'"
fi

# Comprobación de archivos clave
for archivo in "$CARPETA_K8S/volume/volume.yaml" "$CARPETA_K8S/deployment/deployment.yaml" "$CARPETA_K8S/services/service.yaml"; do
  if [ ! -f "$archivo" ]; then
    echo "❌ No se pudo encontrar el archivo necesario: $archivo"
    exit 1
  fi
done

# =============================================================================
# INICIO DEL ENTORNO MINIKUBE
# =============================================================================

echo -e "\n🚀 Configurando entorno Minikube con perfil '$PERFIL_MINIKUBE'..."

if minikube status -p "$PERFIL_MINIKUBE" | grep -q "host: Running"; then
  echo "ℹ️ Minikube ya se encuentra activo. Validando si el montaje fue correcto..."
  CONTENIDO_MONTADO=$(minikube -p "$PERFIL_MINIKUBE" ssh -- ls -A /mnt/sitio-web 2>/dev/null || true)
  if [ -z "$CONTENIDO_MONTADO" ]; then
    echo "🔄 El volumen está vacío. Se reiniciará Minikube con el montaje adecuado..."
    minikube delete -p "$PERFIL_MINIKUBE"
    minikube start -p "$PERFIL_MINIKUBE" --driver=docker --mount --mount-string="$CARPETA_SITIO:/mnt/sitio-web"
  else
    echo "✅ El montaje fue detectado correctamente en '/mnt/sitio-web'"
  fi
else
  echo "🟢 Iniciando Minikube con el perfil especificado..."
  minikube start -p "$PERFIL_MINIKUBE" --driver=docker --mount --mount-string="$CARPETA_SITIO:/mnt/sitio-web"
fi

# =============================================================================
# CONTEXTO Y ESPACIO DE NOMBRES
# =============================================================================

echo -e "\n⚙️ Configurando el contexto de Kubernetes..."

kubectl config set-context "$CTX_K8S" --cluster="$PERFIL_MINIKUBE" --user="$PERFIL_MINIKUBE" --namespace="$NS_K8S" >/dev/null 2>&1 || true
kubectl config use-context "$CTX_K8S" >/dev/null 2>&1

kubectl get namespace "$NS_K8S" >/dev/null 2>&1 || kubectl create namespace "$NS_K8S"

# =============================================================================
# ACTIVACIÓN DE ADDONS
# =============================================================================

echo -e "\n🧩 Verificando y activando addons necesarios..."

for addon in storage-provisioner default-storageclass metrics-server; do
  echo -e "\n🔎 Comprobando el addon: $addon"
  if minikube addons list -p "$PERFIL_MINIKUBE" | grep -E "^$addon\s+enabled" >/dev/null; then
    echo "✅ El addon '$addon' ya está activo."
  else
    echo "➕ Habilitando '$addon'..."
    minikube addons enable "$addon" -p "$PERFIL_MINIKUBE" >/dev/null 2>&1 && echo "✅ Activado con éxito."
  fi
done

# =============================================================================
# DESPLIEGUE DE MANIFIESTOS
# =============================================================================

echo -e "\n📦 Desplegando los componentes de Kubernetes..."

if ! kubectl get pvc institucional-web-pvc >/dev/null 2>&1; then
  kubectl apply -f "$CARPETA_K8S/volume/volume.yaml"
else
  echo "📄 El PVC ya existe. No se vuelve a crear."
fi

if ! kubectl get deployment "$DEPLOYMENT_WEB" >/dev/null 2>&1; then
  kubectl apply -f "$CARPETA_K8S/deployment/deployment.yaml"
else
  echo "📄 El Deployment ya está presente."
fi

if ! kubectl get service "$SERVICIO_WEB" >/dev/null 2>&1; then
  kubectl apply -f "$CARPETA_K8S/services/service.yaml"
else
  echo "📄 El Service ya fue creado previamente."
fi

# =============================================================================
# ESPERA ACTIVA HASTA QUE LOS PODS ESTÉN LISTOS
# =============================================================================

echo -e "\n⏳ Esperando que los pods estén completamente operativos..."

until kubectl get deployment "$DEPLOYMENT_WEB" >/dev/null 2>&1; do
  echo "⌛ Aguardando que se cree el deployment..."
  sleep 2
done

until kubectl get pods | grep "$DEPLOYMENT_WEB" >/dev/null 2>&1; do
  echo "⌛ Aguardando que aparezcan los pods..."
  sleep 2
done

PODS_ESPERADOS=$(kubectl get deployment "$DEPLOYMENT_WEB" -o jsonpath="{.spec.replicas}")
echo "⌛ Se esperan $PODS_ESPERADOS pod(s) en estado Running..."

until [ "$(kubectl get pods | grep "$DEPLOYMENT_WEB" | grep -c '1/1')" -eq "$PODS_ESPERADOS" ]; do
  echo -n "."
  sleep 2
done

echo -e "\n✅ Todos los pods están ahora en ejecución."

# =============================================================================
# RESUMEN FINAL Y ACCESO
# =============================================================================

echo -e "\n📋 Estado general del entorno (namespace: $NS_K8S):"

echo -e "\n🧱 Pods:"
kubectl get pods

echo -e "\n🌐 Servicios:"
kubectl get svc

echo -e "\n💽 Volúmenes Persistentes:"
kubectl get pv

echo -e "\n📦 Claims de Volumen:"
kubectl get pvc

echo -e "\n🌐 Abriendo el servicio en el navegador..."
minikube service "$SERVICIO_WEB" -p "$PERFIL_MINIKUBE" -n "$NS_K8S"

echo -e "\n🟢 El entorno de despliegue ya estaba configurado. No se detectaron cambios nuevos."
