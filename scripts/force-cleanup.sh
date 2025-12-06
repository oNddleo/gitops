#!/bin/bash
# VSF-Miniapp Force Cleanup Script
# This script forcefully removes stuck resources and finalizers

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

# Check if jq is available
if ! command -v jq &> /dev/null; then
    print_error "jq not found. Please install jq first."
    print_info "Install with: sudo apt-get install jq (Ubuntu/Debian) or brew install jq (macOS)"
    exit 1
fi

# Check cluster connection
if ! kubectl cluster-info &>/dev/null; then
    print_error "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
    exit 1
fi

print_header "Force Cleanup Script"

echo "⚠️  WARNING: This script will forcefully remove stuck resources!"
echo ""
echo "This script will:"
echo "  • Remove finalizers from stuck namespaces"
echo "  • Force delete stuck ArgoCD applications"
echo "  • Remove stuck pods and deployments"
echo "  • Clean up orphaned resources"
echo ""
echo "Only use this if normal destroy scripts have failed!"
echo ""

read -p "Are you sure you want to force cleanup? (type 'FORCE' to confirm): " CONFIRM

if [ "$CONFIRM" != "FORCE" ]; then
    print_info "Cancelled."
    exit 0
fi

# Step 1: Force delete stuck namespaces
print_header "Step 1: Force Delete Stuck Namespaces"

