#!/bin/bash
set -e

echo "======================================"
echo "GitOps Platform Bootstrap"
echo "======================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}kubectl not found. Please install kubectl first.${NC}"
    exit 1
fi

# Check if we can connect to the cluster
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}Cannot connect to Kubernetes cluster. Please check your kubeconfig.${NC}"
    exit 1
fi

echo -e "${GREEN}Connected to cluster:${NC}"
kubectl cluster-info | head -1

# Install ArgoCD via Helm
echo -e "\n${YELLOW}Step 1: Installing ArgoCD via Helm...${NC}"

# Add ArgoCD Helm repository
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# Create argocd namespace
kubectl apply -f bootstrap/argocd-namespace.yaml

# Install ArgoCD
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --set server.service.type=LoadBalancer \
  --set configs.params."application\.instanceLabelKey"=argocd.argoproj.io/instance \
  --set configs.params."server\.insecure"=true \
  --wait \
  --timeout 30s  

echo -e "${GREEN}ArgoCD installed successfully!${NC}"

# Wait for ArgoCD to be ready
echo -e "\n${YELLOW}Step 2: Waiting for ArgoCD to be ready...${NC}"
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s

# Get ArgoCD admin password
echo -e "\n${YELLOW}Step 3: Retrieving ArgoCD admin credentials...${NC}"
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
ARGOCD_SERVER=$(kubectl -n argocd get svc argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

if [ -z "$ARGOCD_SERVER" ]; then
    ARGOCD_SERVER=$(kubectl -n argocd get svc argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
fi

echo -e "${GREEN}ArgoCD URL: https://${ARGOCD_SERVER}${NC}"
echo -e "${GREEN}Username: admin${NC}"
echo -e "${GREEN}Password: ${ARGOCD_PASSWORD}${NC}"

# Apply the root App of Apps
echo -e "\n${YELLOW}Step 4: Deploying Root App of Apps...${NC}"

# Update the repository URL in root-app.yaml
echo -e "${YELLOW}Please update the repoURL in bootstrap/root-app.yaml before proceeding.${NC}"
read -p "Have you updated the repository URL? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${RED}Please update bootstrap/root-app.yaml with your Git repository URL and run this script again.${NC}"
    exit 1
fi

kubectl apply -f bootstrap/root-app.yaml

echo -e "\n${GREEN}======================================"
echo -e @"Bootstrap Complete!"
echo -e "======================================${NC}"
echo -e "ArgoCD is now managing the cluster via GitOps."
echo -e "All infrastructure components will be deployed automatically."
echo -e "\nNext steps:"
echo -e "1. Login to ArgoCD UI at https://${ARGOCD_SERVER}"
echo -e "2. Monitor the application sync status"
echo -e "3. Configure Vault backend (AWS DynamoDB + S3)"
echo -e "4. Update application configurations as needed"
