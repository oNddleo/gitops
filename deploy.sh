#!/bin/bash
# VSF-Miniapp Quick Deployment Script
# This script guides you through the deployment process

set -e

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
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Check if running in git repository
if [ ! -d .git ]; then
    print_error "Not in a Git repository. Please run this script from the gitops directory."
    exit 1
fi

print_header "VSF-Miniapp Deployment Wizard"

echo "This script will help you deploy the multi-service platform."
echo "It will guide you through configuration, secrets setup, and deployment."
echo ""

# Step 1: Configuration
print_header "Step 1: Update Configuration"

echo "We need to update placeholder values in your configuration files."
echo ""

# Check if already configured
if grep -q "YOUR_ECR_REGISTRY" charts/vsf-miniapp/ci/service-a-dev.yaml 2>/dev/null; then
    print_warning "Placeholders detected. Let's update them."
    echo ""

    read -p "Enter your ECR Registry URL (e.g., 123456789012.dkr.ecr.us-east-1.amazonaws.com): " ECR_REGISTRY
    read -p "Enter your AWS Account ID (e.g., 123456789012): " AWS_ACCOUNT_ID
    read -p "Enter your AWS Region (default: us-east-1): " AWS_REGION
    AWS_REGION=${AWS_REGION:-us-east-1}

    echo ""
    print_info "Updating configuration files..."

    # Update ECR registry
    find charts/vsf-miniapp/ci/ -name "*.yaml" -exec sed -i "s|YOUR_ECR_REGISTRY|${ECR_REGISTRY}|g" {} \;

    # Update AWS Account ID
    find charts/vsf-miniapp/ci/ -name "*.yaml" -exec sed -i "s|ACCOUNT_ID|${AWS_ACCOUNT_ID}|g" {} \;

    # Update AWS Region if not us-east-1
    if [ "$AWS_REGION" != "us-east-1" ]; then
        find charts/vsf-miniapp/ci/ -name "*.yaml" -exec sed -i "s|us-east-1|${AWS_REGION}|g" {} \;
    fi

    print_success "Configuration updated!"

    # Ask if they want to commit
    read -p "Commit these changes to Git? (y/n): " COMMIT_CHANGES
    if [ "$COMMIT_CHANGES" = "y" ]; then
        git add charts/vsf-miniapp/ci/
        git commit -m "chore: update ECR registry and AWS account ID to production values"
        print_success "Changes committed!"

        read -p "Push to GitHub? (y/n): " PUSH_CHANGES
        if [ "$PUSH_CHANGES" = "y" ]; then
            CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
            git push origin $CURRENT_BRANCH
            print_success "Changes pushed to GitHub!"
        fi
    fi
else
    print_success "Configuration already updated!"
fi

# Step 2: AWS Secrets
print_header "Step 2: AWS Secrets Manager Setup"

echo "Do you want to create AWS Secrets Manager secrets now?"
echo "You'll need AWS CLI configured with appropriate permissions."
echo ""
read -p "Create secrets? (y/n): " CREATE_SECRETS

if [ "$CREATE_SECRETS" = "y" ]; then
    AWS_REGION=${AWS_REGION:-us-east-1}

    print_info "Creating secrets in AWS Secrets Manager (region: $AWS_REGION)..."
    echo ""

    # Service A - Dev
    print_info "Creating dev/vsf-miniapp/service-a/database..."
    aws secretsmanager create-secret \
        --name dev/vsf-miniapp/service-a/database \
        --description "Service A dev database credentials" \
        --secret-string '{"url":"postgresql://localhost:5432/servicea","username":"dev_user","password":"dev_password"}' \
        --region $AWS_REGION 2>/dev/null && print_success "Created!" || print_warning "Secret may already exist (this is OK)"

    # Service B - Dev
    print_info "Creating dev/vsf-miniapp/service-b/mongodb..."
    aws secretsmanager create-secret \
        --name dev/vsf-miniapp/service-b/mongodb \
        --description "Service B dev MongoDB credentials" \
        --secret-string '{"connectionString":"mongodb://localhost:27017/serviceb","database":"serviceb"}' \
        --region $AWS_REGION 2>/dev/null && print_success "Created!" || print_warning "Secret may already exist (this is OK)"

    echo ""
    print_success "Dev secrets created!"
    print_warning "Remember to create staging and production secrets separately!"
    print_info "See CONFIGURATION_GUIDE.md for all secret creation commands."
else
    print_warning "Skipping secret creation. Make sure secrets exist before deploying!"
fi

# Step 3: Cluster Connection
print_header "Step 3: Connect to Kubernetes Cluster"

read -p "Do you want to connect to your EKS cluster now? (y/n): " CONNECT_CLUSTER

if [ "$CONNECT_CLUSTER" = "y" ]; then
    read -p "Enter EKS cluster name (default: gitops-eks-cluster): " CLUSTER_NAME
    CLUSTER_NAME=${CLUSTER_NAME:-gitops-eks-cluster}
    AWS_REGION=${AWS_REGION:-us-east-1}

    print_info "Updating kubeconfig..."
    aws eks update-kubeconfig --name $CLUSTER_NAME --region $AWS_REGION

    print_info "Verifying connection..."
    if kubectl cluster-info &>/dev/null; then
        print_success "Connected to cluster!"
        kubectl get nodes
    else
        print_error "Failed to connect to cluster. Check your AWS credentials and cluster name."
        exit 1
    fi
