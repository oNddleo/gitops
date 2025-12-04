
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

---
### **Prompt: Migration to AWS Secrets Manager**
Act as a Senior DevOps Engineer and Kubernetes Architect. I need to refactor a specific section of our infrastructure roadmap regarding Secrets Management.

  We have decided to move away from self-hosted HashiCorp Vault to reduce operational overhead. We will strictly use AWS Secrets Manager.

  **Context & Constraints:**
  1.  **Remove:** HashiCorp Vault (and its DynamoDB/S3 backends).
  2.  **Remove:** External Secrets Operator (ESO).
  3.  **Implement:** AWS Secrets Manager integrated directly via the **Kubernetes Secrets Store CSI Driver** (using the AWS Provider).
  4.  **Goal:** Pods must be able to mount secrets from AWS Secrets Manager as volumes or sync them to Kubernetes Secrets via the CSI driver.

  **Task 1: Update the Documentation**
  Please rewrite the following row in our project plan to reflect this architectural change:
  * **Original:** `| Secrets Management | HashiCorp Vault | Deploy Vault on EKS in High-Availability mode with an AWS DynamoDB & S3 backend. Integrate with ArgoCD using External Secrets Operator to inject secrets at deploy time. |`

  **Task 2: Implementation Plan (Terraform & Helm)**
  Provide the necessary Infrastructure-as-Code snippets to implement this change:
  1.  **IAM Policy:** A Terraform snippet for the IAM OIDC role that allows the EKS pods to read from AWS Secrets Manager.
  2.  **Helm Release:** The Terraform/Helm configuration to install the `secrets-store-csi-driver` and the `secrets-store-csi-driver-provider-aws`.
  3.  **Manifest Example:** A sample `SecretProviderClass` YAML that demonstrates how to map an AWS Secret to a Kubernetes Secret.

---
### **Prompt: Merge & Refactor**

I need to refactor the project documentation to reflect our architectural changes.

**Files to process:**
1.  `IMPLEMENTATION_PLAN.md`
2.  `DEPLOYMENT_CHECKLIST.md`
3.  `README.md`
4.  `IMPLEMENTATION_SUMMARY.md`
5.  `QUICK_REFERENCE.md`
6.  `MIGRATION_GUIDE.md`

**Your Task:**
Merge the relevant deployment steps from all files markdown into `README.md` to create a single source of truth, then update the content based on the following rules:

1.  **Merge & Consolidate:** Move the deployment instructions into the Guidelines file. If any files becomes redundant after this, mark it for deletion.
2.  **Remove Legacy Secrets Logic:**
    * Identify any sections discussing **External Secrets Operator**, **HashiCorp Vault**, or **Key Vault**.
    * **Delete these sections entirely.** We are no longer using the External Secrets Operator pattern.
3.  **Standardize:** Ensure the remaining deployment steps assume the use of **AWS Secrets Manager** (native/CSI driver) instead of the old Vault setup.
4.  **Cleanup:** Fix any broken links or table of contents entries resulting from these removals.

Output the updated content for the merged file.I need to refactor the project documentation to reflect our architectural changes.

---
# Prompt: 
# **Claude Code Prompt: GitOps Implementation with Helm + Kustomize + ArgoCD**

## **Context**
You are an expert Kubernetes and GitOps engineer. I need you to generate a complete GitOps implementation using ArgoCD, Helm charts, and Kustomize following App of Apps pattern. The system should support multiple microservices with Linkerd mTLS integration and AWS Secrets Manager for database connections.

## **Requirements**

### **1. Project Structure**
Generate this exact directory structure:
```
gitops/
├── bootstrap/
│   ├── install.sh
│   ├── argocd-namespace.yaml
│   └── root-app.yaml
├── infrastructure/
│   ├── secrets-store-csi/
│   ├── traefik/
│   ├── linkerd/
│   ├── reloader/
│   └── argocd/
├── applications/
│   ├── infrastructure/
│   │   ├── 00-project.yaml
│   │   ├── argocd-self-managed.yaml
│   │   ├── linkerd.yaml
│   │   ├── traefik.yaml
│   │   ├── secrets-store-csi.yaml
│   │   └── reloader.yaml
│   ├── app-of-apps-{env}.yaml
│   ├── dev/
│   ├── staging/
│   └── production/
├── charts/
│   └── vsf-miniapp/
│       ├── templates/
│       ├── values.yaml
│       └── ci/
└── .github/workflows/
```

### **2. Core Requirements**
- **App of Apps pattern**: Root application that manages all other applications
- **Multi-service microservice**: `vsf-miniapp` containing serviceA, serviceB, etc.
- **Linkerd mTLS**: Each service must have proper Linkerd sidecar injection with mTLS enabled
- **AWS Secrets Manager**: Database credentials must come from AWS Secrets Manager via CSI driver
- **Helm + Kustomize**: Use Helm charts for templating, Kustomize for environment overlays

### **3. Specific Implementation Requests**

#### **3.1 Helm Chart Strategy**
- Should we create separate Helm charts for each programming language (Java, Node.js, Python) or use a base chart with language-specific overlays?
- How to structure the chart to support both language-specific configurations and shared base configurations?
- Show the optimal approach with examples.

#### **3.2 Linkerd Integration**
- Generate complete Linkerd mTLS setup configuration
- Show how to inject Linkerd into each microservice deployment
- Include certificate management and security policies
- Demonstrate proper annotation for database ports exclusion

#### **3.3 AWS Secrets Manager Integration**
- Create complete AWS Secrets Manager CSI driver setup
- Show how to mount database secrets into containers
- Include IAM role/service account configuration for EKS
- Provide secret rotation strategy

#### **3.4 Application Structure**
- Generate complete `app-of-apps-{env}.yaml` files for dev, staging, production
- Create service-specific Application manifests for serviceA and serviceB
- Show environment-specific value overrides using Kustomize patches
- Demonstrate namespace segregation per service per environment

#### **3.5 Microservice Organization**
- How to structure multiple services under `my-microservice`:
  - Should each service have its own Application manifest?
  - How to share common configurations across services?
  - How to handle service dependencies and ordering?

### **4. Output Format**
Generate complete, production-ready YAML/configuration files for:
1. **Bootstrap files** (install.sh, root-app.yaml)
2. **Infrastructure components** (Linkerd with mTLS, Secrets Manager CSI, Traefik)
3. **Application manifests** for App of Apps pattern
4. **Helm chart structure** for multi-language support
5. **Kustomize overlays** for environment differentiation
6. **CI/CD workflow** examples for GitHub Actions

### **5. Key Considerations**
- **Security**: mTLS between all services, encrypted secrets
- **Scalability**: Easy to add new services or new environments
- **Maintainability**: Clear separation of concerns, minimal duplication
- **GitOps principles**: Everything as code, declarative configuration
- **Best practices**: Follow Kubernetes and CNCF best practices

## **Expected Output**
Provide complete file contents for the most critical files, and explain the architecture decisions. Focus on:
1. How Helm and Kustomize work together in this setup
2. How Linkerd mTLS is implemented per service
3. How database connections are secured with AWS Secrets Manager
4. How the App of Apps pattern manages the entire deployment

## **Constraints**
- Use ArgoCD Application CRDs
- Support EKS or any Kubernetes 1.24+
- Assume AWS as cloud provider
- Include error handling and validation where appropriate
- Include comments explaining key configuration decisions

**Generate the complete implementation following these specifications.**