# Kubernetes Local Cluster Design and Security Architecture

## Overview and Demonstration Goals

This solution demonstrates how a production-aligned Kubernetes cluster can be securely operated using Kubernetes-native primitives while remaining suitable for local development and evaluation.

The cluster is intentionally built using:
- A real Kubernetes control plane (kubeadm)
- Certificate-based user authentication
- Least-privilege, namespace-scoped RBAC
- Application deployment by a non-admin user using Helm
- Standard ingress, service, and TLS patterns

The primary goal of the demonstration is to show that a non-privileged user can deploy and manage an application without cluster-admin access, while still using realistic tooling and workflows. The focus is deliberately placed on **security boundaries, operational correctness, and architectural clarity**, rather than application complexity.

The design emphasizes:
- Stability and predictable behavior
- Production-aligned architecture
- Strong security posture through least privilege
- Clear separation of concerns between cluster administration and application deployment
- Explicit, explainable trade-offs over hidden abstractions or convenience tooling

---

## Scope and Companion Documentation

This document focuses on *design decisions, architecture, and tradeoffs*.

Detailed, step-by-step instructions for:
- Cluster installation
- User creation commands
- NGINX deployment commands

are intentionally documented separately in the **README** at the top level of the repo, to:
- Keep this document concise and design-focused
- Avoid duplicating procedural instructions
- Improve readability for reviewers

Together, the two documents provide both architectural context and operational detail.

---

## Limitations and Trade-offs of the User and Cluster Management Model

While certificate-based authentication and manual RBAC provide strong security guarantees, this approach has several limitations:

- **Operational overhead**: Managing client certificates, CSRs, and kubeconfigs does not scale well for large teams.
- **Certificate lifecycle management**: Certificates must be rotated, revoked, and redistributed manually unless integrated with external identity systems.
- **Limited audit context**: Native certificate auth lacks rich identity metadata compared to OIDC-based providers.
- **Not ideal for dynamic environments**: Short-lived users, contractors, or ephemeral access are harder to manage.
- **Local cluster constraints**: kubeadm-based clusters require more hands-on maintenance compared to managed Kubernetes services.

In production environments, these issues are typically addressed by integrating Kubernetes with:
- OIDC identity providers
- Centralized IAM systems
- Automated certificate and access lifecycle tooling

For this exercise, the simpler model was chosen intentionally to demonstrate Kubernetes-native security primitives without external dependencies.

---

## Virtualization Platform Selection

This design uses a traditional VM setup with:
- Explicit CPU allocation per node
- Explicit memory allocation per node

This decision prioritized **cluster stability and predictable behavior** over convenience, which is critical for Kubernetes control-plane components such as `etcd`, `kube-apiserver`, and `kube-scheduler`.

It was specifically tested on Parallels for Mac. 

---

## Cluster Topology

The cluster uses a simple but production-representative topology:

- **1 Control Plane Node**
- **2 Worker Nodes**

This layout mirrors common real-world deployments while remaining lightweight enough for local use.

Resources were allocated above minimal defaults to prevent contention between:
- kubelet
- etcd
- networking components
- system daemons

This avoids performance-induced instability that can mask real configuration issues.

---

## Kubernetes Distribution and Installation

### kubeadm

The cluster was installed using **kubeadm**, rather than Minikube, Kind, or other abstractions.

Rationale:
- Uses a real Kubernetes control plane
- Deploys static pods, PKI, and standard networking patterns
- Aligns with production operational models
- Meets requirements for using “real” Kubernetes

### Kubernetes Version

- **Kubernetes v1.29** was selected for:
  - Stability
  - Availability of tooling
  - Ease of installation

---

## Container Runtime Choice

**containerd** was selected as the container runtime.

Reasons:
- Kubernetes default runtime
- dockershim has been removed
- Simpler configuration and maintenance
- Matches upstream kubeadm expectations

The kubelet was explicitly configured to use the containerd socket to avoid ambiguity.

---

## Cgroup Driver Alignment

A key stability decision was aligning cgroup drivers:

- **systemd** is used for both:
  - kubelet
  - containerd

This prevents subtle resource-management issues that can lead to:
- Pod restarts
- Node instability
- Difficult-to-debug scheduling behavior

This configuration follows Kubernetes best practices.

---

## Swap Management

Swap was fully disabled at both the OS and kubelet levels.

Actions taken:
- Swap disabled at runtime
- Swap entries commented out in `/etc/fstab` to persist across reboots

Rationale:
- Kubernetes requires swap to be disabled
- Ensures predictable scheduling and memory management
- Avoids kubelet startup failures and `NotReady` node states

---

## Networking (CNI) Selection

**Calico** was chosen as the Container Network Interface (CNI).

Reasons:
- Mature and production-proven
- Widely adopted
- Supports NetworkPolicy
- Integrates cleanly with kubeadm

Calico was deployed early in the bootstrap process to ensure networking was available before scheduling workloads.

---

## User Authentication and Authorization Model

### Authentication

A non-admin Kubernetes user (`nginx-user`) was created using **certificate-based authentication**.

Process:
1. Client private key generated locally
2. Certificate Signing Request (CSR) created
3. CSR submitted to Kubernetes
4. CSR approved by an admin
5. Signed certificate embedded into a dedicated kubeconfig

