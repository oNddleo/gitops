#!/bin/bash
# VSF-Miniapp Destroy Services Only
# This script removes only the VSF-Miniapp services, preserving infrastructure

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

print_header "Destroy VSF-Miniapp Services Only"

echo "This script will destroy only the VSF-Miniapp services."
echo ""
echo "Services to be deleted:"
echo "  • service-a (dev, staging, production)"
echo "  • service-b (dev, staging, production)"
echo ""
echo "Infrastructure will be preserved:"
echo "  • ArgoCD"
echo "  • Linkerd"
echo "  • Traefik"
echo "  • Secrets Store CSI Driver"
echo "  • Reloader"
echo ""

read -p "Continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    print_info "Cancelled."
    exit 0
fi

# Delete service applications
print_header "Deleting Service Applications"

ENVIRONMENTS=("dev" "staging" "production")
SERVICES=("service-a" "service-b")

for env in "${ENVIRONMENTS[@]}"; do
    for service in "${SERVICES[@]}"; do
        APP_NAME="vsf-miniapp-${service}-${env}"

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
            sleep 1
        else
            print_info "$APP_NAME not found"
        fi
    done
done

# Delete the services ApplicationSet
print_header "Deleting Services ApplicationSet"

if kubectl get applicationset vsf-miniapp-services -n argocd &>/dev/null; then
    print_info "Deleting ApplicationSet: vsf-miniapp-services"
    kubectl delete applicationset vsf-miniapp-services -n argocd
    print_success "Deleted ApplicationSet"
else
    print_info "ApplicationSet not found"
fi

# Clean up service namespaces
print_header "Cleaning Up Service Namespaces"

print_warning "Waiting for resources to be cleaned up (20 seconds)..."
sleep 20

SERVICE_NAMESPACES=("dev" "staging" "production")

for ns in "${SERVICE_NAMESPACES[@]}"; do
    if kubectl get namespace "$ns" &>/dev/null; then
        # Check if namespace has any non-service resources
        POD_COUNT=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | wc -l)

        if [ "$POD_COUNT" -eq 0 ]; then
            print_info "Deleting empty namespace: $ns"
            kubectl delete namespace "$ns" --timeout=60s 2>/dev/null || \
                print_warning "Namespace $ns deletion in progress"
        else
            print_info "Namespace $ns still has $POD_COUNT pods, skipping deletion"
        fi
    else
        print_info "Namespace $ns already deleted"
    fi
done

# Summary
print_header "Summary"

echo "✅ Deleted all VSF-Miniapp service applications"
echo "✅ Deleted services ApplicationSet"
echo "✅ Cleaned up service namespaces"
echo "✅ Infrastructure components preserved"
echo ""

print_info "Remaining applications:"
kubectl get applications -n argocd 2>/dev/null || print_info "No applications found"

echo ""
print_success "Services destroyed successfully! 🎉"
