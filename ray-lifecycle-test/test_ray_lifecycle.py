"""
Test Ray Cluster Lifecycle with shutdown_after_job_finishes

This test demonstrates:
1. Ray cluster creation by KubeRay operator
2. Task execution and completion
3. Cluster persistence when shutdown_after_job_finishes=False
4. Cluster cleanup when shutdown_after_job_finishes=True (for comparison)
"""

from datetime import timedelta
from flytekit import task, workflow, Resources
from flytekitplugins.ray import RayJobConfig, WorkerNodeConfig

# ==============================================================================
# TEST 1: Cluster stays alive after job completion
# ==============================================================================

@task(
    task_config=RayJobConfig(
        worker_node_config=[
            WorkerNodeConfig(
                group_name="test-workers",
                replicas=2,
            )
        ],
        # KEY SETTING: Do not shutdown cluster after job finishes
        shutdown_after_job_finishes=False,
        ttl_seconds_after_finished=3600,  # Ignored when shutdown=False
    ),
    requests=Resources(cpu="1", mem="2Gi"),
    limits=Resources(cpu="1", mem="2Gi"),
    timeout=timedelta(minutes=5),
)
def ray_task_no_shutdown() -> str:
    """
    A simple Ray task that completes quickly.
    The cluster should REMAIN RUNNING after this completes.
    """
    import ray
    import time
    from datetime import datetime

    # Initialize Ray (connects to cluster created by KubeRay)
    ray.init(address="auto")

    print(f"[{datetime.now()}] Ray cluster initialized")
    print(f"Available resources: {ray.cluster_resources()}")

    @ray.remote
    def simple_task(task_id: int) -> str:
        time.sleep(2)  # Simulate some work
        return f"Task {task_id} completed at {datetime.now()}"

    # Run some simple tasks
    print(f"[{datetime.now()}] Starting Ray tasks...")
    results = ray.get([simple_task.remote(i) for i in range(5)])

    for result in results:
        print(result)

    print(f"[{datetime.now()}] All Ray tasks completed")
    print("=" * 80)
    print("IMPORTANT: Task is complete, but cluster should STAY ALIVE")
    print("Check with: kubectl get rayjobs,rayclusters,pods -n flyte")
    print("=" * 80)

    ray.shutdown()
    return "Task completed - cluster should still be running!"


# ==============================================================================
# TEST 2: Cluster is cleaned up after job completion (for comparison)
# ==============================================================================

@task(
    task_config=RayJobConfig(
        worker_node_config=[
            WorkerNodeConfig(
                group_name="test-workers",
                replicas=2,
            )
        ],
        # KEY SETTING: Shutdown cluster after job finishes
        shutdown_after_job_finishes=True,
        ttl_seconds_after_finished=60,  # Wait 60 seconds before cleanup
    ),
    requests=Resources(cpu="1", mem="2Gi"),
    limits=Resources(cpu="1", mem="2Gi"),
    timeout=timedelta(minutes=5),
)
def ray_task_with_shutdown() -> str:
    """
    A simple Ray task that completes quickly.
    The cluster should be DELETED 60 seconds after this completes.
    """
    import ray
    import time
    from datetime import datetime

    ray.init(address="auto")

    print(f"[{datetime.now()}] Ray cluster initialized")
    print(f"Available resources: {ray.cluster_resources()}")

    @ray.remote
    def simple_task(task_id: int) -> str:
        time.sleep(2)
        return f"Task {task_id} completed at {datetime.now()}"

    print(f"[{datetime.now()}] Starting Ray tasks...")
    results = ray.get([simple_task.remote(i) for i in range(5)])

    for result in results:
        print(result)

    print(f"[{datetime.now()}] All Ray tasks completed")
    print("=" * 80)
    print("IMPORTANT: Cluster will be DELETED in 60 seconds")
    print("Watch with: kubectl get rayjobs,rayclusters,pods -n flyte -w")
    print("=" * 80)

    ray.shutdown()
    return "Task completed - cluster will be deleted in 60 seconds!"


# ==============================================================================
# WORKFLOWS
# ==============================================================================

@workflow
def test_no_shutdown_workflow() -> str:
    """
    Test workflow: Ray cluster should persist after completion.

    Steps to observe:
    1. Run this workflow
    2. Watch cluster with: kubectl get rayjobs,rayclusters,pods -n flyte -w
    3. After task completes, verify cluster is still running
    4. Manually delete with: kubectl delete rayjob <name> -n flyte
    """
    return ray_task_no_shutdown()


@workflow
def test_with_shutdown_workflow() -> str:
    """
    Test workflow: Ray cluster should be deleted 60s after completion.

    Steps to observe:
    1. Run this workflow
    2. Watch cluster with: kubectl get rayjobs,rayclusters,pods -n flyte -w
    3. After task completes, wait 60 seconds
    4. Verify cluster is deleted automatically
    """
    return ray_task_with_shutdown()


@workflow
def test_both_scenarios() -> tuple[str, str]:
    """
    Run both tests sequentially to compare behavior.

    WARNING: This will create two separate Ray clusters!
    """
    result1 = ray_task_no_shutdown()
    result2 = ray_task_with_shutdown()
    return result1, result2


if __name__ == "__main__":
    # For local testing
    print("Ray Lifecycle Tests")
    print("=" * 80)
    print("Use pyflyte to run these workflows:")
    print()
    print("Test 1 (no shutdown):")
    print("  pyflyte run test_ray_lifecycle.py test_no_shutdown_workflow")
    print()
    print("Test 2 (with shutdown):")
    print("  pyflyte run test_ray_lifecycle.py test_with_shutdown_workflow")
    print()
    print("Test both:")
    print("  pyflyte run test_ray_lifecycle.py test_both_scenarios")
    print("=" * 80)
