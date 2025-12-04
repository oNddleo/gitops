# Linkerd Base Configuration

This directory contains the base Kustomize configuration for Linkerd.

## Components

-   `namespace.yaml`: Defines the `linkerd` namespace.
-   `linkerd-issuer.yaml`: Configures `cert-manager` resources (`Issuer`, `Certificate`) to automatically generate and rotate Linkerd's Trust Anchor and Identity certificates.

## Certificate Management

Certificates are managed by `cert-manager` (must be installed in the cluster).

1.  A **Self-Signed Issuer** bootstraps the root of trust.
2.  A **Trust Anchor Certificate** (`linkerd-trust-anchor`) is generated.
3.  An **Identity Issuer Certificate** (`linkerd-identity-issuer`) is generated, signed by the Trust Anchor.

The `linkerd-identity-trust-roots` ConfigMap is automatically injected with the Trust Anchor bundle via `cert-manager` annotations.
