from fastapi import APIRouter, HTTPException
from opentelemetry import trace, metrics
from app.main import task_counter  # shared counter for internal tasks
from .utils import perform_task, generate_logs, simulate_external_call
import random
import time  # use Python time module for timing

router = APIRouter()

tracer = trace.get_tracer(__name__)
meter = metrics.get_meter(__name__)

# RED (Rate, Errors, Duration) metrics
request_counter = meter.create_counter(
    "http_requests_total",
    description="Total number of HTTP requests received"
)
error_counter = meter.create_counter(
    "http_errors_total",
    description="Total number of HTTP error responses"
)
duration_histogram = meter.create_histogram(
    "http_request_duration_ms",
    description="Duration of HTTP requests in milliseconds"
)

def record_metrics(route: str, duration: float, error: bool = False):
    # Record duration (ms) and attributes
    duration_histogram.record(duration * 1000, {"route": route})
    request_counter.add(1, {"route": route})
    if error:
        error_counter.add(1, {"route": route})

@router.get("/process")
async def process_endpoint():
    """
    Simulate multiple internal tasks, generating traces, metrics, and logs.
    """
    with tracer.start_as_current_span("process-endpoint"):
        start_time = time.time()
        for i in range(5):
            with tracer.start_as_current_span(f"task-{i}"):
                duration = await perform_task(i)
                task_counter.add(1)
                await generate_logs(i, duration)
        total_duration = time.time() - start_time
        record_metrics("/process", total_duration)
    return {"status": "completed", "tasks_executed": 5, "duration_s": total_duration}

@router.get("/compute")
async def compute_endpoint(count: int = 10):
    """
    Perform fake CPU-bound workload by sleeping count times.
    """
    start_time = time.time()
    with tracer.start_as_current_span("compute-endpoint"):
        for _ in range(count):
            await perform_task(random.randint(1, 3))
    total_duration = time.time() - start_time
    record_metrics("/compute", total_duration)
    return {"status": "compute done", "iterations": count, "duration_s": total_duration}

@router.get("/error")
async def error_endpoint():
    """
    Endpoint that always returns HTTP 500 to simulate errors.
    """
    start_time = time.time()
    try:
        raise RuntimeError("Simulated error for testing")
    except RuntimeError as exc:
        duration = time.time() - start_time
        record_metrics("/error", duration, True)
        tracer.get_current_span().record_exception(exc)
        await generate_logs(-1, 0)
        raise HTTPException(status_code=500, detail=str(exc))

@router.get("/external-call")
async def external_call_endpoint():
    """
    Simulate an external HTTP call with random latency.
    """
    start_time = time.time()
    with tracer.start_as_current_span("external-call"):
        result = await simulate_external_call()
    total_duration = time.time() - start_time
    record_metrics("/external-call", total_duration)
    return {"status": "external result", "data": result, "duration_s": total_duration}
