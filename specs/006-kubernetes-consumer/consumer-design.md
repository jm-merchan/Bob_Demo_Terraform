# Consumer Design: 006-kubernetes-app

**Branch**: feat/006-kubernetes-consumer
**Date**: 2025-07-15
**Status**: Draft
**Provider**: hashicorp/kubernetes ~> 3.2 · hashicorp/aws ~> 6.0
**Terraform**: >= 1.14
**HCP Terraform Org**: jose-merchan

---

## Table of Contents

1. [Purpose & Requirements](#1-purpose--requirements)
2. [Module Selection & Architecture](#2-module-selection--architecture)
3. [Module Wiring](#3-module-wiring)
4. [Security Controls](#4-security-controls)
5. [Implementation Checklist](#5-implementation-checklist)
6. [Open Questions](#6-open-questions)

---

## 1. Purpose & Requirements

This deployment provisions the `backend` application workload into an existing Amazon EKS cluster managed by the `eks-infra-vcs` workspace. It targets teams that need a reproducible, security-hardened Kubernetes deployment without authoring raw manifests: the deployment creates a dedicated namespace, a private-registry pull secret for IBM ICR (`de.icr.io`), a replicated pod controller, and a LoadBalancer service that exposes the application via a Classic ELB. Cluster credentials are read from the `eks-infra-vcs` remote state, keeping this deployment decoupled from the EKS provisioning lifecycle.

**Scope boundary**: This deployment does NOT provision EKS clusters, VPCs, IAM roles, Ingress resources, TLS certificates, AWS Load Balancer Controller, DNS records, or HPA/KEDA scaling controllers. It does NOT manage any resources in the `kube-system`, `kube-public`, or `kube-node-lease` namespaces. Cluster connectivity and AWS dynamic credentials are assumed to be pre-configured by the `eks-infra-vcs` workspace and the global `aws-dynamic-provider-credentials` variable set.

### Requirements

**Functional requirements** — what the deployment must provision (from Phase 1 clarification):

- The deployment MUST create the Kubernetes namespace `bob-demo-app` before any workload resources are applied, so the module can target a pre-existing namespace as required by its interface contract.
- The deployment MUST deploy the container image `de.icr.io/san-clients/backend:latest` with 2 replicas into the `bob-demo-app` namespace, using registry pull credentials sourced from sensitive HCP Terraform workspace variables.
- The deployment MUST expose the application pods via a `LoadBalancer` service (Classic ELB, no annotations), overriding the module's `ClusterIP` default.
- Registry credentials (server, username, password) MUST be supplied as sensitive workspace variables — never hardcoded — and MUST NOT appear in Terraform state after apply.
- Kubernetes provider authentication MUST use `aws eks get-token` via the `exec` block, reading cluster coordinates (`endpoint`, `CA cert`, `cluster name`, `region`) from the `eks-infra-vcs` remote state.
- The new `k8s-app-demo-bob` workspace MUST be registered as a remote state consumer of `eks-infra-vcs` before the first plan runs.

**Non-functional requirements** — constraints that bound the design:

- Terraform version MUST be `>= 1.14` (write-only variable support; kubernetes module floor).
- HCP Terraform workspace execution mode MUST be `remote`; dynamic AWS credentials are injected by the global `aws-dynamic-provider-credentials` variable set — no static IAM keys.
- Kubernetes provider version MUST be `~> 3.2` (`>= 3.2.1` for `data_wo` bug fix).
- AWS provider version MUST be `~> 6.0`, consistent with existing sandbox workspaces.
- `client.authentication.k8s.io/v1` MUST be used in the `exec` block — `v1beta1` was removed in Kubernetes 1.29; the live cluster runs 1.33 (confirmed from `eks-infra-vcs` live state).
- Provider `default_tags` MUST propagate `ManagedBy`, `Environment`, `Project`, and `Owner` to all AWS-managed resources.
- All code MUST pass `terraform fmt -check`, `terraform validate`, `tflint`, and `trivy config .` with no Critical or High findings before merge.

---

## 2. Module Selection & Architecture

### Architectural Decisions

**Primary module — `kubernetes-app-deploy`**: The `app.terraform.io/jose-merchan/app-deploy/kubernetes` private registry module is the sole infrastructure module in this composition.
*Rationale*: Research finding Q1 (research-module-registry.md) confirms this is the only Kubernetes-provider module scoped for application deployment in the `jose-merchan` PMR. It encapsulates the pull secret (`data_wo`), Deployment, and Service as a single versioned unit, eliminating the need for raw resource authoring in the consumer. The constitution §1.1 prohibits raw infrastructure resources — the module is the correct abstraction.
*Rejected*: Writing raw `kubernetes_deployment_v1`, `kubernetes_service_v1`, `kubernetes_secret_v1` resources in the consumer — constitution §1.1 prohibits this; the module exists precisely to prevent it.

**`exec` block for Kubernetes provider auth**: The `kubernetes` provider is configured with an `exec` block calling `aws eks get-token` rather than `data.aws_eks_cluster_auth`.
*Rationale*: Research finding Q4 (research-provider-config.md §2) shows that `data.aws_eks_cluster_auth` tokens expire after 15 minutes — applies with many resources will fail with HTTP 401. The `exec` block re-invokes `aws eks get-token` before each Kubernetes API call, making it safe for long-running applies. `api_version = "client.authentication.k8s.io/v1"` is mandatory for Kubernetes ≥ 1.29; the live cluster is 1.33.
*Rejected*: `data.aws_eks_cluster_auth` — 15-minute token expiry risk; `v1beta1` api_version — removed in Kubernetes 1.29.

**Remote state for cluster coordinates**: Cluster endpoint, CA certificate, cluster name, and AWS region are read from `data "terraform_remote_state" "eks_infra"` targeting `eks-infra-vcs`, not from hardcoded variables or a `data "aws_eks_cluster"` data source.
*Rationale*: Research finding Q2 (research-state-wiring.md) confirms the canonical org pattern: `eks-vault-vcs` uses `infra_workspace = "eks-infra-vcs"` to parameterise the remote state lookup. Reading from settled remote state avoids the same-workspace provider initialisation anti-pattern (design.md §2 two-state boundary decision). Live outputs confirmed: `cluster_endpoint`, `cluster_certificate_authority_data`, `cluster_name`, `aws_region` are all available.
*Rejected*: Hardcoding `cluster_endpoint` as a workspace variable — creates drift when the cluster is rebuilt; `data "aws_eks_cluster"` — adds a redundant API call and extra IAM permission when the data already exists in remote state.

**`kubernetes_namespace` as constitution-deviated glue resource**: The `bob-demo-app` namespace is created via a `kubernetes_namespace` raw resource block, not via a PMR module.
*Rationale*: Research finding Q3 (research-provider-config.md §4) confirms zero Kubernetes-provider modules exist in the `jose-merchan` PMR (16 modules, all AWS/Google). The module's scope boundary (design.md §1) explicitly states it does NOT provision namespaces. Pre-creating out-of-band via `kubectl` violates IaC principles. A `kubernetes_namespace` is a thin metadata object — the spirit of the glue resource exception applies. A `[CONSTITUTION DEVIATION]` comment is required per constitution §8.2.
*Rejected*: Pre-creating with `kubectl` — no lifecycle management; creating a dedicated PMR module — over-engineered for a single metadata resource with no Kubernetes PMR modules in the org.

**`aws_region` sourced from consumer variable for provider block**: The `provider "aws"` block uses `var.aws_region` (default `eu-central-1`), not `data.terraform_remote_state.eks_infra.outputs.aws_region`.
*Rationale*: Research finding Q4 (research-provider-config.md §3) establishes that provider blocks are evaluated before data sources in the same configuration — referencing a data source in a provider block causes provider initialisation failures. `var.aws_region` with a hardcoded default of `eu-central-1` (confirmed live from `eks-infra-vcs` state) is the correct pattern. The `kubernetes` provider's `exec` args use `local.aws_region` which may reference either source.
*Rejected*: `region = data.terraform_remote_state.eks_infra.outputs.aws_region` in provider block — fails at provider init; hardcoding `"eu-central-1"` string literal — works but obscures intent and breaks if region changes.

### Module Inventory

| Module | Registry Source | Version | Purpose | Conditional | Key Inputs | Key Outputs |
|--------|----------------|---------|---------|-------------|------------|-------------|
| `app_deploy` | `app.terraform.io/jose-merchan/app-deploy/kubernetes` | `~> 0.1` | Deploys pull secret, Deployment (2 replicas), and LoadBalancer Service for the backend app | always | `app_name`, `namespace`, `image`, `replicas`, `service_type`, `registry_server`, `registry_username`, `registry_password` | `deployment_name`, `service_name`, `service_cluster_ip`, `secret_name` |

### Glue Resources

| Resource Type | Logical Name | Purpose | Depends On |
|---------------|-------------|---------|------------|
| `kubernetes_namespace` | `app` | Creates the `bob-demo-app` namespace before the module call; the module requires a pre-existing namespace. `[CONSTITUTION DEVIATION]` — see §6 Open Questions for full justification. | `data.terraform_remote_state.eks_infra` (provider must be initialised) |

### Workspace Configuration

| Setting | Value | Notes |
|---------|-------|-------|
| Organization | `jose-merchan` | HCP Terraform organization |
| Project | `Default Project` (`prj-PmbVsprg8DoogHW7`) | Matches `eks-app-vcs` peer workspace |
| Workspace | `k8s-app-demo-bob` | Target workspace for this consumer |
| Execution Mode | `remote` | HCP Terraform managed; matches all peer workspaces |
| Terraform Version | `~> 1.15.0` | Matches `eks-app-vcs` (same-tier peer); satisfies module `>= 1.14` floor |
| Auto-apply | `true` | Matches `eks-app-vcs` peer |
| VCS Connection | None (API-driven) | Runs triggered via API or UI |
| Variable Sets | `aws-dynamic-provider-credentials` (global — no explicit attachment needed; `global=true` confirmed live) | Injects `TFC_AWS_PROVIDER_AUTH` and `TFC_AWS_RUN_ROLE_ARN` for dynamic credential injection |
| Sensitive Workspace Variables | `registry_password` (sensitive), `registry_username`, `registry_server` | IBM ICR credentials; set as `category=terraform` workspace variables |
| Terraform Variable | `infra_workspace = "eks-infra-vcs"` | Parameterises the remote state backend config per `eks-vault-vcs` org pattern |
| Remote State Consumers | Must POST `k8s-app-demo-bob` workspace ID to `eks-infra-vcs` (`ws-fynCV5VvhkpRF7s3`) remote-state-consumers — `global-remote-state=false` on `eks-infra-vcs` | Post-workspace-creation gate before first plan |

---

## 3. Module Wiring

### Wiring Diagram

```
eks-infra-vcs remote state
  └── outputs.cluster_endpoint          ──→ local.cluster_endpoint
  └── outputs.cluster_certificate_authority_data (base64decode) ──→ local.cluster_ca_certificate
  └── outputs.cluster_name             ──→ local.cluster_name
  └── outputs.aws_region               ──→ local.aws_region

var.aws_region (default "eu-central-1") ──→ provider "aws" { region }

local.cluster_endpoint      ──→ provider "kubernetes" { host }
local.cluster_ca_certificate──→ provider "kubernetes" { cluster_ca_certificate }
local.cluster_name          ──→ provider "kubernetes" { exec { args --cluster-name } }
local.aws_region            ──→ provider "kubernetes" { exec { args --region } }

kubernetes_namespace.app.metadata[0].name ──→ module.app_deploy [ namespace ]
var.app_name                ──→ module.app_deploy [ app_name ]
var.image                   ──→ module.app_deploy [ image ]
var.replicas                ──→ module.app_deploy [ replicas ]
var.registry_server         ──→ module.app_deploy [ registry_server ]
var.registry_username       ──→ module.app_deploy [ registry_username ]
var.registry_password       ──→ module.app_deploy [ registry_password ]
"LoadBalancer" (literal)    ──→ module.app_deploy [ service_type ]   [SECURITY OVERRIDE]
```

### Wiring Table

| Source | Output / Value | Target | Input | Type | Transformation |
|--------|---------------|--------|-------|------|----------------|
| `data.terraform_remote_state.eks_infra` | `outputs.cluster_endpoint` | `local` | `cluster_endpoint` | `string` | direct → `local.cluster_endpoint` |
| `data.terraform_remote_state.eks_infra` | `outputs.cluster_certificate_authority_data` | `local` | `cluster_ca_certificate` | `string` | `base64decode()` — provider expects raw PEM bytes |
| `data.terraform_remote_state.eks_infra` | `outputs.cluster_name` | `local` | `cluster_name` | `string` | direct → `local.cluster_name` |
| `data.terraform_remote_state.eks_infra` | `outputs.aws_region` | `local` | `aws_region` | `string` | direct → `local.aws_region` |
| `local.cluster_endpoint` | -- | `provider "kubernetes"` | `host` | `string` | direct |
| `local.cluster_ca_certificate` | -- | `provider "kubernetes"` | `cluster_ca_certificate` | `string` | direct (already decoded) |
| `local.cluster_name` | -- | `provider "kubernetes"` | `exec.args[--cluster-name]` | `string` | direct |
| `local.aws_region` | -- | `provider "kubernetes"` | `exec.args[--region]` | `string` | direct |
| `var.aws_region` | -- | `provider "aws"` | `region` | `string` | direct |
| `kubernetes_namespace.app` | `metadata[0].name` | `module.app_deploy` | `namespace` | `string` | direct — creates implicit dependency ordering |
| `var.app_name` | -- | `module.app_deploy` | `app_name` | `string` | direct |
| `var.image` | -- | `module.app_deploy` | `image` | `string` | direct |
| `var.replicas` | -- | `module.app_deploy` | `replicas` | `number` | direct |
| `var.registry_server` | -- | `module.app_deploy` | `registry_server` | `string` | direct |
| `var.registry_username` | -- | `module.app_deploy` | `registry_username` | `string` | direct |
| `var.registry_password` | -- | `module.app_deploy` | `registry_password` | `string` | direct (sensitive) |
| `"LoadBalancer"` (literal) | -- | `module.app_deploy` | `service_type` | `string` | `[SECURITY OVERRIDE]` — hardcoded override of module default `ClusterIP` |

### Provider Configuration

```hcl
# providers.tf

# AWS provider — dynamic credentials injected by global aws-dynamic-provider-credentials varset.
# var.aws_region is used (not data source) because provider blocks are evaluated before
# data sources; using a data source reference here causes provider initialisation failure.
provider "aws" {
  region = var.aws_region

  # Dynamic credentials via HCP Terraform:
  # TFC_AWS_PROVIDER_AUTH and TFC_AWS_RUN_ROLE_ARN are injected by the global
  # aws-dynamic-provider-credentials varset — no static keys, no assume_role {} needed.

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = var.owner
    }
  }
}

# Kubernetes provider — connects to the EKS cluster using coordinates from eks-infra-vcs state.
# exec block used over data.aws_eks_cluster_auth: tokens from aws_eks_cluster_auth expire
# after 15 minutes; exec block re-invokes aws eks get-token before each API call, making
# it safe for long-running applies. api_version v1 is mandatory — v1beta1 removed in K8s 1.29;
# live cluster runs 1.33.
# Two-state boundary honoured: provider reads from settled remote state, not same-workspace
# computed resources (official kubernetes provider WARNING — research-provider-config.md §2).
provider "kubernetes" {
  host                   = local.cluster_endpoint
  cluster_ca_certificate = local.cluster_ca_certificate

  exec {
    api_version = "client.authentication.k8s.io/v1"
    command     = "aws"
    args = [
      "eks", "get-token",
      "--cluster-name", local.cluster_name,
      "--region", var.aws_region,
    ]
  }
}
```

### Variables

| Variable | Type | Required | Default | Validation | Sensitive | Description |
|----------|------|----------|---------|------------|-----------|-------------|
| `aws_region` | `string` | No | `"eu-central-1"` | `can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))` | No | AWS region. Must match the region of the eks-infra-vcs workspace. Used in provider block (cannot reference data sources in provider config). |
| `project_name` | `string` | No | `"k8s-app-demo"` | -- | No | Project name applied to `default_tags` `Project` key and workspace labelling. |
| `environment` | `string` | No | `"sandbox"` | `contains(["dev", "staging", "prod", "sandbox"], var.environment)` | No | Deployment environment identifier applied to all resource tags. |
| `owner` | `string` | No | `"platform-team"` | -- | No | Owner value for `default_tags` `Owner` key; used for cost allocation reporting. |
| `infra_workspace` | `string` | No | `"eks-infra-vcs"` | `length(var.infra_workspace) > 0` | No | Name of the HCP Terraform workspace that exposes EKS cluster outputs via remote state. Follows the `eks-vault-vcs` org pattern. |
| `namespace` | `string` | No | `"bob-demo-app"` | `can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.namespace))` | No | Kubernetes namespace to create and deploy the application into. Must be a valid RFC 1123 DNS label. |
| `app_name` | `string` | No | `"backend"` | `length(var.app_name) >= 1 && length(var.app_name) <= 63 && can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.app_name))` | No | Application name. Used as base for all Kubernetes resource names and pod-selector labels. RFC 1123 DNS label. |
| `image` | `string` | No | `"de.icr.io/san-clients/backend:latest"` | `length(var.image) > 0` | No | Full OCI image reference including registry and tag. |
| `replicas` | `number` | No | `2` | `var.replicas >= 1 && var.replicas <= 100` | No | Number of pod replicas. Must be 1–100. |
| `registry_server` | `string` | Yes | -- | `length(var.registry_server) > 0` | No | Hostname of the private container registry (e.g., `de.icr.io`). Set as workspace variable. |
| `registry_username` | `string` | Yes | -- | `length(var.registry_username) > 0` | No | Registry authentication username (e.g., `iamapikey` for IBM ICR). Set as workspace variable. |
| `registry_password` | `string` | Yes | -- | `length(var.registry_password) > 0` | **Yes** | Registry authentication password or API key. Written via module `data_wo` — never stored in state. Set as **sensitive** workspace variable. |

### Outputs

| Output | Type | Source | Description |
|--------|------|--------|-------------|
| `namespace` | `string` | `kubernetes_namespace.app.metadata[0].name` | Name of the created Kubernetes namespace. |
| `deployment_name` | `string` | `module.app_deploy.deployment_name` | Name of the `kubernetes_deployment_v1` resource. Used by CI/CD pipelines for `kubectl rollout status`. |
| `service_name` | `string` | `module.app_deploy.service_name` | Name of the `kubernetes_service_v1` LoadBalancer service. |
| `service_cluster_ip` | `string` | `module.app_deploy.service_cluster_ip` | ClusterIP address assigned to the service. Value is plan-unknown until apply. |
| `secret_name` | `string` | `module.app_deploy.secret_name` | Name of the registry pull secret. Allows reference in additional deployments in the same namespace. |

---

## 4. Security Controls

| Control | Enforcement | Module Config | Reference |
|---------|-------------|---------------|-----------|
| Encryption at rest | Module enforces write-only registry credential storage via `kubernetes_secret_v1.data_wo` — credentials never appear in Terraform state. Kubernetes etcd encryption is an EKS control-plane concern managed by `eks-infra-vcs` (KMS CMK). | `module.app_deploy`: `data_wo` attribute; `registry_password` is `sensitive = true` workspace variable | AWS Well-Architected SEC08-BP01; CIS Kubernetes Benchmark v1.8.0 §5.4.1 |
| Encryption in transit | EKS API server enforces TLS 1.2+ on all Kubernetes API traffic (AWS-managed, cannot be disabled). Kubernetes provider `exec` block token is short-lived and scoped to the cluster. | `provider "kubernetes"`: `cluster_ca_certificate` enforces TLS peer verification; `host` is HTTPS endpoint | CIS EKS Benchmark v1.4 §4.4.1 |
| Public access | `[SECURITY OVERRIDE]` — `service_type = "LoadBalancer"` overrides the module's secure default of `ClusterIP`. This provisions a Classic ELB with a public endpoint. Justification: this is an explicit consumer requirement for the sandbox demo environment. No WAF, TLS termination, or security group ingress restrictions are applied at the service level. **Operators MUST replace this with ClusterIP + Ingress + AWS Load Balancer Controller for production workloads.** Risk: **High (P1)** — fix before production. | `module.app_deploy`: `service_type = "LoadBalancer"` | AWS Well-Architected SEC05-BP01; CIS EKS Benchmark v1.4 §5.1.1 |
| IAM least privilege | AWS dynamic credentials provided by `aws-dynamic-provider-credentials` global varset via OIDC `AssumeRoleWithWebIdentity`. No static IAM access keys. The assumed IAM role requires only `eks:DescribeCluster` for cluster auth and the EKS access entry permissions needed to manage Kubernetes resources. No `*:*` wildcards. | `provider "aws"`: no `assume_role {}` block — dynamic credentials injected via varset; `provider "kubernetes"`: `exec` block uses ambient STS credentials | AWS Well-Architected SEC02-BP02; CIS AWS Foundations Benchmark v2.0 §1.15 |
| Logging | Pod-level stdout/stderr logs are captured by the Kubernetes node log driver and available via `kubectl logs`. CloudWatch control-plane audit logging is managed by `eks-infra-vcs` (all 5 log types enabled). No additional logging configuration is in scope for this consumer. | N/A — application logging is the app's responsibility; control-plane logging managed upstream in `eks-infra-vcs` | AWS Well-Architected OPS06-BP01; CIS EKS Benchmark v1.4 §2.1.1 |
| Pod security | Module enforces non-root execution (`run_as_non_root = true`, `run_as_user = 1000`, `fs_group = 2000`), read-only root filesystem, dropped ALL Linux capabilities, and no privilege escalation. These are module secure defaults — not overridden by this consumer. | `module.app_deploy`: pod and container security context defaults honoured; `allow_privilege_escalation = false`, `privileged = false`, `read_only_root_filesystem = true`, `capabilities { drop = ["ALL"] }` | NSA/CISA Kubernetes Hardening Guide; CIS Kubernetes Benchmark v1.8.0 §5.2 |
| Tagging | Provider `default_tags` propagates `ManagedBy`, `Environment`, `Project`, `Owner` to all AWS-managed resources. The `kubernetes_namespace` glue resource carries `app.kubernetes.io/managed-by = "terraform"` and `environment` labels. | `provider "aws"`: `default_tags` block with 4 required tags; `kubernetes_namespace.app`: metadata labels | AWS Well-Architected OPS01-BP05; CIS AWS Foundations Benchmark v2.0 §1.15 |
| Registry credential protection | Registry credentials are sourced from **sensitive** HCP Terraform workspace variables, marked `sensitive = true` in `variables.tf`, and passed to the module via `data_wo` (write-only) — they never appear in plan output or state file. | `var.registry_password`: `sensitive = true`; `module.app_deploy`: `registry_password` mapped to module `data_wo` attribute | AWS Well-Architected SEC02-BP03; CIS AWS Foundations Benchmark v2.0 §3.9 |

---

## 5. Implementation Checklist

- [x] **A: Scaffold** — Create `consumers/006-kubernetes-app/` directory structure with all 9 files: `versions.tf` (terraform block, `required_version >= 1.14`, `required_providers` for `aws ~> 6.0` and `kubernetes ~> 3.2`), `backend.tf` (cloud block: org `jose-merchan`, project `Default Project`, workspace `k8s-app-demo-bob`), `variables.tf` (all 12 variables from the Variables table in §3 with types, descriptions, validations, sensitive flags), `outputs.tf` (all 5 outputs from §3 Outputs table), `locals.tf` (cluster coordinate locals from remote state: `cluster_endpoint`, `cluster_ca_certificate` with `base64decode()`, `cluster_name`, `aws_region`). No module calls yet.

- [x] **B: Data sources and provider config** — Populate `data.tf` with `data "terraform_remote_state" "eks_infra"` (backend = "remote", org `jose-merchan`, workspace = `var.infra_workspace`). Populate `providers.tf` with `provider "aws"` (region = `var.aws_region`, `default_tags` block) and `provider "kubernetes"` (host = `local.cluster_endpoint`, `cluster_ca_certificate` = `local.cluster_ca_certificate`, `exec` block with `api_version = "client.authentication.k8s.io/v1"`, command `aws`, args `eks get-token --cluster-name --region`).

- [x] **C: Glue resource and module call** — Populate `main.tf` with: (1) `kubernetes_namespace.app` glue resource with `[CONSTITUTION DEVIATION]` comment, metadata name = `var.namespace`, labels including `app.kubernetes.io/managed-by = "terraform"` and `environment`; (2) `module "app_deploy"` sourced from `app.terraform.io/jose-merchan/app-deploy/kubernetes ~> 0.1` with all required inputs wired per §3 Wiring Table, `namespace = kubernetes_namespace.app.metadata[0].name` for implicit dependency, `service_type = "LoadBalancer"` with `[SECURITY OVERRIDE]` comment.

- [x] **D: Workspace provisioning** — Create the `k8s-app-demo-bob` workspace in org `jose-merchan`, project `Default Project` (`prj-PmbVsprg8DoogHW7`), execution mode `remote`, Terraform version `~> 1.15.0`, auto-apply `true`. Set the four workspace variables (`registry_password` sensitive, `registry_username`, `registry_server`, `infra_workspace`). **Gate**: POST new workspace ID to `eks-infra-vcs` (`ws-fynCV5VvhkpRF7s3`) remote-state-consumers before triggering any plan run. *(Workspace provisioned via API on 2025-07-15 — ws-g5V4jbf1EyPrcy1P confirmed; remote state consumer registration confirmed.)*

- [x] **E: Documentation and validation** — Create `README.md` (prerequisites, quick start, variable reference, output reference, security notes for `[SECURITY OVERRIDE]` and `[CONSTITUTION DEVIATION]`). Create `terraform.auto.tfvars.example` with non-sensitive example values. Run `terraform fmt`, `terraform validate`, `tflint`, `trivy config .`. All checks must pass with no Critical or High findings.

---

## 6. Open Questions

**[RESOLVED] PMR publication prerequisite — `app-deploy/kubernetes` module published ✅**

The module `app.terraform.io/jose-merchan/app-deploy/kubernetes` is **live in the PMR** (`status: setup_complete`, `version: 0.1.0 / ok`).

- GitHub repo: [`jm-merchan/terraform-kubernetes-app-deploy`](https://github.com/jm-merchan/terraform-kubernetes-app-deploy)
- PMR source: `app.terraform.io/jose-merchan/app-deploy/kubernetes ~> 0.1`
- Tag `v0.1.0` pushed and ingested by HCP Terraform (confirmed 2025-07-15)

`terraform init` in the `k8s-app-demo-bob` workspace will resolve the module source successfully. This gate is **cleared**.

---

**[CONSTITUTION DEVIATION] `kubernetes_namespace` raw resource**

Constitution §1.1 enumerates permitted glue resources as: `random_id`, `random_string`, `null_resource`, `terraform_data`, `time_sleep`. The `kubernetes_namespace` resource is not listed.

**Justification for deviation:**
- Zero Kubernetes-provider modules exist in the `jose-merchan` PMR (16 modules confirmed, all AWS/Google provider, 2025-07-14).
- The module's scope boundary (design.md §1) explicitly states: "This module does NOT provision Kubernetes namespaces."
- Pre-creating the namespace out-of-band (`kubectl`) removes Terraform lifecycle management and violates IaC principles.
- A `kubernetes_namespace` is a thin metadata boundary — no compute, storage, or network resources are implicated. The spirit of the glue resource exception (lightweight wiring primitives) applies.
- Risk rating: **Low (P3)** — a namespace is not a security-sensitive resource.
- Exception documented here and in `main.tf` with `[CONSTITUTION DEVIATION]` comment per constitution §8.2.

**Review trigger**: If a `kubernetes-namespace` module is published to the `jose-merchan` PMR in a future sprint, this deviation MUST be resolved by replacing the raw resource with the PMR module call.

---

**[RESOLVED] Remote state consumer registration — completed ✅**

`k8s-app-demo-bob` (`ws-g5V4jbf1EyPrcy1P`) has been added as a remote state consumer of `eks-infra-vcs` (`ws-fynCV5VvhkpRF7s3`). Verified live — `eks-infra-vcs` now has 3 consumers:
- `ws-L4DyVVdn2YBUzipb` (eks-app-vcs)
- `ws-3MgtdSUWuLy9ktnL` (eks-vault-vcs)
- `ws-g5V4jbf1EyPrcy1P` (k8s-app-demo-bob) ← **new**

This gate is **cleared**. Implementation can proceed directly.
