#!/bin/bash
set -e

echo "======================================"
echo "Linkerd Certificate Generation"
echo "======================================"

# Check if step CLI is installed
if ! command -v step &> /dev/null; then
    echo "step CLI not found. Installing..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install step
    else
        echo "Please install step CLI from: https://smallstep.com/docs/step-cli/installation"
        exit 1
    fi
fi

# Create certificates directory
mkdir -p certs
cd certs

echo "Generating trust anchor certificate..."
step certificate create root.linkerd.cluster.local ca.crt ca.key \
  --profile root-ca --no-password --insecure \
  --not-after=87600h \
  --kty RSA --size 4096

echo "Generating issuer certificate..."
step certificate create identity.linkerd.cluster.local issuer.crt issuer.key \
  --profile intermediate-ca --not-after=8760h \
  --no-password --insecure \
  --ca ca.crt --ca-key ca.key \
  --kty RSA --size 4096

echo ""
echo "======================================"
echo "Certificates generated successfully!"
echo "======================================"
echo ""
echo "Files created in ./certs directory:"
echo "  - ca.crt (Trust Anchor Certificate)"
echo "  - ca.key (Trust Anchor Private Key)"
echo "  - issuer.crt (Issuer Certificate)"
echo "  - issuer.key (Issuer Private Key)"
echo ""
echo "Next steps:"
echo "1. Create Kubernetes secrets with these certificates"
echo "2. Update linkerd-certificates.yaml with the actual certificate contents"
echo ""
echo "Or apply directly to cluster:"
echo ""
echo "kubectl create namespace linkerd"
echo ""
echo "kubectl create secret tls linkerd-trust-anchor \\"
echo "  --cert=ca.crt \\"
echo "  --key=ca.key \\"
echo "  --namespace=linkerd"
echo ""
echo "kubectl create secret tls linkerd-identity-issuer \\"
echo "  --cert=issuer.crt \\"
echo "  --key=issuer.key \\"
echo "  --namespace=linkerd"
echo ""
echo "kubectl label secret linkerd-trust-anchor linkerd.io/control-plane-component=identity -n linkerd"
echo "kubectl label secret linkerd-identity-issuer linkerd.io/control-plane-component=identity -n linkerd"

cd ..
