
### **Prompt: Design and Implement a GitOps Kubernetes Platform on AWS**

**Objective:** Design and implement a complete, production-ready CI/CD and application delivery platform on Amazon EKS. The system must adhere to GitOps principles, leveraging a decoupled CI and CD pipeline with robust configuration management, secrets handling, and networking.

---

#### **1. Core Philosophy & Requirements**

* **GitOps as the Single Source of Truth:** The entire state of the cluster (apps, config, mesh, ingress) must be declaratively defined in Git. Manual `kubectl` changes are forbidden.
* **Separation of CI and CD:**
  * **CI (Continuous Integration):** Responsible for building, testing, and packaging application code into Helm charts. Output is an OCI artifact (Helm chart) stored in a repository.
  * **CD (Continuous Delivery):** Responsible for deploying the packaged artifacts from the repository to the target environments based on the declarations in Git. This is handled by ArgoCD.
* **Security First:** Secrets are not stored in Git. Use HashiCorp Vault for dynamic secrets and configuration.
* **Automation & Observability:** The system must automatically respond to changes in both code and configuration.

---

#### **2. Technology Stack & Component Specifications**

| Component | Technology | Rationale & Specific Requirement |
| :--- | :--- | :--- |
| **Orchestration** | Amazon EKS | Managed control plane. Configure with a managed node group for add-ons and separate node groups for workloads. |
| **Package Management** | **Helm** & **Kustomize** | Use **Helm** as the primary package manager for 3rd-party applications (e.g., Traefik, Vault, Service Mesh). Use **Kustomize** for environment-specific overlays on top of both 3rd-party and internal Helm charts. |
| **Secrets Management** | **HashiCorp Vault** | Deploy Vault on EKS in High-Availability mode with an AWS DynamoDB & S3 backend. Integrate with ArgoCD using External Secrets Operator to inject secrets at deploy time. |
| **Configuration Reloader** | **Reloader** | Deploy Reloader to watch changes in ConfigMaps and Secrets and automatically perform rolling updates of dependent pods. |
| **Service Mesh** | **Linkerd**|. Must be installed via Helm and managed via GitOps. Enable mutual TLS (mTLS) by default for secure service-to-service communication. |
| **Ingress Controller** | **Traefik Proxy** | Deploy Traefik v3 via its Helm chart. It must be the cluster's sole entry point for north-south traffic. |
| **Ingress Configuration** | **Traefik IngressRoute** | Use the CRD `IngressRoute` (traefik.containo.us/v1alpha1) for all routing configuration, **not** the standard Kubernetes Ingress. This allows access to all Traefik features. |
| **Traefik Dashboard** | **Exposed via IngressRoute** | The Traefik dashboard must be exposed securely via an `IngressRoute`. It should be protected by authentication (e.g., BasicAuth Middleware) and only accessible from authorized IP ranges. |
| **CD & GitOps Operator** | **ArgoCD** | Install ArgoCD via Helm in its own dedicated namespace. It will be the "GitOps engine," continuously reconciling the cluster state with the Git repository. |
| **Git Repository** | (e.g., AzureDevops) | A single Git repository structured as below. |

---

#### **3. Git Repository Structure**

The Git repo must be structured to cleanly separate config from apps and environments.

```
gitops-platform/
├── bootstrap/           # Scripts to bootstrap ArgoCD and the root App of Apps
├── infrastructure/      # Cluster-wide add-ons (installed by the App of Apps)
│   ├── vault/          # Helm release for Vault + Kustomize patches
│   ├── traefik/        # Helm release for Traefik + IngressRoute for dashboard
│   ├── service-mesh/   # Helm release for Linkerd/Istio
│   ├── reloader/       # Helm release for Reloader
│   └── argocd/         # Helm release for ArgoCD itself (self-managed)
├── applications/        # Definitions of what *to deploy* (ArgoCD Application manifests)
│   ├── infrastructure-apps.yaml # App of Apps for infrastructure
│   ├── dev/
│   ├── staging/
│   └── production/
└── charts/              # Internal Helm charts for our microservices
    └── my-microservice/
        ├── Chart.yaml
        ├── values.yaml
        ├── templates/
        └── ci/          # CI-specific values (e.g., image tag)
```

---

#### **4. Implementation Steps & Key Integration Points**

**Phase 1: Bootstrap & Infrastructure as Code**

1. **Write the Bootstrap Manifests:** Create the initial ArgoCD `Application` that points to the `infrastructure-apps.yaml` (the App of Apps pattern). This is the only resource applied manually via `kubectl apply -f bootstrap/`.
2. **Define Infrastructure Helm Charts:** For each infra component (Traefik, Vault, Mesh, Reloader, ArgoCD), create a Kustomization that references the public Helm chart and includes a `kustomization.yaml` for environment-specific patches (e.g., setting `service.type: LoadBalancer` for Traefik).

**Phase 2: Configure Core Networking & Security**

1. **Configure Traefik & Dashboard:**
    * Create an `IngressRoute` for the Traefik dashboard.
    * Define and use a `Middleware` for BasicAuth or forward authentication to a service.
    * ArgoCD should automatically deploy this and make the dashboard available.
2. **Integrate Vault:**
    * Configure ArgoCD to use the Vault Plugin. This involves setting up `argocd-repo-server` with AVP and storing Vault connection details in a Kubernetes Secret.
    * Create example `ApplicationSet` or `Application` manifests that show how to reference secrets from Vault paths instead of hardcoding them in `values.yaml`.

**Phase 3: Application Deployment & CI/CD Pipeline**

1. **CI Pipeline (e.g., GitHub Actions):**
    * On a merge to `main`, the pipeline:
        * Builds and pushes the Docker image.
        * Packages the application's Helm chart from `charts/my-microservice`.
        * Publishes the Helm chart to a repository (e.g., OCI in ECR, Harbor).
        * **Updates the Git repo:** The pipeline commits an update to the `applications/production/app.yaml` file, changing the `values.yaml` to point to the new Helm chart version or image tag. **This is the CD trigger.**
2. **CD with ArgoCD:**
    * ArgoCD detects the Git commit made by the CI pipeline.
    * It pulls the new Helm chart from the repository and the updated values from Git.
    * It renders the manifests, retrieves any required secrets from Vault using AVP, and applies them to the cluster.
    * If the deployment updates a ConfigMap or Secret referenced via `reloader.stakater.com/auto`, Reloader automatically triggers a rolling update of the relevant pods.

**Phase 4: Service Mesh & Final Routing**

1. **Mesh Integration:** Ensure the mesh is injected into application namespaces via annotations. Define traffic-splitting `IngressRoute` rules in Traefik that direct traffic to different service versions based on weight or headers, leveraging the mesh for internal routing.

---

#### **5. Success Criteria & Validation**

* A commit to the application code repository automatically results in a new deployment in the target environment within 5 minutes, without manual intervention.
* Changing a secret in Vault automatically triggers a rollout of the dependent application pods (via Reloader).
* The Traefik dashboard is accessible via a secure URL and shows active `IngressRoute` configurations.
* ArgoCD's UI shows all applications as "Healthy" and "Synced," visualizing the entire platform's state.
* `kubectl get application -n argocd` returns a list of all managed apps.

---

This prompt provides a solid foundation for building the sophisticated platform you've described. You can now provide this to an AI or a team to generate the specific YAML manifests, Helm `values.yaml` files, and pipeline code.
