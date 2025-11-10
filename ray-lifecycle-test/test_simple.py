"""
Simple test to verify the test structure works without Ray plugin.

This is a minimal example that can run without flytekitplugins-ray installed,
useful for testing the basic workflow structure.
"""

from datetime import timedelta
from flytekit import task, workflow

@task(timeout=timedelta(minutes=1))
def simple_task(message: str) -> str:
    """
    A simple task that doesn't require Ray.
    Use this to verify your Flyte setup works before testing Ray.
    """
    import time
    print(f"Starting simple task with message: {message}")
    time.sleep(2)
    print(f"Task completed!")
    return f"Completed: {message}"

@workflow
def simple_workflow() -> str:
    """Test workflow without Ray to verify Flyte setup."""
    return simple_task(message="Hello from Flyte!")

if __name__ == "__main__":
    print("Testing simple workflow (no Ray required)...")
    print("Run with: pyflyte run test_simple.py simple_workflow")
    result = simple_workflow()
    print(f"Result: {result}")
