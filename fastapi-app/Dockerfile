FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt ./

RUN pip install --no-cache-dir -r requirements.txt && \
    pip install --no-cache-dir \
    fastapi \
    uvicorn[standard]

COPY . .

ENV OTEL_PYTHON_LOG_LEVEL="info"
ENV OTEL_TRACES_EXPORTER="otlp"
ENV OTEL_METRICS_EXPORTER="otlp"
ENV OTEL_LOGS_EXPORTER="otlp"
ENV OTEL_EXPORTER_OTLP_PROTOCOL="grpc"
ENV OTEL_EXPORTER_OTLP_ENDPOINT="http://otel-collector:4317"
ENV OTEL_EXPORTER_OTLP_INSECURE="true"
ENV OTEL_SERVICE_NAME="fastapi-default-service"

ENV APP_PORT=8000
ENV APP_HOST="0.0.0.0"

EXPOSE ${APP_PORT}

CMD uvicorn "app.main:app" --host "$APP_HOST" --port "$APP_PORT"