This uses Kubernetes-native authentication mechanisms without shortcuts.

### Authorization (RBAC)

Authorization is handled entirely via **RBAC**, cleanly separated from authentication.

Key principles:
- No impersonation
- No service-account shortcuts
- Explicit permissions only

---

## Kubeconfig Separation

Separate kubeconfig files are used for:
- Cluster administration
- Application deployment (nginx-user)

Benefits:
- Clear identity boundaries
- No accidental privilege escalation
- Easy demonstration of permission enforcement

All tooling (`kubectl`, `helm`) explicitly references the appropriate kubeconfig.

---

## RBAC and Security Model

Least privilege is enforced by design:

- Namespace-scoped Role
- RoleBinding to a non-admin user
- Permissions limited to required resources only

This mirrors real-world multi-tenant clusters and avoids the common anti-pattern of deploying applications as `cluster-admin`.

---

## Application Deployment as a Non-Admin User

The NGINX application was deployed while authenticated as the non-admin user.

This validates:
- Authentication works correctly
- RBAC rules are enforced
- Separation of duties between platform and application teams

This was a deliberate design choice to demonstrate secure operations, not just cluster functionality.

---

## Application Definition

The application is intentionally minimal:

- Single **NGINX Deployment**
- Static HTML content via **ConfigMap**
- **ClusterIP Service**

The focus is on:
- Deployment flow
- Access control
- Security boundaries

Not application complexity.

---

## Deployment Mechanism (Helm)

**Helm** was selected instead of full GitOps tooling (Argo CD / Flux).

Rationale:
- Lower operational complexity
- Clear demonstration that non-admin users can deploy workloads
- Avoids introducing additional controllers and cluster-wide permissions

Helm still represents a realistic production workflow and can later be layered under GitOps if required.

---

## RBAC for Helm-Based Deployments

RBAC permissions explicitly include everything Helm requires:

- deployments
- pods
- services
- configmaps
- secrets
- ingresses

Both read and write verbs are granted because Helm performs read-before-write reconciliation.

All permissions are strictly **namespace-scoped**.

---

## Ingress and Traffic Management

### Ingress Controller

The **ingress-nginx** controller is installed explicitly.

Ingress resources require a controller to function; they do not operate on their own.

### Traffic Flow

Standard Kubernetes traffic flow is used:

```
Ingress → Service → Pod
```

The Service abstraction is retained even when using Ingress, as Ingress always routes to Services, not directly to Pods.

---

## TLS and Certificate Management

**cert-manager** is used to automate TLS certificate lifecycle management.

Because the cluster runs in a private, non-public environment:
- An internal CA issuer is used
- Let’s Encrypt is not required

Certificates are issued via Ingress annotations, ensuring:
- Application users do not handle private keys
- Certificate policies are centrally managed

Helm values allow easy replacement with:
- Public ACME
- Enterprise PKI

---

## MetalLB and Load Balancing

**MetalLB** was installed to provide a cloud-like `LoadBalancer` experience on bare metal.

Design choices:
- Single IP address (`192.168.99.2`) for simplicity
- Stable external access
- Avoids NodePort URLs in demos

Trade-offs:
- Additional infrastructure component
- Requires Layer 2 network adjacency

NodePort remains a valid and supported alternative.

---

## Networking Constraints in Virtualized Environments

VM networking mode directly affects reachability:

- **Bridged networking (not configured for Parallels VMs)**
  - MetalLB Layer 2 advertisements reach the host
- **NAT networking**
  - ARP-based LoadBalancer IPs are blocked

This is an environmental constraint, not a Kubernetes or MetalLB misconfiguration.

---

## Validation and Observability

Cluster health was validated using:
- Node conditions
- Pod readiness across system and application namespaces
- Event inspection for scheduling and restarts

Validation was performed before application deployment to ensure a stable baseline.

---

## Overall Architectural Principles

- Least privilege by default
- Separation of duties
- Production-aligned patterns
- Explicit trade-offs over unnecessary complexity
- Security demonstrated through behavior, not assumptions

---

## Feature Scope and Level-Appropriate Choices

For the scope and level of this implementation, the following deliberate choices were made:

- **Focused feature set**: Emphasis on secure user access and deployment rather than application complexity.
- **Helm over GitOps**: Demonstrates realistic workflows without introducing additional controllers or cluster-wide permissions.
- **Single application**: NGINX was chosen to keep attention on access control and deployment mechanics.
- **Namespace-scoped RBAC**: Aligns with real multi-tenant patterns while remaining understandable.
- **Internal TLS issuer**: Avoids external dependencies while still demonstrating certificate automation.

These choices balance realism with clarity, ensuring the core concepts are demonstrated cleanly and can be evaluated without unnecessary complexity.

---

## Summary

This design intentionally favors correctness, clarity, and security over shortcuts. While the environment is local, the architecture mirrors real-world Kubernetes deployments, making it suitable for demonstrations, evaluations, and security-focused discussions.

This model also highlights why managing access, identity, and lifecycle at scale becomes challenging, and why centralized access platforms are commonly introduced in production environments.
