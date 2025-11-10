#!/bin/bash
# Check if EKS nodes have ECR access
# This helps diagnose "ImagePullBackOff" errors

set -e

REGION="${AWS_REGION:-us-west-2}"

echo "🔍 Checking EKS Node ECR Access"
echo "================================"
echo ""

# Get node IAM role
echo "→ Finding EKS node IAM role..."

# Try to get node instance profile from a node
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
echo "  Checking node: $NODE_NAME"

# Get instance ID from node
INSTANCE_ID=$(kubectl get node "$NODE_NAME" -o jsonpath='{.spec.providerID}' | cut -d'/' -f5)
echo "  Instance ID: $INSTANCE_ID"

# Get IAM instance profile
INSTANCE_PROFILE=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --region "$REGION" \
    --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn' \
    --output text | cut -d'/' -f2)

if [ -z "$INSTANCE_PROFILE" ]; then
    echo "  ❌ Could not find IAM instance profile"
    exit 1
fi

echo "  Instance Profile: $INSTANCE_PROFILE"

# Get IAM role from instance profile
IAM_ROLE=$(aws iam get-instance-profile \
    --instance-profile-name "$INSTANCE_PROFILE" \
    --query 'InstanceProfile.Roles[0].RoleName' \
    --output text)

echo "  IAM Role: $IAM_ROLE"
echo ""

# Check if ECR policy is attached
echo "→ Checking for ECR permissions..."
echo ""

ECR_POLICY="arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"

if aws iam list-attached-role-policies \
    --role-name "$IAM_ROLE" \
    --query "AttachedPolicies[?PolicyArn=='$ECR_POLICY']" \
    --output text | grep -q "$ECR_POLICY"; then
    echo "  ✅ AmazonEC2ContainerRegistryReadOnly policy is attached"
    echo ""
    echo "Your nodes should be able to pull from ECR!"
else
    echo "  ❌ AmazonEC2ContainerRegistryReadOnly policy NOT attached"
    echo ""
    echo "To fix this, run:"
    echo ""
    echo "  aws iam attach-role-policy \\"
    echo "    --role-name $IAM_ROLE \\"
    echo "    --policy-arn $ECR_POLICY"
    echo ""
    echo "Or manually attach it in the AWS Console:"
    echo "  1. Go to IAM > Roles > $IAM_ROLE"
    echo "  2. Click 'Attach policies'"
    echo "  3. Search for 'AmazonEC2ContainerRegistryReadOnly'"
    echo "  4. Check the box and click 'Attach policy'"
    echo ""
    exit 1
fi

# Test actual ECR access from a pod
echo "→ Testing ECR access from a pod..."
echo ""

# Create a test pod that tries to pull from ECR
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY="$AWS_ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"

cat <<EOF | kubectl apply -f - > /dev/null
apiVersion: v1
kind: Pod
metadata:
  name: ecr-test-pod
  namespace: default
spec:
  containers:
  - name: test
    image: $ECR_REGISTRY/flyte-ray-lifecycle:latest
    command: ['sh', '-c', 'echo "ECR access works!" && sleep 10']
  restartPolicy: Never
EOF

echo "  Created test pod: ecr-test-pod"
echo "  Waiting for pod to start..."

# Wait up to 60 seconds for pod to be ready or fail
for i in {1..60}; do
    STATUS=$(kubectl get pod ecr-test-pod -n default -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")

    if [ "$STATUS" = "Running" ] || [ "$STATUS" = "Succeeded" ]; then
        echo ""
        echo "  ✅ Pod successfully pulled image from ECR!"
        kubectl delete pod ecr-test-pod -n default > /dev/null 2>&1
        echo "  🧹 Test pod cleaned up"
        echo ""
        echo "✅ All checks passed! Your cluster can pull from ECR."
        exit 0
    elif [ "$STATUS" = "Failed" ] || kubectl get pod ecr-test-pod -n default -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}' 2>/dev/null | grep -q "ImagePullBackOff"; then
        echo ""
        echo "  ❌ Failed to pull image from ECR"
        echo ""
        echo "Pod events:"
        kubectl describe pod ecr-test-pod -n default | grep -A 5 Events:
        kubectl delete pod ecr-test-pod -n default > /dev/null 2>&1
        echo ""
        echo "This likely means:"
        echo "  1. The image doesn't exist in ECR yet (run ./deploy.sh first)"
        echo "  2. The IAM role needs the ECR policy (see command above)"
        echo "  3. The ECR repository is in a different region"
        exit 1
    fi

    sleep 1
    echo -n "."
done

echo ""
echo "  ⚠️  Timeout waiting for pod"
kubectl delete pod ecr-test-pod -n default > /dev/null 2>&1
echo ""
echo "Check manually with:"
echo "  kubectl describe pod ecr-test-pod -n default"
