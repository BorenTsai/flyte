#!/bin/bash
# Quick rebuild and redeploy script
# Use this after initial setup with deploy.sh

set -e

# Configuration
REPO_NAME="flyte-ray-lifecycle"
REGION="${AWS_REGION:-us-west-2}"
PROJECT="${FLYTE_PROJECT:-flytesnacks}"
DOMAIN="${FLYTE_DOMAIN:-development}"
VERSION="${FLYTE_VERSION:-v$(date +%s)}"  # Auto-increment with timestamp

# Get AWS account
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY="$AWS_ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"
IMAGE_NAME="$ECR_REGISTRY/$REPO_NAME:latest"

echo "🔄 Quick Deploy"
echo "==============="
echo ""

# Login to ECR
echo "→ Logging into ECR..."
aws ecr get-login-password --region "$REGION" | \
    docker login --username AWS --password-stdin "$ECR_REGISTRY" > /dev/null 2>&1

# Build and push
echo "→ Building image..."
docker build -q -t "$IMAGE_NAME" . > /dev/null

echo "→ Pushing to ECR..."
docker push "$IMAGE_NAME" 2>&1 | grep -E "(digest:|latest:)" || true

# Register
echo "→ Registering workflow (version: $VERSION)..."
pyflyte register \
    --image "$IMAGE_NAME" \
    --project "$PROJECT" \
    --domain "$DOMAIN" \
    --version "$VERSION" \
    test_ray_lifecycle.py 2>&1 | grep -E "(Successfully|registered)" || echo "Registered"

echo ""
echo "✅ Done!"
echo ""
echo "Run test with:"
echo "  flytectl create execution --project $PROJECT --domain $DOMAIN --name test_no_shutdown_workflow --version $VERSION"
echo ""
echo "Or use pyflyte:"
echo "  pyflyte run --remote --image $IMAGE_NAME test_ray_lifecycle.py test_no_shutdown_workflow"
