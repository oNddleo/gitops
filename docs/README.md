# GitOps Platform Documentation

## Core Guides

*   **[GETTING_STARTED.md](GETTING_STARTED.md)** - Installation, Checklist, and Quick Start.
*   **[ARCHITECTURE.md](ARCHITECTURE.md)** - System design, multi-service strategy, and security.
*   **[OPERATIONS.md](OPERATIONS.md)** - Daily commands, maintenance, and cheat sheets.
*   **[DEVELOPMENT.md](DEVELOPMENT.md)** - How to add new services and code patterns.
*   **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** - Fixes for Linkerd, Secrets, and CI/CD.

## Repository Structure

*   `/applications` - ArgoCD Application manifests (GitOps entry point).
*   `/bootstrap` - Scripts to set up the cluster initially.
*   `/charts` - Shared Helm charts for microservices.
*   `/infrastructure` - Kustomize/Helm configs for platform tools (Linkerd, Traefik).
*   `/docs` - This documentation folder.

---
*Note: This repository uses AWS Secrets Manager for secrets and Linkerd for mTLS.*