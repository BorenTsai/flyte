# Ray Cluster Lifecycle Timeline

Visual timeline of what happens with different configurations.

## Scenario 1: `shutdown_after_job_finishes=False`

```
Time    Action                          RayJob      RayCluster   Pods
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
00:00   Flyte submits task              -           -            -

00:05   Flyte creates RayJob            Creating    -            -

00:10   KubeRay sees RayJob             Running     Creating     -

00:15   KubeRay creates RayCluster      Running     Running      -

00:20   KubeRay creates pods            Running     Running      Creating
        - Head pod
        - Worker pod 1
        - Worker pod 2
        - Submitter pod

00:30   All pods running                Running     Running      ●●●● Running

00:35   Submitter pod submits job       Running     Running      ●●●● Running

00:40   Ray job executes                Running     Running      ●●●● Running

00:50   Ray job completes               Running     Running      ●●●● Running

00:55   Submitter pod exits             Complete    Running      ●●● Running
                                                                  ● Complete

01:00   ⚠️ CRITICAL POINT ⚠️             Complete    Running      ●●● Running
        Task marked complete but                                 ● Complete
        CLUSTER KEEPS RUNNING!

01:30   Still running...                Complete    Running      ●●● Running
                                                                  ● Complete

02:00   Still running...                Complete    Running      ●●● Running
                                                                  ● Complete

∞       CLUSTER RUNS FOREVER            Complete    Running      ●●● Running
        until manually deleted!                                  ● Complete

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Manual deletion required:
  kubectl delete rayjob <name> -n flyte

Cost: $$$ - Cluster consumes resources indefinitely!
```

## Scenario 2: `shutdown_after_job_finishes=True, ttl_seconds_after_finished=60`

```
Time    Action                          RayJob      RayCluster   Pods
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
00:00   Flyte submits task              -           -            -

00:05   Flyte creates RayJob            Creating    -            -

00:10   KubeRay sees RayJob             Running     Creating     -

00:15   KubeRay creates RayCluster      Running     Running      -

00:20   KubeRay creates pods            Running     Running      Creating
        - Head pod
        - Worker pod 1
        - Worker pod 2
        - Submitter pod

00:30   All pods running                Running     Running      ●●●● Running

00:35   Submitter pod submits job       Running     Running      ●●●● Running

00:40   Ray job executes                Running     Running      ●●●● Running

00:50   Ray job completes               Running     Running      ●●●● Running

00:55   Submitter pod exits             Complete    Running      ●●● Running
                                                                  ● Complete

01:00   ⏱️  TTL COUNTDOWN STARTS          Complete    Running      ●●● Running
        Task complete, waiting 60s...                            ● Complete

01:15   Countdown: 45s remaining        Complete    Running      ●●● Running
                                                                  ● Complete

01:30   Countdown: 30s remaining        Complete    Running      ●●● Running
                                                                  ● Complete

01:45   Countdown: 15s remaining        Complete    Running      ●●● Running
                                                                  ● Complete

02:00   ✅ TTL EXPIRED!                  Complete    Deleting     ●●● Running
        KubeRay deletes RayCluster                               ● Complete

02:05   Pods terminating                Complete    -            ●●● Terminating
        (cascade deletion)                                       ● Complete

02:10   All cleaned up                  Complete    -            -
                                        (may persist
                                         for logs)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Automatic cleanup!
No manual intervention needed.

Cost: $ - Cluster only runs for task duration + TTL
```

## Scenario 3: `shutdown_after_job_finishes=True, ttl_seconds_after_finished=0`

```
Time    Action                          RayJob      RayCluster   Pods
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
00:00   Flyte submits task              -           -            -

[... same as Scenario 2 until ...]

00:50   Ray job completes               Running     Running      ●●●● Running

00:55   Submitter pod exits             Complete    Running      ●●● Running
                                                                  ● Complete

00:56   ⚡ IMMEDIATE DELETION!           Complete    Deleting     ●●● Running
        TTL=0, no grace period!                                  ● Complete

00:57   Pods terminating                Complete    -            ●●● Terminating
                                                                  ● Complete

01:00   All cleaned up                  Complete    -            -

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Immediate cleanup!
No time for debugging logs.

Cost: $ - Minimal runtime
Warning: May delete before logs are fully captured!
```

