#!/bin/bash
# Monitor Ray Cluster Lifecycle
# This script watches Ray resources in real-time to observe cluster lifecycle

set -e

NAMESPACE="${FLYTE_NAMESPACE:-flyte}"
WATCH_INTERVAL="${WATCH_INTERVAL:-2}"

echo "============================================================"
echo "Ray Cluster Lifecycle Monitor"
echo "============================================================"
echo "Namespace: $NAMESPACE"
echo "Watching: RayJobs, RayClusters, Pods"
echo "Press Ctrl+C to stop"
echo "============================================================"
echo ""

# Function to display timestamp
timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Function to get Ray resources with detailed info
get_ray_resources() {
    local ts=$(timestamp)

    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "[$ts] Current State"
    echo "═══════════════════════════════════════════════════════════"

    # RayJobs
    echo ""
    echo "RayJobs:"
    echo "--------"
    kubectl get rayjobs -n "$NAMESPACE" 2>/dev/null || echo "  No RayJobs found"

    # RayClusters
    echo ""
    echo "RayClusters:"
    echo "------------"
    kubectl get rayclusters -n "$NAMESPACE" 2>/dev/null || echo "  No RayClusters found"

    # Pods (Ray-related)
    echo ""
    echo "Ray Pods:"
    echo "---------"
    kubectl get pods -n "$NAMESPACE" -l ray.io/cluster 2>/dev/null || echo "  No Ray pods found"

    # Get detailed status of RayJobs
    echo ""
    echo "RayJob Status Details:"
    echo "----------------------"
    kubectl get rayjobs -n "$NAMESPACE" -o custom-columns=\
NAME:.metadata.name,\
STATUS:.status.jobDeploymentStatus,\
SHUTDOWN:.spec.shutdownAfterJobFinishes,\
TTL:.spec.ttlSecondsAfterFinished,\
AGE:.metadata.creationTimestamp 2>/dev/null || echo "  No RayJobs found"
}

# Function to watch continuously
watch_resources() {
    while true; do
        clear
        get_ray_resources
        sleep "$WATCH_INTERVAL"
    done
}

# Function to show one-time snapshot
show_snapshot() {
    get_ray_resources

    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "Additional Commands:"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    echo "Watch continuously:"
    echo "  $0 watch"
    echo ""
    echo "Get RayJob YAML:"
    echo "  kubectl get rayjob <name> -n $NAMESPACE -o yaml"
    echo ""
    echo "Get RayJob logs:"
    echo "  kubectl logs -n $NAMESPACE -l ray.io/cluster=<cluster-name>"
    echo ""
    echo "Delete RayJob manually:"
    echo "  kubectl delete rayjob <name> -n $NAMESPACE"
    echo ""
    echo "Describe RayJob:"
    echo "  kubectl describe rayjob <name> -n $NAMESPACE"
    echo ""
}

# Function to show detailed info about a specific RayJob
show_rayjob_details() {
    local rayjob_name="$1"

    if [ -z "$rayjob_name" ]; then
        echo "Usage: $0 details <rayjob-name>"
        exit 1
    fi

    echo "═══════════════════════════════════════════════════════════"
    echo "RayJob Details: $rayjob_name"
    echo "═══════════════════════════════════════════════════════════"

    kubectl get rayjob "$rayjob_name" -n "$NAMESPACE" -o yaml

    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "RayJob Events:"
    echo "═══════════════════════════════════════════════════════════"
    kubectl describe rayjob "$rayjob_name" -n "$NAMESPACE" | grep -A 20 "Events:"

    # Get associated RayCluster
    local cluster_name=$(kubectl get rayjob "$rayjob_name" -n "$NAMESPACE" -o jsonpath='{.status.rayClusterName}' 2>/dev/null)

    if [ -n "$cluster_name" ]; then
        echo ""
        echo "═══════════════════════════════════════════════════════════"
        echo "Associated RayCluster: $cluster_name"
        echo "═══════════════════════════════════════════════════════════"
        kubectl get raycluster "$cluster_name" -n "$NAMESPACE"

        echo ""
        echo "Ray Pods:"
        kubectl get pods -n "$NAMESPACE" -l ray.io/cluster="$cluster_name"
    fi
}

# Function to tail logs from Ray pods
tail_logs() {
    local rayjob_name="$1"

    if [ -z "$rayjob_name" ]; then
        echo "Usage: $0 logs <rayjob-name>"
        exit 1
    fi

    local cluster_name=$(kubectl get rayjob "$rayjob_name" -n "$NAMESPACE" -o jsonpath='{.status.rayClusterName}' 2>/dev/null)

    if [ -z "$cluster_name" ]; then
        echo "Error: Could not find RayCluster for RayJob $rayjob_name"
        exit 1
    fi

    echo "Tailing logs for RayJob: $rayjob_name (Cluster: $cluster_name)"
    echo "Press Ctrl+C to stop"
    echo ""

    kubectl logs -n "$NAMESPACE" -l ray.io/cluster="$cluster_name" -f --all-containers=true
}

# Main script logic
case "${1:-snapshot}" in
    watch)
        watch_resources
        ;;
    details)
        show_rayjob_details "$2"
        ;;
    logs)
        tail_logs "$2"
        ;;
    snapshot|*)
        show_snapshot
        ;;
esac
