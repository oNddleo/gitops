#!/bin/bash

# Usage: ./patch-argocd-apps.sh [operation]
# Operations:
#   refresh (default): Triggers a hard refresh on all applications
#   sync: Triggers a sync on all applications (not implemented yet, just an example)

OPERATION=${1:-refresh}
NAMESPACE="argocd"

echo "Targeting namespace: $NAMESPACE"
echo "Operation: $OPERATION"

case $OPERATION in
    refresh)
        echo "Triggering hard refresh for all applications..."
        kubectl get applications -n "$NAMESPACE" -o name | xargs -I {} kubectl patch {} -n "$NAMESPACE" --type merge -p '{"metadata": {"annotations": {"argocd.argoproj.io/refresh": "hard"}}}'
        echo "Hard refresh triggered."
        ;;
    *)
        echo "Unknown operation: $OPERATION"
        echo "Usage: $0 [refresh]"
        exit 1
        ;;
esac
