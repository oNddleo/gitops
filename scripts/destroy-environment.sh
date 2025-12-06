#!/bin/bash
# VSF-Miniapp Destroy Specific Environment
# This script removes services from a specific environment only

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

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl not found. Please install kubectl first."
    exit 1
fi

# Check cluster connection
if ! kubectl cluster-info &>/dev/null; then
    print_error "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
    exit 1
fi

print_header "Destroy Environment"

# Get environment from user
echo "Which environment do you want to destroy?"
echo "  1) dev"
echo "  2) staging"
echo "  3) production"
echo ""
read -p "Enter choice (1-3): " ENV_CHOICE

case $ENV_CHOICE in
    1) ENVIRONMENT="dev" ;;
    2) ENVIRONMENT="staging" ;;
    3) ENVIRONMENT="production" ;;
    *)
        print_error "Invalid choice"
        exit 1
        ;;
esac

echo ""
print_warning "⚠️  WARNING: This will destroy all services in the $ENVIRONMENT environment!"
echo ""
echo "Services to be deleted:"
echo "  • service-a ($ENVIRONMENT)"
echo "  • service-b ($ENVIRONMENT)"
echo ""
echo "The $ENVIRONMENT namespace will also be deleted."
echo ""

read -p "Are you sure you want to continue? (type 'yes' to confirm): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    print_info "Cancelled."
    exit 0
fi

# Delete service applications for this environment
print_header "Deleting Services in $ENVIRONMENT"

SERVICES=("service-a" "service-b")

for service in "${SERVICES[@]}"; do
    APP_NAME="vsf-miniapp-${service}-${ENVIRONMENT}"

    print_info "Checking for application: $APP_NAME"

    if kubectl get application "$APP_NAME" -n argocd &>/dev/null; then
        print_info "Deleting: $APP_NAME"

        if command -v argocd &> /dev/null; then
            argocd app delete "$APP_NAME" --yes --cascade 2>/dev/null || \
                kubectl delete application "$APP_NAME" -n argocd
        else
            kubectl delete application "$APP_NAME" -n argocd
        fi

        print_success "Deleted $APP_NAME"
        sleep 2
    else
        print_warning "$APP_NAME not found (may already be deleted)"
    fi
done

# Clean up namespace
print_header "Cleaning Up $ENVIRONMENT Namespace"

print_warning "Waiting for resources to be cleaned up (20 seconds)..."
sleep 20

if kubectl get namespace "$ENVIRONMENT" &>/dev/null; then
    print_info "Deleting namespace: $ENVIRONMENT"
    kubectl delete namespace "$ENVIRONMENT" --timeout=60s 2>/dev/null || \
        print_warning "Namespace $ENVIRONMENT deletion in progress (may take time)"

    # Wait for namespace deletion
    print_info "Waiting for namespace to be fully deleted..."
    kubectl wait --for=delete namespace/"$ENVIRONMENT" --timeout=120s 2>/dev/null || \
        print_warning "Namespace deletion is taking longer than expected"

    print_success "Namespace $ENVIRONMENT deleted"
else
    print_info "Namespace $ENVIRONMENT already deleted"
fi

# Summary
print_header "Summary"

echo "✅ Deleted all services in $ENVIRONMENT environment"
echo "✅ Deleted $ENVIRONMENT namespace"
echo ""

print_info "Other environments are still running:"
kubectl get applications -n argocd -l environment!="$ENVIRONMENT" 2>/dev/null || true

echo ""
print_success "Environment $ENVIRONMENT destroyed successfully! 🎉"
