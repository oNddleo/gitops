#!/bin/bash
# VSF-Miniapp Destroy Script
# This script removes all applications deployed via ArgoCD

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

print_header "VSF-Miniapp Destroy Script"

echo "⚠️  WARNING: This script will destroy all applications deployed via ArgoCD."
echo ""
echo "This includes:"
echo "  • All VSF-Miniapp services (service-a, service-b) in all environments (dev, staging, production)"
echo "  • Infrastructure components (Linkerd, Traefik, Reloader, Secrets Store CSI)"
echo "  • Namespaces and all resources within them"
echo ""
echo "The following will be preserved by default:"
echo "  • ArgoCD itself (unless you choose to destroy it)"
echo "  • AWS Secrets Manager secrets"
echo "  • EKS cluster and nodes"
echo ""

read -p "Are you absolutely sure you want to continue? (type 'yes' to confirm): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    print_info "Destroy cancelled."
    exit 0
fi

# Ask about ArgoCD
echo ""
read -p "Do you also want to destroy ArgoCD itself? (yes/no): " DESTROY_ARGOCD

echo ""
print_warning "Starting destruction process..."
sleep 2

# Step 1: Delete Application-specific resources
print_header "Step 1: Deleting VSF-Miniapp Service Applications"

ENVIRONMENTS=("dev" "staging" "production")
SERVICES=("service-a" "service-b")

for env in "${ENVIRONMENTS[@]}"; do
    for service in "${SERVICES[@]}"; do
        APP_NAME="vsf-miniapp-${service}-${env}"

        print_info "Checking for application: $APP_NAME"

        if kubectl get application "$APP_NAME" -n argocd &>/dev/null; then
            print_info "Deleting ArgoCD application: $APP_NAME"

            # Delete the application with cascade (removes all resources)
            if command -v argocd &> /dev/null; then
                argocd app delete "$APP_NAME" --yes --cascade 2>/dev/null || \
                    kubectl delete application "$APP_NAME" -n argocd
            else
                kubectl delete application "$APP_NAME" -n argocd
            fi

            print_success "Deleted $APP_NAME"
            sleep 1
        else
            print_info "Application $APP_NAME not found (may already be deleted)"
        fi
    done
done

# Step 2: Delete ApplicationSets
print_header "Step 2: Deleting ApplicationSets"

APPSETS=("vsf-miniapp-services" "infrastructure")

for appset in "${APPSETS[@]}"; do
    print_info "Checking for ApplicationSet: $appset"

    if kubectl get applicationset "$appset" -n argocd &>/dev/null; then
        print_info "Deleting ApplicationSet: $appset"
        kubectl delete applicationset "$appset" -n argocd
        print_success "Deleted ApplicationSet: $appset"
        sleep 2
    else
        print_info "ApplicationSet $appset not found"
    fi
done

# Step 3: Delete Infrastructure Applications
print_header "Step 3: Deleting Infrastructure Applications"

# List of infrastructure apps to delete (in reverse dependency order)
INFRA_APPS=(
    "reloader"
    "traefik"
    "traefik-certificates"
    "linkerd-viz"
    "linkerd"
    "linkerd-crds"
    "linkerd-certificates"
    "secrets-store-csi-driver-provider-aws"
    "secrets-store-csi-driver"
    "cert-manager"
    "infrastructure-project"
)

for app in "${INFRA_APPS[@]}"; do
    print_info "Checking for infrastructure app: $app"

    if kubectl get application "$app" -n argocd &>/dev/null; then
        print_info "Deleting ArgoCD application: $app"

        if command -v argocd &> /dev/null; then
            argocd app delete "$app" --yes --cascade 2>/dev/null || \
                kubectl delete application "$app" -n argocd
        else
            kubectl delete application "$app" -n argocd
        fi

        print_success "Deleted $app"
        sleep 2
    else
        print_info "Application $app not found"
    fi
done

# Step 4: Delete application namespaces
print_header "Step 4: Cleaning Up Namespaces"

