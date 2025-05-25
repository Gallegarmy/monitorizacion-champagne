#!/bin/bash

# --- Configuración ---
NAMESPACE="monitoring"
GRAFANA_ADMIN_PASSWORD='prom-operator'
MINIO_ROOT_USER="mimir"
MINIO_ROOT_PASSWORD="mimirsecret"

# --- Funciones Auxiliares ---
check_command() {
  if ! command -v "$1" &> /dev/null; then
    echo "Error: '$1' no encontrado. Por favor, instálalo."
    exit 1
  fi
}

# --- Verificaciones Previas ---
check_command kubectl
check_command helm

echo ">>> Iniciando despliegue del PoC de Monitorización en el namespace '$NAMESPACE'..."

# 1. Namespace
kubectl create namespace "$NAMESPACE" 2>/dev/null || echo "Namespace '$NAMESPACE' ya existe."

# 2. Repos oficiales
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add minio https://charts.min.io/
helm repo update

# 3. MinIO standalone + PVC 5Gi + root perms
helm upgrade --install minio minio/minio \
  -n "$NAMESPACE" \
  --set mode=standalone \
  --set rootUser="$MINIO_ROOT_USER" \
  --set rootPassword="$MINIO_ROOT_PASSWORD" \
  --set persistence.enabled=true \
  --set persistence.size="5Gi" \
  --set persistence.storageClass="" \
  --set securityContext.runAsUser=0 \
  --set securityContext.runAsGroup=0 \
  --set securityContext.fsGroup=0 \
  --set resources.requests.memory="512Mi" \
  --set resources.requests.cpu="250m" \
  --set resources.limits.memory="1Gi" \
  --set resources.limits.cpu="500m" \
  --set serviceAccount.name="minio-instance-sa" \
  --wait

# 4. Crear buckets en MinIO
kubectl run --rm -i -n monitoring create-mimir-buckets \
  --image=minio/mc --restart=Never --command -- sh -c "\
    mc alias set myminio http://minio:9000 ${MINIO_ROOT_USER} ${MINIO_ROOT_PASSWORD} && \
    mc mb myminio/mimir-bucket-blocks && \
    mc mb myminio/mimir-bucket-rules && \
    mc mb myminio/mimir-bucket-alerts && \
    mc mb myminio/loki-chunks && \
    mc mb myminio/loki-index && \
    mc ls myminio \
  "

# 5. Loki
cat <<EOF > loki-values.yaml
replicaCount: 3

image:
  tag: "2.9.1"

memberlist:
  joinMembers: []

distributor:
  replicaCount: 2

ingester:
  replicaCount: 3
  lifecycler:
    ring:
      kvstore:
        store: memberlist
      replication_factor: 3

querier:
  replicaCount: 2

compactor:
  enabled: true
  replicaCount: 1

schemaConfig:
  configs:
    - from: "2022-01-01"
      store: boltdb-shipper
      object_store: s3
      schema: v12
      index:
        prefix: index_
        period: 24h

storageConfig:
  boltdb_shipper:
    active_index_directory: /data/loki/boltdb-shipper-active
    cache_location: /data/loki/boltdb-shipper-cache
    shared_store: s3
  aws:
    s3:
      endpoint: minio.monitoring.svc.cluster.local:9000
      bucketnames:
        - loki-chunks
        - loki-index
      access_key_id: "${MINIO_ROOT_USER}"
      secret_access_key: "${MINIO_ROOT_PASSWORD}"
      insecure: true

persistence:
  enabled: true
  storageClassName: ""
  accessModes:
    - ReadWriteOnce
  size: 10Gi

fluent-bit:
  enabled: false

promtail:
  enabled: false

grafana:
  enabled: false

ruler:
  enabled: true
  storage:
    type: s3
    s3:
      endpoint: minio.monitoring.svc.cluster.local:9000
      bucket_name: loki-rules
      access_key_id: "${MINIO_ROOT_USER}"
      secret_access_key: "${MINIO_ROOT_PASSWORD}"
      insecure: true
  extraVolumes:
    - name: ruler-volume
      emptyDir: {}
  extraVolumeMounts:
    - name: ruler-volume
      mountPath: /etc/loki/rules
      
EOF
helm upgrade --install loki grafana/loki-distributed -n "$NAMESPACE" -f loki-values.yaml --wait

# 6. Tempo
cat <<EOF > tempo-values.yaml
storage:
  trace:
    backend: local
traces:
  otlp:
    grpc: { enabled: true }
queryFrontend:
  service:
    port: 3200
    targetPort: 3200
