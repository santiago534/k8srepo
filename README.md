# k8srepo

Repositorio de Kubernetes para el despliegue de una página web estática usando Minikube y volúmenes persistentes.

## Requisitos previos

Se debe tener instalado:

- Docker
- Minikube
- kubectl
- Acceso a una terminal Linux (preferentemente WSL si estás en Windows)

## Estructura del proyecto


Deberemos crear una carpeta llamada `proyecto-devops` y clonar **ambos repositorios**: este repositorio (`k8srepo`) y el repositorio con el contenido web `static-website`:  
https://github.com/santiago534/static-website.git


## aplicamos los addons y montajes necesarios para que el proyecto funcione correctamente 
minikube start --driver=docker --mount --mount-string="/home/santi/proyecto-devops/sitio-web:/mnt/sitio-web"
minikube addons enable storage-provisioner
minikube addons enable default-storageclass
minikube addons enable metrics-serverkube

## 2. Aplicar los maniifiestos yaml 

cd ../deployment/
kubectl apply -f deployment.yaml

cd ../services/
kubectl apply -f service.yaml

cd ../volume/
kubectl apply -f volume.yaml

## 3. verificar que todo funcione correctamente
kubectl get pods
kubectl get svc
kubectl get pv
kubectl get pvc
## 4. por ultimo acceder a la pagina desde el navegador
minikube service institucional-web-svc
