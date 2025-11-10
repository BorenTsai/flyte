# Deploying to Your EKS Cluster

This guide helps you deploy and run the Ray lifecycle test on your actual EKS cluster with Flyte.

## What You Have
- ✅ EKS cluster
- ✅ Flyte installed via Helm
- ❌ No container registry
- ❌ No database (?)

## What You Need

To run workflows on Flyte, you need:

1. **Container Registry** - To store your workflow container images
2. **Container Image** - Built from your workflow code
3. **Flyte Registration** - Register workflow to the cluster
4. **Execution** - Run the workflow on the cluster

## Step 1: Set Up Container Registry

### Option A: AWS ECR (Recommended for EKS)

```bash
# Check if you have AWS CLI access
aws sts get-caller-identity

# Create ECR repository
aws ecr create-repository \
  --repository-name flyte-ray-lifecycle \
  --region us-west-2  # Change to your region

# Get the registry URL
export ECR_REGISTRY=$(aws ecr describe-repositories \
  --repository-names flyte-ray-lifecycle \
  --region us-west-2 \
  --query 'repositories[0].repositoryUri' \
  --output text | cut -d'/' -f1)

echo "Your registry: $ECR_REGISTRY"

# Login to ECR
aws ecr get-login-password --region us-west-2 | \
  docker login --username AWS --password-stdin $ECR_REGISTRY

# Set your image name
export IMAGE_NAME="$ECR_REGISTRY/flyte-ray-lifecycle:latest"
```

### Option B: Docker Hub (Free, Public)

```bash
# Login to Docker Hub
docker login

# Set your image name (replace with your username)
export IMAGE_NAME="your-dockerhub-username/flyte-ray-lifecycle:latest"
```

### Option C: GitHub Container Registry (Free)

```bash
# Create personal access token at: https://github.com/settings/tokens
# Needs: write:packages permission

export GITHUB_USERNAME="your-github-username"
export GITHUB_TOKEN="ghp_your_token_here"

echo $GITHUB_TOKEN | docker login ghcr.io -u $GITHUB_USERNAME --password-stdin

export IMAGE_NAME="ghcr.io/$GITHUB_USERNAME/flyte-ray-lifecycle:latest"
```

## Step 2: Build and Push Container Image

```bash
cd ~/Projects/ml_infra/flyte/ray-lifecycle-test

# Build the image
docker build -t $IMAGE_NAME .

# Push to registry
docker push $IMAGE_NAME

# Verify
echo "Image pushed: $IMAGE_NAME"
```

## Step 3: Configure Flyte to Use Your Registry

If using ECR, ensure your EKS nodes can pull from ECR:

```bash
# Check if nodes have ECR access (should have AmazonEC2ContainerRegistryReadOnly policy)
aws eks describe-nodegroup \
  --cluster-name your-cluster-name \
  --nodegroup-name your-nodegroup-name

# If not, add the policy to the node IAM role
aws iam attach-role-policy \
  --role-name your-node-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
```

## Step 4: Register Workflow to Flyte

### Option A: Using pyflyte (Simple)

```bash
# Check connection to your cluster
kubectl config current-context
kubectl get pods -n flyte

# Register the workflow
pyflyte register \
  --image $IMAGE_NAME \
  --project flytesnacks \
  --domain development \
  --version v1 \
  test_ray_lifecycle.py

# If you have flytectl installed:
flytectl config init  # Set up connection to your cluster
```

### Option B: Using flytectl (More Control)

```bash
# Create a serialized workflow package
pyflyte package \
  --image $IMAGE_NAME \
  --output /tmp/ray-lifecycle.tar.gz

# Register to cluster
flytectl register files \
  --project flytesnacks \
  --domain development \
  --archive /tmp/ray-lifecycle.tar.gz \
  --version v1
```

## Step 5: Run the Test on Your Cluster

### Using flytectl (Recommended)

```bash
# Create execution
flytectl create execution \
  --project flytesnacks \
  --domain development \
  --name test_no_shutdown_workflow \
  --version v1

# Watch execution
flytectl get execution <execution-id> \
  --project flytesnacks \
  --domain development

# Get execution logs
flytectl get execution <execution-id> \
  --project flytesnacks \
  --domain development \
  --details
```

### Using kubectl (Direct Monitoring)

In a separate terminal, monitor the resources:

```bash
# Watch Ray resources being created
watch -n 2 'kubectl get rayjobs,rayclusters,pods -n flyte'

# Or use our monitoring script
./monitor_cluster.sh watch
```