EOF
helm upgrade --install tempo grafana/tempo-distributed -n "$NAMESPACE" -f tempo-values.yaml --wait

# 7. Mimir
cat <<EOF > mimir-values.yaml
minio:
  enabled: false
  mode: standalone
  rootUser: "${MINIO_ROOT_USER}"
  rootPassword: "${MINIO_ROOT_PASSWORD}"
  service:
    port: 9000
  buckets:
    - name: mimir-bucket-blocks
      policy: none
      purge: false
    - name: mimir-bucket-alerts
      policy: none
      purge: false
    - name: mimir-bucket-rules
      policy: none
      purge: false

serviceAccount:
  create: true
  name: mimir-sa

mimir:
  structuredConfig:
    alertmanager_storage:
      backend: s3
      s3:
        endpoint: minio.monitoring.svc.cluster.local:9000
        bucket_name: "mimir-bucket-alerts"
        access_key_id: "${MINIO_ROOT_USER}"
        secret_access_key: "${MINIO_ROOT_PASSWORD}"
        insecure: true
    blocks_storage:
      backend: s3
      s3:
        endpoint: minio.monitoring.svc.cluster.local:9000
        bucket_name: "mimir-bucket-blocks"
        access_key_id: "${MINIO_ROOT_USER}"
        secret_access_key: "${MINIO_ROOT_PASSWORD}"
        insecure: true
    ruler_storage:
      backend: s3
      s3:
        endpoint: minio.monitoring.svc.cluster.local:9000
        bucket_name: "mimir-bucket-rules"
        access_key_id: "${MINIO_ROOT_USER}"
        secret_access_key: "${MINIO_ROOT_PASSWORD}"
        insecure: true

distributor:
  replicas: 1
ingester:
  replicas: 1
querier:
  replicas: 1
compactor:
  replicas: 1
ruler:
  replicas: 1
storegateway:
  replicas: 1

alertmanager:
  persistence:
    enabled: true
  containerSecurityContext:
    readOnlyRootFilesystem: false
    allowPrivilegeEscalation: false

resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 1
    memory: 2Gi
EOF

helm upgrade --install mimir grafana/mimir-distributed -n "$NAMESPACE" \
  -f mimir-values.yaml --wait

# 8. Grafana con 3 DataSources
helm upgrade --install grafana grafana/grafana -n "$NAMESPACE" \
  --set persistence.enabled=true \
  --set persistence.size=2Gi \
  --set adminPassword="$GRAFANA_ADMIN_PASSWORD" \
  --set image.tag=9.5.18 \
  --set datasources."datasources\\.yaml".apiVersion=1 \
  --set datasources."datasources\\.yaml".datasources[0].name=Loki \
    --set datasources."datasources\\.yaml".datasources[0].type=loki \
    --set datasources."datasources\\.yaml".datasources[0].url=http://loki-loki-distributed-gateway.monitoring.svc.cluster.local:80 \
    --set datasources."datasources\\.yaml".datasources[0].access=proxy \
    --set datasources."datasources\\.yaml".datasources[0].uid=loki-ds \
    --set datasources."datasources\\.yaml".datasources[0].editable=true \
  --set datasources."datasources\\.yaml".datasources[1].name=Tempo \
    --set datasources."datasources\\.yaml".datasources[1].type=tempo \
    --set datasources."datasources\\.yaml".datasources[1].url=http://tempo-query-frontend.monitoring.svc.cluster.local:3100 \
    --set datasources."datasources\\.yaml".datasources[1].access=proxy \
    --set datasources."datasources\\.yaml".datasources[1].uid=tempo-ds \
    --set datasources."datasources\\.yaml".datasources[1].editable=true \
  --set datasources."datasources\\.yaml".datasources[2].name=Mimir \
    --set datasources."datasources\\.yaml".datasources[2].type=prometheus \
    --set datasources."datasources\\.yaml".datasources[2].url=http://mimir-nginx.monitoring.svc.cluster.local:80/prometheus \
    --set datasources."datasources\\.yaml".datasources[2].access=proxy \
    --set datasources."datasources\\.yaml".datasources[2].uid=mimir-ds \
    --set datasources."datasources\\.yaml".datasources[2].isDefault=true \
    --set datasources."datasources\\.yaml".datasources[2].editable=true \
  --wait

# 10. Crear archivo de configuración para Grafana Alloy
echo -e "\n>>> 10. Creando archivo de configuración 'alloy-values.yaml'..."

