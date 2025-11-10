# Ray Cluster Lifecycle Test

This test demonstrates how the Ray cluster lifecycle works with different `shutdown_after_job_finishes` settings.

## What This Test Demonstrates

1. **Ray cluster creation** - KubeRay operator provisions head/worker/submitter pods
2. **Task execution** - Flyte submits a Ray job to the cluster
3. **Cluster persistence** - With `shutdown_after_job_finishes=False`, cluster stays alive
4. **Cluster cleanup** - With `shutdown_after_job_finishes=True`, cluster is deleted after TTL

## Prerequisites

1. **Kubernetes cluster** with:
   - Flyte installed
   - KubeRay operator installed
   - Ray plugin enabled in Flyte

2. **kubectl** configured to access your cluster

3. **Python environment** with:
   ```bash
   pip install flytekit flytekitplugins-ray
   ```

## Test Setup

### Install KubeRay Operator (if not already installed)

```bash
helm repo add kuberay https://ray-project.github.io/kuberay-helm/
helm repo update

helm install kuberay-operator kuberay/kuberay-operator \
  --namespace ray-system \
  --create-namespace \
  --version 1.1.0
```

### Enable Ray Plugin in Flyte

Add to your Flyte configuration:

```yaml
tasks:
  task-plugins:
    enabled-plugins:
      - container
      - sidecar
      - k8s-array
      - ray
    default-for-task-types:
      container: container
      sidecar: sidecar
      container_array: k8s-array
      ray: ray

plugins:
  ray:
    shutdownAfterJobFinishes: true  # Default behavior
    ttlSecondsAfterFinished: 3600   # Default TTL (1 hour)
```

## Running The Tests

### Test 1: Cluster Persists After Completion

This test uses `shutdown_after_job_finishes=False` to keep the cluster alive.

**Terminal 1: Start monitoring**
```bash
./monitor_cluster.sh watch
```

**Terminal 2: Run the workflow**
```bash
# Local execution (for testing)
pyflyte run test_ray_lifecycle.py test_no_shutdown_workflow

# OR register and run on Flyte cluster
flytectl register files test_ray_lifecycle.py -p flytesnacks -d development -v v1
flytectl create execution -p flytesnacks -d development \
  --workflow flyte.workflows.test_no_shutdown_workflow \
  --version v1
```

**Expected Behavior:**

1. **Before task starts:**
   ```
   RayJobs:        (empty)
   RayClusters:    (empty)
   Ray Pods:       (empty)
   ```

2. **During task execution:**
   ```
   RayJobs:        rayjob-xxx (Status: Running)
   RayClusters:    raycluster-yyy
   Ray Pods:
     - rayjob-xxx-raycluster-yyy-head-xxxxx       (Running)
     - rayjob-xxx-raycluster-yyy-worker-0-xxxxx   (Running)
     - rayjob-xxx-raycluster-yyy-worker-1-xxxxx   (Running)
     - rayjob-xxx-submitter-xxxxx                 (Running)
   ```

3. **After task completes (KEY OBSERVATION):**
   ```
   RayJobs:        rayjob-xxx (Status: Complete)
   RayClusters:    raycluster-yyy (STILL EXISTS!)
   Ray Pods:
     - rayjob-xxx-raycluster-yyy-head-xxxxx       (STILL Running!)
     - rayjob-xxx-raycluster-yyy-worker-0-xxxxx   (STILL Running!)
     - rayjob-xxx-raycluster-yyy-worker-1-xxxxx   (STILL Running!)
     - rayjob-xxx-submitter-xxxxx                 (Completed)
   ```

4. **Verify the cluster is running:**
   ```bash
   # Get RayJob details
   kubectl get rayjobs -n flyte

   # Check shutdown setting
   kubectl get rayjob <name> -n flyte -o jsonpath='{.spec.shutdownAfterJobFinishes}'
   # Should output: false

   # Check TTL (should be ignored)
   kubectl get rayjob <name> -n flyte -o jsonpath='{.spec.ttlSecondsAfterFinished}'
   # Should output: 3600

   # Cluster should still be healthy
   kubectl get rayclusters -n flyte
   kubectl get pods -n flyte -l ray.io/cluster
   ```

