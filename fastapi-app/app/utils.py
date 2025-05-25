import time
import logging
import random
import asyncio

logger = logging.getLogger("app.utils")

async def perform_task(index: int) -> float:
    """
    Simulate an internal task by sleeping for a short time.
    Returns the elapsed time in seconds.
    """
    start = time.time()
    await asyncio.sleep(0.1 * index)
    return time.time() - start

async def generate_logs(index: int, duration: float):
    """
    Log task completion details. Emit a warning if duration exceeds threshold.
    """
    logger.info(f"Task {index} completed in {duration:.3f}s")
    if duration > 0.3:
        logger.warning(f"Task {index} took longer than expected: {duration:.3f}s")

async def simulate_external_call() -> dict:
    """
    Simulate an external HTTP call by sleeping a random time and returning dummy data.
    """
    latency = random.uniform(0.05, 0.2)
    await asyncio.sleep(latency)
    return {"latency_s": latency, "result": "ok"}