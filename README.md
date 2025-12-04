# GitOps Kubernetes Platform on AWS EKS

A production-ready, multi-service GitOps platform on Amazon EKS with Linkerd mTLS, AWS Secrets Manager, and automated deployments.

---

## 🚀 Quick Start

Get your complete GitOps platform running in **under 10 minutes** with a single command:

```bash
./deploy.sh
```

For detailed setup instructions, prerequisites, and manual deployment steps, please refer to the [Getting Started Guide](./docs/GETTING_STARTED.md).

---

## ✨ Key Features

This platform provides a robust foundation for modern microservices:

*   **Zero-Trust Networking:** Automatic mTLS with [Linkerd Service Mesh](./docs/ARCHITECTURE.md#security-architecture) for all service-to-service communication.
*   **Centralized Secret Management:** Securely store and manage secrets using [AWS Secrets Manager](./docs/ARCHITECTURE.md#security-architecture) integrated via CSI Driver.
*   **Automated Deployments:** GitOps-driven continuous delivery with [ArgoCD](./docs/ARCHITECTURE.md).
*   **Scalable Microservices:** A shared Helm chart supports multiple services (Java, Node.js, Python) across [Dev, Staging, and Production environments](./docs/ARCHITECTURE.md).
*   **Built-in Observability:** Prometheus metrics and Linkerd Viz for insight into application and mesh health.
*   **High Availability:** Configured with Horizontal Pod Autoscaling (HPA) and Pod Anti-Affinity.

---

## 📖 Documentation

Explore the comprehensive documentation for this platform:

*   **[Getting Started Guide](./docs/GETTING_STARTED.md)**: Your go-to for setup, deployment, and configuration.
*   **[Architecture & Design](./docs/ARCHITECTURE.md)**: Deep dive into the system's architecture, technology stack, and design principles.
*   **[Operations & Maintenance](./docs/OPERATIONS.md)**: Daily commands, troubleshooting cheat sheets, and maintenance workflows.
*   **[Development Guide](./docs/DEVELOPMENT.md)**: Learn how to add new services and understand the Helm/Kustomize patterns.
*   **[Troubleshooting Guide](./docs/TROUBLESHOOTING.md)**: Solutions for common issues including Linkerd, secrets, and CI/CD.
*   **[Optimization Report](./OPTIMIZATION_REPORT.md)**: Summary of the recent repository improvements and refactoring.

---

## 🗺️ Repository Structure

*   `/applications`: ArgoCD ApplicationSet manifests, defining what gets deployed.
*   `/bootstrap`: Scripts and manifests for initial cluster setup.
*   `/charts`: Reusable Helm charts for deploying services.
*   `/docs`: Detailed documentation and guides.
*   `/infrastructure`: Kustomize overlays and Helm values for platform components (e.g., Linkerd, Traefik).
*   `/terraform`: Infrastructure as Code for AWS resources.
*   `./deploy.sh`: One-command script for a full platform deployment.

---

## Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details (or create one if it does not exist yet).

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## Support

*   **Issues:** For bugs or feature requests, please open an issue on GitHub.
*   **Documentation:** Refer to the [docs/](./docs/) folder for detailed information.

---
**Last Updated:** December 4, 2025
**Platform Version:** 2.0.0 (AWS Secrets Manager)