5. **Manual cleanup required:**
   ```bash
   # The cluster will NOT be automatically deleted
   # You must delete it manually:
   kubectl delete rayjob <name> -n flyte

   # This will cascade delete:
   # - RayCluster
   # - Head pod
   # - Worker pods
   # - Submitter pod (if still exists)
   ```

### Test 2: Cluster Auto-Deletes After Completion

This test uses `shutdown_after_job_finishes=True` with `ttl_seconds_after_finished=60`.

**Terminal 1: Start monitoring**
```bash
./monitor_cluster.sh watch
```

**Terminal 2: Run the workflow**
```bash
pyflyte run test_ray_lifecycle.py test_with_shutdown_workflow
```

**Expected Behavior:**

1. **During execution:** Same as Test 1

2. **After task completes:**
   ```
   RayJobs:        rayjob-xxx (Status: Complete)
   RayClusters:    raycluster-yyy (EXISTS, but marked for deletion)
   Ray Pods:       (All still running)
   ```

3. **60 seconds after completion (KEY OBSERVATION):**
   ```
   RayJobs:        rayjob-xxx (may still exist)
   RayClusters:    (DELETED by KubeRay!)
   Ray Pods:
     - rayjob-xxx-raycluster-yyy-head-xxxxx       (Terminating)
     - rayjob-xxx-raycluster-yyy-worker-0-xxxxx   (Terminating)
     - rayjob-xxx-raycluster-yyy-worker-1-xxxxx   (Terminating)
   ```

4. **Shortly after:**
   ```
   RayJobs:        rayjob-xxx (may persist for logs)
   RayClusters:    (GONE)
   Ray Pods:       (ALL GONE)
   ```

5. **Verify automatic cleanup:**
   ```bash
   # Watch the countdown
   watch -n 1 'kubectl get rayclusters,pods -n flyte -l ray.io/cluster'

   # After 60 seconds, everything should be gone
   ```

## Detailed Monitoring

### Get snapshot of current state
```bash
./monitor_cluster.sh snapshot
```

### Watch in real-time
```bash
./monitor_cluster.sh watch
```

### Get detailed info about a specific RayJob
```bash
./monitor_cluster.sh details <rayjob-name>
```

### Tail logs from Ray pods
```bash
./monitor_cluster.sh logs <rayjob-name>
```

### Manual kubectl commands
```bash
# List all Ray resources
kubectl get rayjobs,rayclusters,pods -n flyte

# Watch resources in real-time
kubectl get rayjobs,rayclusters,pods -n flyte -w

# Get RayJob YAML
kubectl get rayjob <name> -n flyte -o yaml

# Check RayJob status
kubectl get rayjob <name> -n flyte -o jsonpath='{.status.jobDeploymentStatus}'

# Check shutdown setting
kubectl get rayjob <name> -n flyte -o jsonpath='{.spec.shutdownAfterJobFinishes}'

# Check TTL setting
kubectl get rayjob <name> -n flyte -o jsonpath='{.spec.ttlSecondsAfterFinished}'

# Get RayCluster details
kubectl describe raycluster <cluster-name> -n flyte

# Get pod logs
kubectl logs -n flyte <pod-name>

# Delete RayJob manually
kubectl delete rayjob <name> -n flyte
```

## Understanding the Resource Chain

```
Flyte Task Execution
       ↓
   Creates RayJob CRD
       ↓
KubeRay Operator Detects RayJob
       ↓
   Creates RayCluster CRD
       ↓
   Creates Pods:
       ├── Head Pod (1)
       ├── Worker Pods (N replicas)
       └── Submitter Pod (1)
       ↓
Job Executes and Completes
       ↓
  shutdown_after_job_finishes?
       ↓
    ┌─────┴─────┐
    │           │
   YES         NO
    │           │
    ↓           ↓
Wait TTL   Cluster Stays
    ↓      Forever!
KubeRay Deletes
RayCluster
    ↓
Kubernetes Cascades
Delete to Pods
    ↓
Everything Gone
```