STUCK_NAMESPACES=$(kubectl get namespaces --field-selector status.phase=Terminating -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

if [ -n "$STUCK_NAMESPACES" ]; then
    print_warning "Found stuck namespaces: $STUCK_NAMESPACES"

    for ns in $STUCK_NAMESPACES; do
        print_info "Force deleting namespace: $ns"

        # Remove finalizers
        kubectl get namespace "$ns" -o json | \
            jq '.spec.finalizers = []' | \
            kubectl replace --raw "/api/v1/namespaces/$ns/finalize" -f - 2>/dev/null && \
            print_success "Removed finalizers from $ns" || \
            print_warning "Failed to remove finalizers from $ns"

        sleep 1
    done
else
    print_success "No stuck namespaces found"
fi

# Step 2: Force delete stuck ArgoCD applications
print_header "Step 2: Force Delete Stuck ArgoCD Applications"

if kubectl get namespace argocd &>/dev/null; then
    STUCK_APPS=$(kubectl get applications -n argocd -o jsonpath='{.items[?(@.metadata.deletionTimestamp!="")].metadata.name}' 2>/dev/null || echo "")

    if [ -n "$STUCK_APPS" ]; then
        print_warning "Found stuck ArgoCD applications: $STUCK_APPS"

        for app in $STUCK_APPS; do
            print_info "Force deleting application: $app"

            # Remove finalizers
            kubectl patch application "$app" -n argocd \
                --type json \
                -p='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>/dev/null && \
                print_success "Removed finalizers from $app" || \
                print_warning "Failed to remove finalizers from $app"

            sleep 1
        done
    else
        print_success "No stuck ArgoCD applications found"
    fi
else
    print_info "ArgoCD namespace not found"
fi

# Step 3: Clean up stuck pods
print_header "Step 3: Clean Up Stuck Pods"

NAMESPACES=("dev" "staging" "production" "linkerd" "linkerd-viz" "traefik" "reloader" "cert-manager")

for ns in "${NAMESPACES[@]}"; do
    if kubectl get namespace "$ns" &>/dev/null; then
        print_info "Checking namespace: $ns"

        # Force delete stuck pods
        STUCK_PODS=$(kubectl get pods -n "$ns" --field-selector status.phase=Unknown -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

        if [ -n "$STUCK_PODS" ]; then
            for pod in $STUCK_PODS; do
                print_info "Force deleting pod: $pod"
                kubectl delete pod "$pod" -n "$ns" --force --grace-period=0 2>/dev/null || true
            done
        fi

        # Delete all pods if namespace is terminating
        NS_STATUS=$(kubectl get namespace "$ns" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        if [ "$NS_STATUS" = "Terminating" ]; then
            print_info "Force deleting all pods in terminating namespace: $ns"
            kubectl delete pods --all -n "$ns" --force --grace-period=0 2>/dev/null || true
        fi
    fi
done

# Step 4: Remove stuck PVCs
print_header "Step 4: Clean Up Stuck PVCs"

for ns in "${NAMESPACES[@]}"; do
    if kubectl get namespace "$ns" &>/dev/null; then
        STUCK_PVCS=$(kubectl get pvc -n "$ns" -o jsonpath='{.items[?(@.metadata.deletionTimestamp!="")].metadata.name}' 2>/dev/null || echo "")

        if [ -n "$STUCK_PVCS" ]; then
            print_warning "Found stuck PVCs in $ns: $STUCK_PVCS"

            for pvc in $STUCK_PVCS; do
                print_info "Force deleting PVC: $pvc"

                kubectl patch pvc "$pvc" -n "$ns" \
                    --type json \
                    -p='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>/dev/null || true

                sleep 1
            done
        fi
    fi
done

# Step 5: Clean up stuck ApplicationSets
print_header "Step 5: Clean Up Stuck ApplicationSets"

if kubectl get namespace argocd &>/dev/null; then
    STUCK_APPSETS=$(kubectl get applicationsets -n argocd -o jsonpath='{.items[?(@.metadata.deletionTimestamp!="")].metadata.name}' 2>/dev/null || echo "")

    if [ -n "$STUCK_APPSETS" ]; then
        print_warning "Found stuck ApplicationSets: $STUCK_APPSETS"

        for appset in $STUCK_APPSETS; do
            print_info "Force deleting ApplicationSet: $appset"

            kubectl patch applicationset "$appset" -n argocd \
                --type json \
                -p='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>/dev/null && \
                print_success "Removed finalizers from $appset" || \
                print_warning "Failed to remove finalizers from $appset"

            sleep 1
        done
    else
        print_success "No stuck ApplicationSets found"
    fi
fi

# Step 6: Clean up webhook configurations that might block deletions
print_header "Step 6: Clean Up Webhook Configurations"

print_info "Checking for validating webhook configurations..."
LINKERD_WEBHOOKS=$(kubectl get validatingwebhookconfigurations -o name | grep linkerd || echo "")
if [ -n "$LINKERD_WEBHOOKS" ]; then
    echo "$LINKERD_WEBHOOKS" | xargs kubectl delete 2>/dev/null || true
    print_success "Removed Linkerd webhook configurations"
fi

print_info "Checking for mutating webhook configurations..."
LINKERD_MUTATING=$(kubectl get mutatingwebhookconfigurations -o name | grep linkerd || echo "")
if [ -n "$LINKERD_MUTATING" ]; then
    echo "$LINKERD_MUTATING" | xargs kubectl delete 2>/dev/null || true
    print_success "Removed Linkerd mutating webhook configurations"
fi

# Step 7: Final cleanup check
print_header "Step 7: Final Cleanup Check"

print_info "Checking for remaining stuck resources..."
echo ""

print_info "Namespaces in Terminating state:"
kubectl get namespaces --field-selector status.phase=Terminating 2>/dev/null || echo "None"

echo ""
print_info "ArgoCD Applications with deletion timestamp:"
kubectl get applications -n argocd -o jsonpath='{.items[?(@.metadata.deletionTimestamp!="")].metadata.name}' 2>/dev/null || echo "None"

echo ""
print_info "ApplicationSets with deletion timestamp:"
kubectl get applicationsets -n argocd -o jsonpath='{.items[?(@.metadata.deletionTimestamp!="")].metadata.name}' 2>/dev/null || echo "None"

# Summary
print_header "Force Cleanup Summary"

echo "✅ Attempted to remove finalizers from stuck namespaces"
echo "✅ Attempted to force delete stuck ArgoCD applications"
echo "✅ Cleaned up stuck pods and PVCs"
echo "✅ Removed webhook configurations"
echo ""
print_warning "If resources are still stuck, you may need to:"
echo "  1. Manually check for custom finalizers: kubectl get <resource> -o yaml"
echo "  2. Check for admission webhooks: kubectl get validatingwebhookconfigurations,mutatingwebhookconfigurations"
echo "  3. Review cluster events: kubectl get events --all-namespaces --sort-by='.lastTimestamp'"
echo ""
echo "For persistent issues, consider:"
echo "  • Restarting the Kubernetes API server"
echo "  • Checking etcd for orphaned resources"
echo "  • Using kubectl delete with --force --grace-period=0"
echo ""

print_success "Force cleanup complete! 🎉"
