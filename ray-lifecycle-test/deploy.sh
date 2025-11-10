#!/bin/bash
# Automated deployment script for Ray Lifecycle Test to EKS
# This script will help you deploy the test to your EKS cluster

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Configuration
REPO_NAME="flyte-ray-lifecycle"
REGION="${AWS_REGION:-us-west-2}"
PROJECT="${FLYTE_PROJECT:-flytesnacks}"
DOMAIN="${FLYTE_DOMAIN:-development}"
VERSION="${FLYTE_VERSION:-v1}"

print_header "Ray Lifecycle Test - EKS Deployment"

echo "This script will:"
echo "  1. Check prerequisites"
echo "  2. Set up AWS ECR repository"
echo "  3. Build and push Docker image"
echo "  4. Register workflow to Flyte"
echo "  5. Execute the test"
echo ""

# Step 1: Check prerequisites
print_header "Step 1: Checking Prerequisites"

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    print_error "AWS CLI not found. Please install it first."
    exit 1
fi
print_success "AWS CLI installed"

# Check Docker
if ! command -v docker &> /dev/null; then
    print_error "Docker not found. Please install it first."
    exit 1
fi
print_success "Docker installed"

# Check Docker daemon
if ! docker info &> /dev/null; then
    print_error "Docker daemon not running. Please start Docker."
    exit 1
fi
print_success "Docker daemon running"

# Check kubectl
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl not found. Please install it first."
    exit 1
fi
print_success "kubectl installed"

# Check kubectl connection
if ! kubectl get nodes &> /dev/null; then
    print_error "Cannot connect to Kubernetes cluster. Check your kubeconfig."
    exit 1
fi
print_success "kubectl connected to cluster"

# Check Flyte namespace
if ! kubectl get namespace flyte &> /dev/null; then
    print_error "Flyte namespace not found. Is Flyte installed?"
    exit 1
fi
print_success "Flyte namespace exists"

# Check KubeRay operator
if ! kubectl get deployment -n ray-system kuberay-operator &> /dev/null 2>&1; then
    print_warning "KubeRay operator not found in ray-system namespace"
    echo ""
    echo "Would you like to install KubeRay operator now? (y/n)"
    read -r install_kuberay
    if [[ "$install_kuberay" == "y" ]]; then
        print_info "Installing KubeRay operator..."
        helm repo add kuberay https://ray-project.github.io/kuberay-helm/
        helm repo update
        helm install kuberay-operator kuberay/kuberay-operator \
            --namespace ray-system \
            --create-namespace \
            --version 1.1.0
        print_success "KubeRay operator installed"
    else
        print_error "KubeRay operator is required. Exiting."
        exit 1
    fi
else
    print_success "KubeRay operator found"
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    print_error "AWS credentials not configured. Run 'aws configure' first."
    exit 1
fi
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
print_success "AWS credentials configured (Account: $AWS_ACCOUNT_ID)"

# Step 2: Set up ECR repository
print_header "Step 2: Setting up ECR Repository"

# Check if repository exists
if aws ecr describe-repositories --repository-names "$REPO_NAME" --region "$REGION" &> /dev/null; then
    print_info "ECR repository '$REPO_NAME' already exists"
else
    print_info "Creating ECR repository '$REPO_NAME'..."
    aws ecr create-repository \
        --repository-name "$REPO_NAME" \
        --region "$REGION" \
        --image-scanning-configuration scanOnPush=true \
        --encryption-configuration encryptionType=AES256
    print_success "ECR repository created"
fi

# Get repository URI
ECR_REGISTRY="$AWS_ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"
IMAGE_NAME="$ECR_REGISTRY/$REPO_NAME:latest"

print_success "Image will be: $IMAGE_NAME"

# Step 3: Build and push Docker image
print_header "Step 3: Building and Pushing Docker Image"

# Login to ECR
print_info "Logging into ECR..."
aws ecr get-login-password --region "$REGION" | \
    docker login --username AWS --password-stdin "$ECR_REGISTRY"
print_success "Logged into ECR"

# Build image
print_info "Building Docker image..."
docker build -t "$IMAGE_NAME" .
print_success "Docker image built"