## Key Observations to Note

### When `shutdown_after_job_finishes=False`:

1. ✅ **RayJob status changes to "Complete"** but RayJob resource persists
2. ✅ **RayCluster continues running** indefinitely
3. ✅ **Head and worker pods keep running** - they don't terminate
4. ✅ **Resources are NOT freed** - pods continue consuming CPU/memory
5. ✅ **Manual deletion required** - you must `kubectl delete rayjob`
6. ⚠️ **TTL is ignored** - the `ttlSecondsAfterFinished` setting has no effect
7. 💰 **Cost implications** - cluster keeps running and billing continues

### When `shutdown_after_job_finishes=True`:

1. ✅ **TTL countdown starts** when job completes
2. ✅ **After TTL expires, KubeRay deletes RayCluster**
3. ✅ **Pods are terminated** via cascade deletion
4. ✅ **Resources are freed** automatically
5. ⏱️ **There's a grace period** - cluster remains available during TTL for debugging

## Troubleshooting

### RayJob not appearing
```bash
# Check if Ray plugin is enabled
kubectl logs -n flyte deployment/flytepropeller | grep ray

# Check Flyte configuration
kubectl get configmap flyte-propeller-config -n flyte -o yaml | grep -A 10 ray
```

### KubeRay operator not creating resources
```bash
# Check operator logs
kubectl logs -n ray-system deployment/kuberay-operator

# Verify operator is running
kubectl get pods -n ray-system
```

### Cluster not deleting after TTL
```bash
# Check RayJob status
kubectl describe rayjob <name> -n flyte

# Check KubeRay operator logs
kubectl logs -n ray-system deployment/kuberay-operator | grep <rayjob-name>

# Verify TTL and shutdown settings
kubectl get rayjob <name> -n flyte -o yaml | grep -A 2 shutdown
```

## Cleanup

### Delete specific RayJob
```bash
kubectl delete rayjob <name> -n flyte
```

### Delete all RayJobs
```bash
kubectl delete rayjobs --all -n flyte
```

### Force delete stuck resources
```bash
# Remove finalizers if stuck
kubectl patch rayjob <name> -n flyte -p '{"metadata":{"finalizers":[]}}' --type=merge
kubectl delete rayjob <name> -n flyte --force --grace-period=0
```

## Advanced: Testing with Flyte's Finalize

To test Flyte's cleanup behavior (when workflow execution ends):

```bash
# 1. Start a workflow with shutdown_after_job_finishes=False
pyflyte run test_ray_lifecycle.py test_no_shutdown_workflow

# 2. Monitor the RayJob
./monitor_cluster.sh watch

# 3. Simulate workflow completion by marking execution as complete in Flyte
# (This triggers Flyte's Finalize() method)

# 4. Observe if Flyte deletes the RayJob based on DeleteResourceOnFinalize setting
# Check Flyte config:
kubectl get configmap flyte-propeller-config -n flyte -o yaml | grep deleteResourceOnFinalize
```

## Expected Test Results Summary

| Setting | Task Completes | After TTL | Manual Delete |
|---------|---------------|-----------|---------------|
| `shutdown=false` | Cluster stays up | Cluster stays up | Required |
| `shutdown=true, ttl=60` | Cluster stays up | Cluster deleted | Not needed |
| `shutdown=true, ttl=0` | Cluster deleted immediately | N/A | Not needed |

## Next Steps

After running these tests, you should:

1. ✅ Understand when clusters persist vs auto-delete
2. ✅ Know how to monitor cluster lifecycle
3. ✅ Be aware of cost implications
4. ✅ Have confidence in production cluster management

For production use:
- Consider using `shutdown_after_job_finishes=true` with reasonable TTL
- Set up monitoring for orphaned clusters
- Implement cleanup policies for development environments
- Use Flyte's `DeleteResourceOnFinalize` for additional safety
