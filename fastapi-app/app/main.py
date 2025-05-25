from fastapi import FastAPI
from starlette.responses import PlainTextResponse
from opentelemetry import trace, metrics
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.logging import LoggingInstrumentor
from prometheus_client import generate_latest, CONTENT_TYPE_LATEST

# Define shared resource attributes
resource = Resource.create({"service.name": "fastapi-otel-poc"})

# --- Tracing Setup ---
trace.set_tracer_provider(TracerProvider(resource=resource))
span_exporter = OTLPSpanExporter()
trace.get_tracer_provider().add_span_processor(BatchSpanProcessor(span_exporter))
tracer = trace.get_tracer(__name__)

# --- Metrics Setup ---
metric_exporter = OTLPMetricExporter()
metric_reader = PeriodicExportingMetricReader(metric_exporter, export_interval_millis=5000)
metrics.set_meter_provider(MeterProvider(resource=resource, metric_readers=[metric_reader]))
meter = metrics.get_meter(__name__)

# Create a counter for internal tasks executed
task_counter = meter.create_counter(
    "internal_tasks_executed",
    description="Number of internal tasks executed"
)

# Initialize FastAPI and instrument
app = FastAPI()
FastAPIInstrumentor.instrument_app(app)
LoggingInstrumentor().instrument(set_logging_format=True)

@app.get("/metrics")
async def prometheus_metrics():
    """
    Expose metrics in Prometheus format.
    """
    data = generate_latest()
    return PlainTextResponse(data, media_type=CONTENT_TYPE_LATEST)

# Include application routes
from app.router import router
app.include_router(router)