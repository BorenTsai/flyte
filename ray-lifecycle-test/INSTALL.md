# Installation Guide

## Prerequisites

1. **Python 3.8+**
2. **kubectl** configured to access your Kubernetes cluster
3. **Flyte** installed on your cluster
4. **KubeRay operator** installed

## Step 1: Install Python Dependencies

### Option A: Install just what you need
```bash
pip install flytekit>=1.10.0
pip install flytekitplugins-ray>=1.10.0
```

### Option B: Install from requirements.txt
```bash
pip install -r requirements.txt
```

### Option C: Verify installation
```bash
python -c "from flytekitplugins.ray import RayJobConfig; print('Ray plugin installed!')"
```

## Step 2: Test Your Setup (No Ray Required)

Before testing Ray, verify your basic Flyte setup works:

```bash
# Test with a simple workflow (no Ray)
pyflyte run test_simple.py simple_workflow
```

Expected output:
```
Starting simple task with message: Hello from Flyte!
Task completed!
Result: Completed: Hello from Flyte!
```

If this works, you're ready for Ray tests!

## Step 3: Verify Kubernetes Setup

```bash
# Check Flyte is running
kubectl get pods -n flyte

# Check KubeRay operator is installed
kubectl get pods -n ray-system

# If KubeRay is not installed, install it:
helm repo add kuberay https://ray-project.github.io/kuberay-helm/
helm repo update
helm install kuberay-operator kuberay/kuberay-operator \
  --namespace ray-system \
  --create-namespace \
  --version 1.1.0
```

## Step 4: Run Ray Tests

Now you're ready to run the Ray lifecycle tests:

```bash
# Terminal 1: Monitor
./monitor_cluster.sh watch

# Terminal 2: Run test
pyflyte run test_ray_lifecycle.py test_no_shutdown_workflow
```

## Troubleshooting

### "No module named 'flytekitplugins'"

**Problem:** The Ray plugin is not installed.

**Solution:**
```bash
pip install flytekitplugins-ray
```

### "command not found: pyflyte"

**Problem:** flytekit is not installed or not in PATH.

**Solution:**
```bash
pip install flytekit
# OR
python -m flytekit pyflyte run ...
```

### "No module named 'ray'"

**Problem:** Ray itself is not installed.

**Solution:**
```bash
pip install ray[default]
```

Note: Ray will be installed in the container images used by the Ray cluster, but you also need it locally for the SDK.

### KubeRay operator not found

**Problem:** KubeRay operator is not installed on your cluster.

**Solution:** Install the KubeRay operator:
```bash
helm repo add kuberay https://ray-project.github.io/kuberay-helm/
helm install kuberay-operator kuberay/kuberay-operator \
  --namespace ray-system \
  --create-namespace
```

### Permission denied: ./monitor_cluster.sh

**Problem:** Script is not executable.

**Solution:**
```bash
chmod +x monitor_cluster.sh
```

### Ray plugin not enabled in Flyte

**Problem:** Flyte is not configured to use the Ray plugin.

**Solution:** Add to Flyte configuration:
```yaml
plugins:
  tasks:
    task-plugins:
      enabled-plugins:
        - container
        - ray
      default-for-task-types:
        container: container
        ray: ray
```

## Verifying Everything Works

Run this checklist:

```bash
# 1. Python packages
python -c "import flytekit; print(f'flytekit {flytekit.__version__}')"
python -c "from flytekitplugins.ray import RayJobConfig; print('Ray plugin OK')"

# 2. kubectl access
kubectl get nodes

# 3. Flyte running
kubectl get pods -n flyte

# 4. KubeRay running
kubectl get pods -n ray-system

# 5. Simple test
pyflyte run test_simple.py simple_workflow

# 6. Monitor script
./monitor_cluster.sh snapshot
```

If all of the above work, you're ready to run the Ray lifecycle tests!

## Quick Install Script

Copy and paste this for a quick setup:

```bash
# Install Python dependencies
pip install flytekit flytekitplugins-ray ray[default]

# Make scripts executable
chmod +x monitor_cluster.sh

# Test basic setup
pyflyte run test_simple.py simple_workflow

# Install KubeRay if needed
helm repo add kuberay https://ray-project.github.io/kuberay-helm/ 2>/dev/null || true
helm install kuberay-operator kuberay/kuberay-operator \
  --namespace ray-system \
  --create-namespace \
  --version 1.1.0 2>/dev/null || echo "KubeRay already installed"

# Verify
echo "Setup complete! Run:"
echo "  ./monitor_cluster.sh watch    # In terminal 1"
echo "  pyflyte run test_ray_lifecycle.py test_no_shutdown_workflow  # In terminal 2"
```

## Next Steps

Once installed, see:
- **QUICKSTART.md** - Run your first test in 5 minutes
- **README.md** - Full documentation
- **TIMELINE.md** - Visual explanation of what happens