## Scenario 4: Flyte Workflow Completes (with `DeleteResourceOnFinalize=true`)

```
Time    Action                          RayJob      RayCluster   Pods
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[... Ray task completes as in Scenario 1 ...]

01:00   Ray task marked complete        Complete    Running      ●●● Running
        (shutdown=false, so cluster                              ● Complete
        stays up)

01:05   Flyte workflow continues        Complete    Running      ●●● Running
        with other tasks...                                      ● Complete

02:00   All workflow tasks done         Complete    Running      ●●● Running
                                                                  ● Complete

02:05   Flyte calls Finalize()          Complete    Running      ●●● Running
        on Ray task                                              ● Complete

02:06   🔧 Flyte checks config:          Complete    Running      ●●● Running
        DeleteResourceOnFinalize=true?                           ● Complete

02:07   ✅ Flyte deletes RayJob          Deleting    Running      ●●● Running
        (owner reference cleanup)                                ● Complete

02:08   RayCluster cascade deleted      -           Deleting     ●●● Running
                                                                  ● Complete

02:10   All pods terminate              -           -            ●●● Terminating
                                                                  ● Terminating

02:15   Everything cleaned up           -           -            -

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Cleanup when workflow ends!
Even if shutdown_after_job_finishes=false

This is Flyte's safety net.
```

## Legend

```
●     Running pod
○     Completed pod
⚠️     Warning/Important
✅     Success/Cleanup
⚡     Immediate action
⏱️     Timer/Countdown
🔧     Configuration check
-     Resource doesn't exist
```

## Key Insights

### Cost Comparison (for a 2-hour workflow with 1-hour tasks)

| Configuration | Cluster Runtime | Cost |
|--------------|----------------|------|
| `shutdown=false`, no Finalize | Forever! | $$$∞ |
| `shutdown=false`, with Finalize | 2 hours | $$$ |
| `shutdown=true, ttl=3600` | 1h + 1h TTL = 2h | $$ |
| `shutdown=true, ttl=300` | 1h + 5m = 1.08h | $ |
| `shutdown=true, ttl=0` | 1h + 0s = 1h | $ |

### When to Use Each Setting

**`shutdown=false`**
- ✅ Interactive development/debugging
- ✅ Running multiple jobs on same cluster
- ✅ Long-running services
- ⚠️ Must have manual cleanup process
- ⚠️ Must have monitoring for orphaned clusters

**`shutdown=true, ttl=3600` (1 hour)**
- ✅ Production jobs
- ✅ Gives time for debugging if failure occurs
- ✅ Allows log retrieval
- ✅ Automatic cleanup

**`shutdown=true, ttl=300` (5 minutes)**
- ✅ Quick jobs
- ✅ Cost-sensitive environments
- ⚠️ Less time for post-mortem debugging

**`shutdown=true, ttl=0`**
- ✅ Ephemeral jobs
- ✅ Maximum cost savings
- ⚠️ Logs may be lost
- ⚠️ No time for debugging

## Production Recommendation

```python
@task(
    task_config=RayJob(
        shutdown_after_job_finishes=True,   # ✅ Auto-cleanup
        ttl_seconds_after_finished=600,     # ✅ 10 min grace period
    ),
    # ... rest of config
)
def production_ray_task():
    pass
```

Plus configure Flyte:
```yaml
plugins:
  k8s:
    delete-resource-on-finalize: true  # ✅ Safety net
```

This gives you:
- ✅ Automatic cleanup via KubeRay (after TTL)
- ✅ Safety net via Flyte (when workflow ends)
- ✅ 10-minute grace period for debugging
- ✅ No orphaned clusters