APP_NAMESPACES=("dev" "staging" "production" "reloader" "traefik" "linkerd" "linkerd-viz" "cert-manager")

print_warning "Waiting for resources to be cleaned up (30 seconds)..."
sleep 30

for ns in "${APP_NAMESPACES[@]}"; do
    if kubectl get namespace "$ns" &>/dev/null; then
        print_info "Deleting namespace: $ns"
        kubectl delete namespace "$ns" --timeout=60s 2>/dev/null || \
            print_warning "Namespace $ns deletion in progress (may take time)"
    else
        print_info "Namespace $ns already deleted"
    fi
done

# Step 5: Delete root application if exists
print_header "Step 5: Cleaning Up Root Application"

if kubectl get application root-app -n argocd &>/dev/null; then
    print_info "Deleting root application"
    kubectl delete application root-app -n argocd
    print_success "Deleted root application"
else
    print_info "Root application not found"
fi

# Step 6: Optionally destroy ArgoCD
if [ "$DESTROY_ARGOCD" = "yes" ]; then
    print_header "Step 6: Destroying ArgoCD"

    print_warning "Deleting ArgoCD self-managed application..."
    kubectl delete application argocd -n argocd 2>/dev/null || print_info "ArgoCD self-managed app not found"

    sleep 5

    print_warning "Deleting ArgoCD namespace..."
    kubectl delete namespace argocd --timeout=120s 2>/dev/null || \
        print_warning "ArgoCD namespace deletion in progress"

    print_success "ArgoCD destruction initiated"
else
    print_info "Preserving ArgoCD"
fi

# Step 7: Check for stuck resources
print_header "Step 7: Checking for Stuck Resources"

print_info "Checking for namespaces in Terminating state..."
TERMINATING_NS=$(kubectl get namespaces --field-selector status.phase=Terminating -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

if [ -n "$TERMINATING_NS" ]; then
    print_warning "The following namespaces are stuck in Terminating state:"
    echo "$TERMINATING_NS"
    echo ""
    echo "To force delete, run:"
    for ns in $TERMINATING_NS; do
        echo "  kubectl get namespace $ns -o json | jq '.spec.finalizers = []' | kubectl replace --raw /api/v1/namespaces/$ns/finalize -f -"
    done
else
    print_success "No stuck namespaces found"
fi

# Step 8: Summary
print_header "Destruction Summary"

echo "✅ Deleted all VSF-Miniapp service applications"
echo "✅ Deleted ApplicationSets"
echo "✅ Deleted infrastructure applications"
echo "✅ Cleaned up namespaces"

if [ "$DESTROY_ARGOCD" = "yes" ]; then
    echo "✅ ArgoCD destroyed"
else
    echo "ℹ️  ArgoCD preserved"
fi

echo ""
print_info "Checking remaining applications..."
REMAINING_APPS=$(kubectl get applications -n argocd --no-headers 2>/dev/null | wc -l)

if [ "$REMAINING_APPS" -gt 0 ]; then
    print_warning "Found $REMAINING_APPS remaining ArgoCD applications:"
    kubectl get applications -n argocd
    echo ""
    echo "To delete manually:"
    echo "  kubectl delete application <app-name> -n argocd"
else
    print_success "All applications have been deleted"
fi

echo ""
print_info "Remaining namespaces:"
kubectl get namespaces

echo ""
echo "📝 What was NOT deleted:"
echo "  • EKS cluster and nodes"
echo "  • AWS Secrets Manager secrets"
echo "  • AWS IAM roles and policies"
echo "  • ECR repositories and Docker images"
echo "  • Git repository contents"
echo ""
echo "To delete AWS resources, you need to:"
echo "  1. Delete secrets: aws secretsmanager delete-secret --secret-id <secret-name> --region us-east-1"
echo "  2. Destroy infrastructure: cd terraform && terraform destroy"
echo ""

print_success "Destroy process complete! 🎉"
