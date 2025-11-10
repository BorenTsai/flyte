# Quick Start Guide

Run this test in 5 minutes to see Ray cluster lifecycle behavior.

## Prerequisites Check

```bash
# Verify kubectl works
kubectl get nodes

# Verify Flyte is installed
kubectl get pods -n flyte

# Verify KubeRay operator is installed
kubectl get pods -n ray-system
```

## One-Command Test

### Test 1: Cluster Stays Alive (Most Important)

```bash
# Terminal 1: Watch the cluster
./monitor_cluster.sh watch

# Terminal 2: Run the test
pyflyte run test_ray_lifecycle.py test_no_shutdown_workflow
```

**What you'll see:**
1. RayJob appears
2. RayCluster created
3. 3 pods spawn (head + 2 workers)
4. Task completes (prints "Task completed")
5. **CLUSTER STAYS RUNNING** ← Key observation!
6. Manually delete: `kubectl delete rayjob <name> -n flyte`

### Test 2: Cluster Auto-Deletes

```bash
# Terminal 1: Watch the cluster
./monitor_cluster.sh watch

# Terminal 2: Run the test
pyflyte run test_ray_lifecycle.py test_with_shutdown_workflow
```

**What you'll see:**
1. Same as Test 1, steps 1-4
2. Wait 60 seconds
3. **CLUSTER DELETES AUTOMATICALLY** ← Key observation!

## Quick Reference

### Monitor Commands
```bash
# Snapshot
./monitor_cluster.sh snapshot

# Watch live
./monitor_cluster.sh watch

# Details
./monitor_cluster.sh details <rayjob-name>

# Logs
./monitor_cluster.sh logs <rayjob-name>
```

### Manual kubectl
```bash
# List everything
kubectl get rayjobs,rayclusters,pods -n flyte

# Watch live
kubectl get rayjobs,rayclusters,pods -n flyte -w

# Delete
kubectl delete rayjob <name> -n flyte
```

## Key Takeaways

| `shutdown_after_job_finishes` | Behavior |
|-------------------------------|----------|
| `False` | ⚠️ Cluster runs forever |
| `True` | ✅ Auto-deleted after TTL |

## Troubleshooting

**Nothing appears?**
```bash
# Check Flyte logs
kubectl logs -n flyte deployment/flytepropeller | grep ray

# Check KubeRay logs
kubectl logs -n ray-system deployment/kuberay-operator
```

**Stuck deleting?**
```bash
kubectl patch rayjob <name> -n flyte -p '{"metadata":{"finalizers":[]}}' --type=merge
kubectl delete rayjob <name> -n flyte --force
```

## Done!

You've now seen how Ray clusters persist or auto-delete. Check README.md for detailed explanations.