# Push image
print_info "Pushing image to ECR..."
docker push "$IMAGE_NAME"
print_success "Image pushed to ECR"

# Step 4: Ensure EKS nodes can pull from ECR
print_header "Step 4: Verifying ECR Access"

print_info "Checking if EKS nodes have ECR access..."
print_warning "If pods fail to pull images, you may need to add ECR read policy to node IAM role"
echo "    See CLUSTER_DEPLOYMENT.md for instructions on adding the policy"

# Step 5: Register workflow
print_header "Step 5: Registering Workflow to Flyte"

# Check if pyflyte is available
if ! command -v pyflyte &> /dev/null; then
    print_error "pyflyte not found. Please install flytekit first."
    exit 1
fi

print_info "Registering workflow..."
pyflyte register \
    --image "$IMAGE_NAME" \
    --project "$PROJECT" \
    --domain "$DOMAIN" \
    --version "$VERSION" \
    test_ray_lifecycle.py

print_success "Workflow registered"

# Step 6: Execute test
print_header "Step 6: Ready to Execute Test"

echo ""
print_success "Setup complete! Ready to run tests."
echo ""
echo "To run the test that keeps cluster alive:"
echo -e "${GREEN}  flytectl create execution \\"
echo "    --project $PROJECT \\"
echo "    --domain $DOMAIN \\"
echo "    --name test_no_shutdown_workflow \\"
echo -e "    --version $VERSION${NC}"
echo ""
echo "To monitor the cluster in real-time:"
echo -e "${GREEN}  ./monitor_cluster.sh watch${NC}"
echo ""
echo "Or run both tests sequentially:"
echo -e "${GREEN}  flytectl create execution \\"
echo "    --project $PROJECT \\"
echo "    --domain $DOMAIN \\"
echo "    --name test_both_scenarios \\"
echo -e "    --version $VERSION${NC}"
echo ""

# Option to execute automatically
echo "Would you like to execute the test now? (y/n)"
read -r execute_now

if [[ "$execute_now" == "y" ]]; then
    print_header "Executing Test: test_no_shutdown_workflow"

    if ! command -v flytectl &> /dev/null; then
        print_warning "flytectl not found. Using kubectl to monitor instead."
        print_info "Starting test with pyflyte..."

        # Run in background and get the execution details
        echo ""
        print_info "Running: pyflyte run --remote --image $IMAGE_NAME test_ray_lifecycle.py test_no_shutdown_workflow"
        echo ""

        # Note: This runs remotely on the cluster
        pyflyte run --remote \
            --image "$IMAGE_NAME" \
            --project "$PROJECT" \
            --domain "$DOMAIN" \
            test_ray_lifecycle.py test_no_shutdown_workflow

        echo ""
        print_success "Workflow submitted!"
        print_info "Monitor with: ./monitor_cluster.sh watch"
    else
        EXECUTION_ID=$(flytectl create execution \
            --project "$PROJECT" \
            --domain "$DOMAIN" \
            --name test_no_shutdown_workflow \
            --version "$VERSION" \
            --format json | jq -r '.id.name')

        print_success "Execution created: $EXECUTION_ID"
        print_info "Monitoring execution..."

        # Start monitoring in background
        echo ""
        print_info "Opening cluster monitor in background..."
        print_info "Run './monitor_cluster.sh watch' in another terminal for real-time updates"
        echo ""

        # Watch execution status
        flytectl get execution "$EXECUTION_ID" \
            --project "$PROJECT" \
            --domain "$DOMAIN" \
            --details
    fi
fi

print_header "Summary"
echo "Image:   $IMAGE_NAME"
echo "Project: $PROJECT"
echo "Domain:  $DOMAIN"
echo "Version: $VERSION"
echo ""
echo "Next steps:"
echo "  1. Monitor: ./monitor_cluster.sh watch"
echo "  2. View logs: ./monitor_cluster.sh logs <rayjob-name>"
echo "  3. Check cluster: kubectl get rayjobs,rayclusters,pods -n flyte"
echo ""
print_success "Deployment complete!"