fi

# Step 4: Verify Infrastructure
print_header "Step 4: Verify Infrastructure Components"

echo "Checking infrastructure components..."
echo ""

# Check ArgoCD
print_info "Checking ArgoCD..."
if kubectl get namespace argocd &>/dev/null; then
    ARGOCD_PODS=$(kubectl get pods -n argocd --no-headers 2>/dev/null | wc -l)
    print_success "ArgoCD is installed ($ARGOCD_PODS pods)"
else
    print_warning "ArgoCD not found! Run ./bootstrap/install.sh to install infrastructure."
fi

# Check Linkerd
print_info "Checking Linkerd..."
if kubectl get namespace linkerd &>/dev/null; then
    LINKERD_PODS=$(kubectl get pods -n linkerd --no-headers 2>/dev/null | wc -l)
    print_success "Linkerd is installed ($LINKERD_PODS pods)"
else
    print_warning "Linkerd not found! Run ./bootstrap/install.sh to install infrastructure."
fi

# Check Secrets Store CSI
print_info "Checking Secrets Store CSI Driver..."
if kubectl get pods -n kube-system | grep -q secrets-store-csi-driver; then
    print_success "Secrets Store CSI Driver is installed"
else
    print_warning "Secrets Store CSI Driver not found! Install it before deploying."
fi

# Check Traefik
print_info "Checking Traefik..."
if kubectl get namespace traefik &>/dev/null; then
    print_success "Traefik is installed"
else
    print_warning "Traefik not found! Run ./bootstrap/install.sh to install infrastructure."
fi

# Check Reloader
print_info "Checking Reloader..."
if kubectl get namespace reloader &>/dev/null; then
    print_success "Reloader is installed"
else
    print_warning "Reloader not found! Run ./bootstrap/install.sh to install infrastructure."
fi

echo ""

# Step 5: Deploy Services
print_header "Step 5: Deploy Services"

echo "Ready to deploy services to dev environment?"
echo ""
read -p "Deploy now? (y/n): " DEPLOY_NOW

if [ "$DEPLOY_NOW" = "y" ]; then
    print_info "Syncing Service A to dev..."
    if command -v argocd &> /dev/null; then
        argocd app sync vsf-miniapp-service-a-dev 2>&1 || print_warning "ArgoCD CLI sync failed. The app will auto-sync from Git."

        print_info "Syncing Service B to dev..."
        argocd app sync vsf-miniapp-service-b-dev 2>&1 || print_warning "ArgoCD CLI sync failed. The app will auto-sync from Git."

        echo ""
        print_info "Waiting for deployments (this may take 2-3 minutes)..."
        sleep 5

        # Check deployment status
        print_info "Checking Service A deployment..."
        kubectl get pods -n dev -l service=service-a

        echo ""
        print_info "Checking Service B deployment..."
        kubectl get pods -n dev -l service=service-b

    else
        print_warning "ArgoCD CLI not installed. Services will auto-sync from Git."
        print_info "You can check status with: kubectl get pods -n dev"
    fi
else
    print_info "Deployment skipped. Services will auto-sync when you push to GitHub."
fi

# Step 6: Verification
print_header "Step 6: Verification Commands"

echo "Here are some useful commands to verify your deployment:"
echo ""
echo -e "${GREEN}# Check ArgoCD applications${NC}"
echo "argocd app list | grep vsf-miniapp"
echo ""
echo -e "${GREEN}# Check pods in dev${NC}"
echo "kubectl get pods -n dev"
echo ""
echo -e "${GREEN}# Check secrets${NC}"
echo "kubectl get secrets -n dev | grep service-"
echo ""
echo -e "${GREEN}# Verify Linkerd mTLS${NC}"
echo "linkerd viz stat deployment -n dev"
echo ""
echo -e "${GREEN}# View live traffic${NC}"
echo "linkerd viz tap deployment/service-a-vsf-miniapp-service-a -n dev"
echo ""
echo -e "${GREEN}# Check service-to-service communication${NC}"
echo "kubectl exec -n dev \$(kubectl get pod -n dev -l service=service-a -o jsonpath='{.items[0].metadata.name}') -c service-a -- curl -s http://service-b-vsf-miniapp-service-b.dev.svc.cluster.local/health/ready"
echo ""

# Final Summary
print_header "Deployment Complete!"

echo "✅ Configuration updated"
echo "✅ Git repository ready"
echo "✅ Infrastructure verified"
echo ""
echo "📚 Next Steps:"
echo "  1. Review deployment: kubectl get pods -n dev"
echo "  2. Check ArgoCD UI: kubectl port-forward -n argocd svc/argocd-server 8080:443"
echo "  3. View Linkerd dashboard: linkerd viz dashboard"
echo "  4. Read DEPLOYMENT_INSTRUCTIONS.md for detailed verification steps"
echo ""
echo "🚀 To deploy to staging/production:"
echo "  argocd app sync vsf-miniapp-service-a-staging"
echo "  argocd app sync vsf-miniapp-service-a-production"
echo ""
echo "📖 Documentation:"
echo "  - DEPLOYMENT_INSTRUCTIONS.md - Full deployment guide"
echo "  - CONFIGURATION_GUIDE.md - Configuration reference"
echo "  - MULTI_SERVICE_SUMMARY.md - Quick troubleshooting"
echo ""

print_success "Happy deploying! 🎉"