cat <<EOF > alloy-values.yaml
_river_config_content: &riverConfigContent |-
  logging {
    level  = "info"
    format = "logfmt"
  }

  discovery.kubernetes "pods" {
    role = "pod"
  }

  discovery.relabel "pod_targets" {
    targets = discovery.kubernetes.pods.targets

    rule {
      source_labels = ["__meta_kubernetes_pod_label_app"]
      target_label  = "app"
      action        = "replace"
    }
  }

  discovery.relabel "scrape_targets" {
    targets = discovery.relabel.pod_targets.output

    rule {
      source_labels = ["__meta_kubernetes_pod_annotation_prometheus_io_scrape"]
      regex         = "true"
      action        = "keep"
    }

    rule {
      source_labels = ["__address__", "__meta_kubernetes_pod_annotation_prometheus_io_port"]
      regex         = "([^;]+);(.+)"
      replacement   = "$1:$2"
      target_label  = "__address__"
    }
  }

  prometheus.remote_write "mimir" {
    endpoint {
      url = "http://mimir-nginx.monitoring.svc.cluster.local:80/api/v1/push"
      basic_auth {
        username = "mimir"
        password = "mimirsecret"
      }
      tls_config {
        insecure_skip_verify = true
      }
    }
  }

  prometheus.scrape "k8s_scrape" {
    targets         = discovery.relabel.scrape_targets.output
    scrape_interval = "15s"
    forward_to      = [prometheus.remote_write.mimir.receiver]
  }

  loki.source.kubernetes "read_logs" {
    targets    = discovery.relabel.pod_targets.output
    forward_to = [loki.write.loki_monitoring.receiver]
  }

  loki.write "loki_monitoring" {
    endpoint {
      url = "http://loki-loki-distributed-gateway.monitoring.svc.cluster.local:80/loki/api/v1/push"
    }
  }

  otelcol.receiver.otlp "default" {
    debug_metrics {
      disable_high_cardinality_metrics = true
    }
    grpc {
      endpoint = "0.0.0.0:4317"
    }
    http {
      endpoint = "0.0.0.0:4318"
    }
    output {
      metrics = [otelcol.processor.k8sattributes.default.input]
      traces  = [otelcol.processor.k8sattributes.default.input]
    }
  }

  otelcol.processor.k8sattributes "default" {
    auth_type = "serviceAccount"
    extract {
      metadata = [
        "k8s.pod.name", "k8s.pod.uid", "k8s.pod.start_time",
        "k8s.deployment.name", "k8s.namespace.name", "k8s.node.name",
        "k8s.replicaset.name", "k8s.statefulset.name", "k8s.daemonset.name",
        "k8s.job.name", "k8s.cronjob.name", "container.id",
      ]
    }
    debug_metrics { disable_high_cardinality_metrics = true }
    output {
      metrics = [otelcol.exporter.prometheus.default.input]
      traces  = [otelcol.exporter.otlp.tempo_monitoring.input]
    }
  }

  otelcol.exporter.otlp "tempo_monitoring" {
    client {
      endpoint = "tempo-distributor.monitoring.svc.cluster.local:4317"
      tls {
        insecure = true
      }
    }
  }

  otelcol.exporter.prometheus "default" {
    forward_to = [prometheus.remote_write.mimir.receiver]
  }

  prometheus.exporter.self "alloy_metrics" {}

alloy:
  configMap:
    create: true
    content: *riverConfigContent
  clustering:
    enabled: false
  listenPort: 12345
  extraPorts:
    - name: otlp-grpc
      port: 4317
      targetPort: 4317
      protocol: TCP
    - name: otlp-http
      port: 4318
      targetPort: 4318
      protocol: TCP
  mounts:
    varlog: true
    dockercontainers: true

controller:
  type: daemonset

rbac:
  create: true

serviceAccount:
  create: true

service:
  enabled: true
  type: ClusterIP
EOF

echo "'alloy-values.yaml' creado."

# 11. Desplegar Grafana Alloy como DaemonSet
echo -e "\n>>> 11. Desplegando Grafana Alloy como DaemonSet..."
helm repo update
helm upgrade --install alloy grafana/alloy -n "$NAMESPACE" -f alloy-values.yaml --wait

# 12. Instrucciones finales
echo -e "\n>>> Despliegue completado."
echo "Namespace: $NAMESPACE"
echo "Admin Grafana: $GRAFANA_ADMIN_PASSWORD"
echo ""
echo "Accede a Grafana:"
echo "  kubectl port-forward svc/grafana -n $NAMESPACE 3000:80"
echo "  http://localhost:3000"
echo ""
echo "Verifica pods:"
echo "  kubectl get pods -n $NAMESPACE"