## Step 6: Observe the Lifecycle

Once the workflow runs on your cluster, you'll see:

```bash
# Before task starts
$ kubectl get rayjobs,rayclusters,pods -n flyte
# (empty)

# During execution
$ kubectl get rayjobs,rayclusters,pods -n flyte
NAME                                     AGE
rayjob.ray.io/f-default-development-...  30s

NAME                                        AGE
raycluster.ray.io/f-default-development-... 25s

NAME                                                    READY   STATUS
pod/f-default-development-...-head-xxxxx                1/1     Running
pod/f-default-development-...-worker-0-xxxxx            1/1     Running
pod/f-default-development-...-worker-1-xxxxx            1/1     Running
pod/f-default-development-...-submitter-xxxxx           1/1     Running

# After task completes (shutdown_after_job_finishes=False)
$ kubectl get rayjobs,rayclusters,pods -n flyte
NAME                                     STATUS      AGE
rayjob.ray.io/f-default-development-...  Complete    5m

NAME                                        AGE
raycluster.ray.io/f-default-development-... 5m       ← STILL EXISTS!

NAME                                                    READY   STATUS
pod/f-default-development-...-head-xxxxx                1/1     Running  ← RUNNING!
pod/f-default-development-...-worker-0-xxxxx            1/1     Running  ← RUNNING!
pod/f-default-development-...-worker-1-xxxxx            1/1     Running  ← RUNNING!
pod/f-default-development-...-submitter-xxxxx           0/1     Completed

# Manual cleanup required
$ kubectl delete rayjob f-default-development-... -n flyte
```

## Troubleshooting

### "Cannot pull image"

**Problem:** Cluster can't pull from your registry.

**For ECR:**
```bash
# Ensure nodes have ECR access
aws iam attach-role-policy \
  --role-name <your-node-role> \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
```

**For private Docker Hub:**
```bash
# Create image pull secret
kubectl create secret docker-registry regcred \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username=<username> \
  --docker-password=<password> \
  --docker-email=<email> \
  -n flyte

# Add to Flyte config to use this secret
```

### "Workflow not found"

**Problem:** Registration didn't work.

**Solution:**
```bash
# Check registered workflows
flytectl get workflow \
  --project flytesnacks \
  --domain development

# Re-register with verbose output
pyflyte register --verbose \
  --image $IMAGE_NAME \
  --project flytesnacks \
  --domain development \
  --version v2 \
  test_ray_lifecycle.py
```

### "No database" Issue

If Flyte complains about missing database, you'll need to set one up:

```bash
# Check Flyte config
kubectl get configmap flyte-admin-config -n flyte -o yaml

# If no database is configured, you need to add one
# Option 1: Use PostgreSQL in the cluster
helm install flyte-db bitnami/postgresql \
  --namespace flyte \
  --set auth.username=flyte \
  --set auth.password=flyte \
  --set auth.database=flyte

# Update Flyte config to use this database
```

### KubeRay Operator Not Installed

```bash
# Check if KubeRay is installed
kubectl get pods -n ray-system

# If not, install it
helm repo add kuberay https://ray-project.github.io/kuberay-helm/
helm install kuberay-operator kuberay/kuberay-operator \
  --namespace ray-system \
  --create-namespace \
  --version 1.1.0
```

## Alternative: Test Locally First

If cluster deployment is too complex right now, test locally:

```bash
# Run locally (won't show KubeRay behavior, but validates the code)
pyflyte run test_ray_lifecycle.py test_no_shutdown_workflow

# This runs on your laptop, not on the cluster
# But it verifies the Ray code works
```

## Summary of What Happens

**Local Execution (`pyflyte run`):**
- ❌ Runs on your laptop
- ❌ Starts a local Ray instance
- ❌ Does NOT use KubeRay operator
- ✅ Good for testing code logic

**Cluster Execution (register + execute):**
- ✅ Runs on EKS cluster
- ✅ Uses KubeRay operator
- ✅ Creates actual Ray clusters
- ✅ Tests the lifecycle behavior we want

## Next Steps

1. **Choose a registry** (ECR recommended for EKS)
2. **Build and push** the container image
3. **Register** the workflow to your cluster
4. **Execute** and monitor with `./monitor_cluster.sh watch`
5. **Observe** the cluster lifecycle behavior

Let me know which registry option you want to use and I can help you through the specific steps!
