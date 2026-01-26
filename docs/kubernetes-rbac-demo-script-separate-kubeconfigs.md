# Kubernetes RBAC Demo Script
## Teleport Take-Home Challenge – Live Demo Guide (Separate kubeconfigs)

This document is a **live demo script** you can follow during the interview.
It assumes **two separate kubeconfig files**:
- One for cluster admin
- One for the application user (e.g. `nginx-user.kubeconfig`)

This is intentional and reinforces access boundaries.

---

## Demo Principles

- Prefer explicit identity over convenience
- Never “switch hats” implicitly
- Validate access before touching workloads
- Narrate intent, not mechanics

---

## Pre-Demo Setup (before the call)

Have ready:

- Kubernetes cluster running
- Repo already cloned
- Admin kubeconfig (e.g. `admin.kubeconfig`)
- User kubeconfig (e.g. `nginx-user.kubeconfig`)
- Browser tab ready for Nginx
- Clean terminal window

Do **not** build the cluster live.

---

## 1. Orient the Audience (30 seconds)

### Talking Point

> “I’m using two separate kubeconfig files — one for admin operations and one for the application user.  
> This makes the trust boundary explicit and avoids accidentally acting with elevated privileges.”

### Command

```bash
kubectl get nodes
```

Explain briefly:
- This confirms admin access exists
- We won’t use it again during the demo

---

## 2. Establish User Identity (1 minute)

### Talking Point

> “From here on, everything is done as the application user.”

### Commands

```bash
kubectl config view --minify kubectl auth can-i '*' '*' --all-namespaces --kubeconfig nginx-user.kubeconfig
```

Then:

```bash
kubectl auth can-i '*' '*' --all-namespaces --kubeconfig nginx-user.kubeconfig
```

Explain:
- Identity is certificate-based
- User is **not** cluster-admin
- This is always the first validation step when debugging access

---

## 3. Prove Namespace-Scoped Access (1–2 minutes)

### Talking Point

> “Access is scoped to a namespace, which defines the blast radius.”

### Commands

```bash
kubectl auth can-i create deployments -n nginx-demo --kubeconfig nginx-user.kubeconfig
kubectl auth can-i create deployments -n kube-system --kubeconfig nginx-user.kubeconfig
```

Explain:
- Allowed in application namespace
- Denied in system namespaces
- Denials here are *expected and healthy*

---

## 4. Deploy the Application as the User (2–3 minutes)

### Talking Point

> “Now I’ll deploy the application using the restricted identity.”

### Commands

```bash
kubectl get ns --kubeconfig nginx-user.kubeconfig
ubectl apply -f nginx/ --kubeconfig nginx-user.kubeconfig
```

Then:

```bash
kubectl get pods --kubeconfig nginx-user.kubeconfig
kubectl get svc --kubeconfig nginx-user.kubeconfig
```

Explain lightly:
- The user can deploy
- The user can observe
- The user stays within their boundary

Avoid explaining YAML unless asked.

---

## 5. Show Application Access (1 minute)

### Talking Point

> “From the user’s perspective, this is the full workflow — deploy, observe, and access.”

### Commands

```bash
kubectl get ingress --kubeconfig nginx-user.kubeconfig
```

Note, MetalLB assigns IPs to LoadBalancer services. In this design, the application service is intentionally ClusterIP, and the external IP is owned by the ingress controller instead.

```bash
kubectl get svc -n ingress-nginx --kubeconfig nginx-user.kubeconfig
```

Now:
- Load the Nginx page
- Pause briefly

```bash
curl -L nginx.local
```

---

## 6. Demonstrate a Controlled Failure (Optional but Strong)

### Talking Point

> “This is a realistic failure scenario.”

### Command

```bash
kubectl get nodes --kubeconfig nginx-user.kubeconfig
```

Explain:
- Access denied is expected
- The fix is not widening permissions
- The fix is understanding intent and scope

---

## 7. Transition to Tradeoffs (1–2 minutes)

### Talking Point

> “This model works well at small scale, but it has operational limits.”

Cover verbally:
- Manual certificate lifecycle management
- RBAC complexity as users grow
- Kubeconfig distribution risk
- Limited audit visibility by default

Bridge:

> “These are exactly the issues that appear once Kubernetes access grows beyond a small team.”

---

## 8. Clean Close

### Talking Point

> “That’s the user lifecycle I wanted to demonstrate — identity, access, deployment, and enforced boundaries.”

---

End of demo.
