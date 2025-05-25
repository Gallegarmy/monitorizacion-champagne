# Monitoring Party

Este repositorio contiene los scripts y manifiestos para desplegar una aplicación FastAPI junto con un stack de monitorización (Prometheus, Grafana, Loki, Tempo, Mimir y MinIO) en un clúster de Kubernetes usando Minikube.

## Estructura del repositorio

-   `.gitignore`: Archivos y carpetas ignorados por Git.
-   `deploy_all.sh`: Script principal para desplegar el stack de monitorización en el namespace `monitoring`.
-   `request-test.sh`: Script para enviar peticiones aleatorias a los endpoints de la aplicación FastAPI y medir latencias.
-   `fastapi-app/`: Código fuente y Dockerfile de la aplicación FastAPI.
    -   `app/`: Módulos Python (`main.py`, `router.py`, `utils.py`).
    -   `Dockerfile`: Imagen Docker de la aplicación.
    -   `requirements.txt`: Dependencias de Python.
-   `k8s-manifests/fastapi-app/`: Manifiestos Kubernetes para desplegar la aplicación FastAPI en el namespace `default`.
    -   `deployment.yml`
    -   `service.yml`
    -   `ingress.yml`

## Prerrequisitos

-   Docker
-   Minikube
-   Kubectl
-   Helm
-   Curl (para pruebas)

## Despliegue

1. Iniciar Minikube con profile y driver Docker:
    ```bash
    minikube start --nodes=1 --driver=docker -p monitoring
    ```
2. Seleccionar el contexto de Kubernetes:
    ```bash
    kubectl config use-context monitoring
    ```
3. Ejecutar el script de despliegue:

    ```bash
    ./deploy_all.sh
    ```

    Este script:

    - Comprueba que `helm`, `kubectl`, `minikube` y `curl` están instalados.
    - Añade los repositorios de Helm:
        - grafana
        - prometheus-community
        - minio
    - Genera los archivos de valores (`loki-values.yaml`, `tempo-values.yaml`, `mimir-values.yaml`, `alloy-values.yaml`).
    - Despliega los charts de MinIO, Prometheus, Grafana, Loki, Tempo, Mimir y Alloy.
    - Muestra información final de acceso a Grafana.

4. Desplegar la aplicación FastAPI:
    ```bash
    kubectl apply -f k8s-manifests/fastapi-app/
    ```

## Parada del entorno

Para detener y eliminar el cluster de Minikube:

```bash
minikube stop -p monitoring
minikube delete -p monitoring
```

## Pruebas de la aplicación

El script `request-test.sh` envía peticiones a los siguientes endpoints:

```bash
BASE_URL="http://localhost:8000"
ENDPOINTS=( "/process" "/compute" "/error" "/external-call" )
```

-   Variables opcionales:
    -   `NUM_REQUESTS`: número total de peticiones (por defecto infinito).
    -   `MAX_SLEEP`: máximo tiempo de espera entre peticiones (por defecto `2.0`).

Ejemplo de uso:

```bash
NUM_REQUESTS=50 MAX_SLEEP=1.5 ./request-test.sh
```

Cada petición muestra la hora, URL, código HTTP y tiempo de respuesta.

## Exposición de URLs

-   **FastAPI**:

    ```bash
    kubectl port-forward svc/fastapi-app-service -n default 8000:8000
    ```

    Accede en `http://localhost:8000`.

-   **Grafana**:
    ```bash
    kubectl port-forward svc/grafana -n monitoring 3000:80
    ```
    Accede en `http://localhost:3000` (usuario: `admin`, contraseña: `prom-operator`).

## Detalles de la aplicación FastAPI

-   Código en `fastapi-app/app/`.
-   Endpoints disponibles:
    -   `/process`
    -   `/compute?count=<n>`
    -   `/error`
    -   `/external-call`
-   Métricas OTLP y Prometheus habilitadas.

## Manifiestos de Kubernetes para FastAPI

-   `k8s-manifests/fastapi-app/deployment.yml`: Deployment de la aplicación.
-   `k8s-manifests/fastapi-app/service.yml`: Servicio ClusterIP con anotaciones para Prometheus.
-   `k8s-manifests/fastapi-app/ingress.yml`: Ingress configurado con host `test.com`.
