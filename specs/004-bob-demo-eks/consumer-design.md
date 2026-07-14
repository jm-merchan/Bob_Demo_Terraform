# Consumer Design: bob-demo EKS Cluster

**Branch**: 004-bob-demo-eks
**Date**: 2025-07-14
**Status**: Draft
**Provider**: hashicorp/aws ~> 5.0
**Terraform**: >= 1.7
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

This deployment provisions a production-grade Amazon EKS cluster named `bob-demo` in the `eu-west-1` region for the `sandbox` environment. It provides a fully isolated Kubernetes control plane with a dedicated VPC (auto-created), a managed node group, KMS-encrypted secrets, CloudWatch control-plane logging, and an OIDC provider for IAM Roles for Service Accounts (IRSA). The cluster is the foundational compute layer for workloads in the `bob-demo` project, consumed by application teams that deploy Kubernetes workloads and by platform tooling that uses the OIDC provider to grant fine-grained AWS permissions to pods.

**Scope boundary**: Application-layer Kubernetes resources (Deployments, Services, Ingress, Helm charts), add-on controllers (AWS Load Balancer Controller, Cluster Autoscaler), monitoring agents, cross-account IAM roles for application service accounts, and any persistent data stores (RDS, ElastiCache) are explicitly out of scope for this deployment.

### Requirements

**Functional requirements** — what the deployment must provision (from Phase 1 clarification):

- A Kubernetes `1.32` control plane must be reachable from within the VPC via a private API endpoint.
- A new VPC with public and private subnets must be created automatically when no existing VPC is supplied.
- A managed node group of `t3.medium` instances must be provisioned with a minimum of 1, desired of 2, and maximum of 3 nodes, all placed in private subnets.
- Kubernetes secrets must be encrypted at rest using a customer-managed KMS key.
- All five EKS control-plane log types (`api`, `audit`, `authenticator`, `controllerManager`, `scheduler`) must be forwarded to CloudWatch Logs with at least 90-day retention.
- An OIDC provider must be created to support IRSA trust policies for pod-level AWS IAM access.
- The deployment must expose the cluster endpoint, CA data, OIDC issuer URL, OIDC provider ARN, VPC ID, private subnet IDs, and CloudWatch log group name as outputs for downstream consumers.

**Non-functional requirements** — constraints like compliance, performance, availability, cost:

- The deployment must be executed via HCP Terraform remote execution — no local `terraform apply` in CI/CD.
- AWS authentication must use short-lived dynamic credentials (OIDC-based STS) — no static IAM access keys permitted.
- All provisioned resources must carry `ManagedBy`, `Environment`, `Project`, and `Owner` tags for cost allocation and compliance reporting.
- The provider version constraint must be pessimistic (`~> 5.0`) to prevent uncontrolled major upgrades.
- The Terraform version floor must be `>= 1.7` in code; the workspace executor must be pinned to `~> 1.12.0`.
- The module must be sourced exclusively from the private registry (`app.terraform.io/jose-merchan`) — no public registry modules or raw resource blocks.
- The cluster API endpoint MUST be reachable from the public internet to allow operator access (`kubectl`) from locations without private VPC connectivity. `[SECURITY OVERRIDE]` — see Section 4.
- Public endpoint access MUST be restricted to a configurable list of CIDR blocks (`cluster_endpoint_public_access_cidrs`); the default restricts to `0.0.0.0/0` but operators SHOULD narrow this to known IPs in practice.
- Node capacity type must be `ON_DEMAND` to eliminate Spot interruption risk in the sandbox environment.

---

## 2. Module Selection & Architecture

### Architectural Decisions

**Single composite module for VPC + EKS**: Use `app.terraform.io/jose-merchan/eks-bob/aws` as the sole module call, relying on its internal VPC creation path (activated when `vpc_id` is `null`).
*Rationale*: Research finding `research-pmr-module.md` confirms that `eks-bob` internally composes `jose-merchan/vpc/aws` and `jose-merchan/eks/aws` with correct EKS subnet tags and dependency ordering. The module requires only 7 inputs at minimum, eliminating all cross-module wiring complexity at the consumer level. Research finding `research-wiring.md` independently verifies that `data.tf` and glue resources are not needed because AZ discovery is internal to the module.
*Rejected*: (a) Separate consumer-level VPC module call — would duplicate subnet logic already encapsulated in `eks-bob` and require manual wiring of `vpc_id`, `private_subnet_ids`, and `public_subnet_ids`; constitution §1.1 requires module-first composition not reimplementation. (b) Raw `aws_eks_cluster` + `aws_vpc` resource blocks — prohibited by constitution §1.1.

**Version constraint `~> 0.1`**: Pin the module at the `0.1.x` series.
*Rationale*: Research finding `research-pmr-module.md` confirms `0.1.0` is the only published version and recommends `~> 0.1` as the safe pessimistic constraint that allows patch-level fixes while blocking `0.2.0` breaking changes. Constitution §4.3 requires `~>` constraints for all module versions.
*Rejected*: `= 0.1.0` exact pin (too restrictive, blocks patch fixes); `>= 0.1` (permits future `0.2.0` breaking changes).

**Public endpoint enabled with CIDR restriction**: Override module default by setting `cluster_endpoint_public_access = true` and exposing `cluster_endpoint_public_access_cidrs` as a consumer variable. `[SECURITY OVERRIDE]` — justified by sandbox operator requirement: no private VPC connectivity from developer workstations; `kubectl` and CI/CD pipelines must reach the API server over the internet.
*Rationale*: The `eks-bob` module exposes `cluster_endpoint_public_access` (default `false`) and `cluster_endpoint_public_access_cidrs` (default `["0.0.0.0/0"]`) as inputs. The private endpoint (`endpoint_private_access = true`) remains hardcoded in the module — node-to-control-plane traffic stays private. Only the public-facing API endpoint is opened.
*Rejected*: Keeping the private-only default — would make the cluster unreachable from operator workstations without a VPN or bastion, which is not available in this sandbox environment.

**Region override via `var.aws_region`**: Set the AWS provider `region` argument from `var.aws_region`, defaulting to `"eu-west-1"`, rather than relying solely on the global varset's `AWS_REGION` env variable.
*Rationale*: Research finding `research-workspace.md` confirms the global `aws-dynamic-provider-credentials` varset sets `AWS_REGION = us-east-1`. Making the region explicit in the provider block (with a `eu-west-1` default in `variables.tf`) makes the intended region auditable in code review and removes a runtime dependency on workspace variable ordering. The workspace-level `AWS_REGION = eu-west-1` env override is an additional safety net.
*Rejected*: Relying solely on the global varset env var — the varset default is `us-east-1`, creating a silent misconfiguration risk if the workspace override is omitted.

**API-driven workflow, `auto_apply = false`**: Create the workspace without a VCS connection and with auto-apply disabled.
*Rationale*: Research finding `research-workspace.md` confirms the pattern for CLI-driven workspaces in the sandbox project sets `auto_apply = false` so operators review the plan before apply. The clarified requirements specify no VCS connection.
*Rejected*: VCS-connected workspace — not required by the feature brief and adds GitHub App configuration complexity not in scope.

### Module Inventory

| Module | Registry Source | Version | Purpose | Conditional | Key Inputs | Key Outputs |
|--------|----------------|---------|---------|-------------|------------|-------------|
| `eks_cluster` | `app.terraform.io/jose-merchan/eks-bob/aws` | `~> 0.1` | Provisions VPC (auto-created), EKS control plane `1.32`, managed node group (`t3.medium`, 1–3 nodes), KMS CMK for secrets encryption, CloudWatch control-plane logging (5 types, 90-day retention), and OIDC provider for IRSA | always | `cluster_name`, `kubernetes_version`, `environment`, `node_instance_types`, `node_min_size`, `node_max_size`, `node_desired_size` | `cluster_endpoint`, `cluster_certificate_authority_data`, `cluster_oidc_issuer_url`, `oidc_provider_arn`, `vpc_id`, `private_subnet_ids`, `cloudwatch_log_group_name` |

### Glue Resources

--

No glue resources are required. The single-module topology has no cross-module wiring; `random_id`, `null_resource`, and similar glue primitives serve no purpose in this composition (confirmed by `research-wiring.md` and `research-pmr-module.md`).

### Workspace Configuration

| Setting | Value | Notes |
|---------|-------|-------|
| Organization | `jose-merchan` | HCP Terraform organization |
| Project | `sandbox` | Existing project `prj-cJR1vdDjwGbiHqzE`; all sandbox EKS workloads target this project |
| Workspace | `sandbox-bob-demo-eks` | Follows `<project>-<feature>` naming pattern observed in all sandbox workspaces |
| Execution Mode | `remote` | Consistent with 100% of sandbox workspaces confirmed in `research-workspace.md` |
| Terraform Version | `~> 1.12.0` | Workspace executor pin; matches all existing sandbox workspaces |
| Auto-Apply | `false` | CLI-driven; operator reviews plan before apply |
| VCS Connection | None | API-driven workflow; can be upgraded to GitHub App VCS later |
| Variable Sets | `aws-dynamic-provider-credentials` (global, auto-applied) | Injects `TFC_AWS_PROVIDER_AUTH`, `TFC_AWS_RUN_ROLE_ARN`; no explicit assignment step needed |
| Workspace Variable | `AWS_REGION = eu-west-1` (env) | **Required** — overrides global varset default `us-east-1`; workspace-level vars take precedence |

---

## 3. Module Wiring

### Wiring Diagram

Single-module topology — all consumer variables flow directly into `module.eks_cluster` inputs; all consumer outputs are direct passthroughs from `module.eks_cluster` outputs. No cross-module wiring exists.

```
# Consumer inputs → module inputs
var.cluster_name                        ──→ module.eks_cluster.cluster_name
var.kubernetes_version                  ──→ module.eks_cluster.kubernetes_version
var.environment                         ──→ module.eks_cluster.environment
var.node_instance_types                 ──→ module.eks_cluster.node_instance_types
var.node_min_size                       ──→ module.eks_cluster.node_min_size
var.node_max_size                       ──→ module.eks_cluster.node_max_size
var.node_desired_size                   ──→ module.eks_cluster.node_desired_size
var.cluster_endpoint_public_access_cidrs ──→ module.eks_cluster.cluster_endpoint_public_access_cidrs  # [SECURITY OVERRIDE]

# Module outputs → consumer outputs
module.eks_cluster.cluster_name                      ──→ output.cluster_name
module.eks_cluster.cluster_endpoint                  ──→ output.cluster_endpoint
module.eks_cluster.cluster_arn                       ──→ output.cluster_arn
module.eks_cluster.cluster_certificate_authority_data ──→ output.cluster_certificate_authority_data  [sensitive]
module.eks_cluster.cluster_oidc_issuer_url           ──→ output.cluster_oidc_issuer_url
module.eks_cluster.oidc_provider_arn                 ──→ output.oidc_provider_arn
module.eks_cluster.cluster_security_group_id         ──→ output.cluster_security_group_id
module.eks_cluster.vpc_id                            ──→ output.vpc_id
module.eks_cluster.private_subnet_ids                ──→ output.private_subnet_ids
module.eks_cluster.cloudwatch_log_group_name         ──→ output.cloudwatch_log_group_name
```

### Wiring Table

This deployment has a single module; there is no module-to-module output/input wiring. All connections are consumer-variable-to-module-input (inputs side) and module-output-to-consumer-output (outputs side). Both are captured in the Wiring Diagram above and the Variables and Outputs tables below. No cross-module transformation is required.

| Source | Output / Variable | Target | Input / Output | Type | Transformation |
|--------|------------------|--------|---------------|------|----------------|
| `var` | `cluster_name` | `module.eks_cluster` | `cluster_name` | `string` | direct |
| `var` | `kubernetes_version` | `module.eks_cluster` | `kubernetes_version` | `string` | direct |
| `var` | `environment` | `module.eks_cluster` | `environment` | `string` | direct |
| `var` | `node_instance_types` | `module.eks_cluster` | `node_instance_types` | `list(string)` | direct |
| `var` | `node_min_size` | `module.eks_cluster` | `node_min_size` | `number` | direct |
| `var` | `node_max_size` | `module.eks_cluster` | `node_max_size` | `number` | direct |
| `var` | `node_desired_size` | `module.eks_cluster` | `node_desired_size` | `number` | direct |
| `module.eks_cluster` | `cluster_name` | `output` | `cluster_name` | `string` | direct |
| `module.eks_cluster` | `cluster_endpoint` | `output` | `cluster_endpoint` | `string` | direct |
| `module.eks_cluster` | `cluster_arn` | `output` | `cluster_arn` | `string` | direct |
| `module.eks_cluster` | `cluster_certificate_authority_data` | `output` | `cluster_certificate_authority_data` | `string` (sensitive) | direct |
| `module.eks_cluster` | `cluster_oidc_issuer_url` | `output` | `cluster_oidc_issuer_url` | `string` | direct |
| `module.eks_cluster` | `oidc_provider_arn` | `output` | `oidc_provider_arn` | `string` | direct |
| `module.eks_cluster` | `cluster_security_group_id` | `output` | `cluster_security_group_id` | `string` | direct |
| `module.eks_cluster` | `vpc_id` | `output` | `vpc_id` | `string` | direct |
| `module.eks_cluster` | `private_subnet_ids` | `output` | `private_subnet_ids` | `list(string)` | direct |
| `module.eks_cluster` | `cloudwatch_log_group_name` | `output` | `cloudwatch_log_group_name` | `string` | direct |

### Provider Configuration

```hcl
# providers.tf
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = var.owner
    }
  }

  # Dynamic credentials via HCP Terraform:
  # TFC_AWS_PROVIDER_AUTH and TFC_AWS_RUN_ROLE_ARN are injected by the global
  # aws-dynamic-provider-credentials varset — no static keys, no assume_role {} needed.
}
```

### Variables

This table is the SINGLE SOURCE OF TRUTH for the deployment's input interface.

| Variable | Type | Required | Default | Validation | Sensitive | Description |
|----------|------|----------|---------|------------|-----------|-------------|
| `aws_region` | `string` | No | `"eu-west-1"` | -- | No | AWS region to deploy into. Default `eu-west-1`; also controlled by workspace env var `AWS_REGION`. |
| `project_name` | `string` | No | `"bob-demo-eks"` | -- | No | Project name applied to `default_tags` `Project` key and used in workspace labelling. |
| `owner` | `string` | No | `"platform-team"` | -- | No | Owner value for `default_tags` `Owner` key; used for cost allocation reporting. |
| `cluster_name` | `string` | Yes | -- | Length 1–100; must match `^[a-zA-Z0-9_-]+$` | No | Name of the EKS cluster. Also used as the VPC name and node group name prefix inside the module. |
| `kubernetes_version` | `string` | No | `"1.32"` | Must match `^[0-9]+\.[0-9]+$` (no `v` prefix, e.g. `"1.32"`) | No | Kubernetes control-plane version. No `v` prefix. |
| `environment` | `string` | No | `"sandbox"` | Must be one of `dev`, `staging`, `prod`, `sandbox` | No | Deployment environment identifier applied to all resource tags. |
| `node_instance_types` | `list(string)` | No | `["t3.medium"]` | List must contain at least 1 element | No | EC2 instance types for the managed node group. |
| `node_min_size` | `number` | No | `1` | Value must be >= 1 | No | Minimum number of nodes in the managed node group. |
| `node_max_size` | `number` | No | `3` | Value must be >= 1 | No | Maximum number of nodes in the managed node group. |
| `node_desired_size` | `number` | No | `2` | Value must be >= 1 | No | Desired node count at cluster creation time. |
| `cluster_endpoint_public_access_cidrs` | `list(string)` | No | `["0.0.0.0/0"]` | -- | No | `[SECURITY OVERRIDE]` CIDR blocks allowed to reach the public EKS API endpoint. Default is open; operators SHOULD restrict to known IPs in non-sandbox environments. |

### Outputs

| Output | Type | Source | Sensitive | Description |
|--------|------|--------|-----------|-------------|
| `cluster_name` | `string` | `module.eks_cluster.cluster_name` | No | EKS cluster name — used in `kubectl` commands and kubeconfig generation. |
| `cluster_endpoint` | `string` | `module.eks_cluster.cluster_endpoint` | No | EKS API server URL — required for kubeconfig and provider configuration in downstream Terraform. |
| `cluster_arn` | `string` | `module.eks_cluster.cluster_arn` | No | EKS cluster ARN — used in IAM policy condition keys and tagging. |
| `cluster_certificate_authority_data` | `string` | `module.eks_cluster.cluster_certificate_authority_data` | **Yes** | Base64-encoded cluster CA certificate — required for kubeconfig TLS verification. Must be marked `sensitive = true`. |
| `cluster_oidc_issuer_url` | `string` | `module.eks_cluster.cluster_oidc_issuer_url` | No | OIDC issuer URL — used in the subject claim of IRSA trust policy documents. |
| `oidc_provider_arn` | `string` | `module.eks_cluster.oidc_provider_arn` | No | OIDC provider ARN — required in `assume_role_policy` trust documents for IRSA IAM roles. |
| `cluster_security_group_id` | `string` | `module.eks_cluster.cluster_security_group_id` | No | Cluster-managed security group ID — referenced when granting cross-service network access to the cluster. |
| `vpc_id` | `string` | `module.eks_cluster.vpc_id` | No | VPC ID created by the module — consumed by future modules (RDS, ALB, cache) added to this consumer. |
| `private_subnet_ids` | `list(string)` | `module.eks_cluster.private_subnet_ids` | No | Private subnet IDs — consumed by future RDS, ElastiCache, or additional node group modules. |
| `cloudwatch_log_group_name` | `string` | `module.eks_cluster.cloudwatch_log_group_name` | No | CloudWatch log group name for control-plane logs — used in dashboard queries and metric-filter alarms. |

---

## 4. Security Controls

| Control | Enforcement | Module Config | Reference |
|---------|-------------|---------------|-----------|
| Encryption at rest | Module default honoured — `eks-bob` creates a customer-managed KMS CMK and configures it as the EKS secrets envelope encryption provider. Consumer does not override. | `module.eks_cluster`: `kms_key_enabled` defaults to `true` (Security Hub EKS.3) | AWS Security Hub [EKS.3]; CIS AWS Foundations Benchmark v1.4 §5.3.1 (encrypt Kubernetes secrets at rest) |
| Encryption in transit | Module default honoured — EKS control-plane API server enforces TLS 1.2+ for all client-to-API and node-to-API communication; this is an AWS-managed control within the EKS service and cannot be disabled. | `module.eks_cluster`: no consumer override required; AWS-managed TLS enforcement | AWS Well-Architected Security Pillar SEC07-BP02 (protect data in transit); CIS AWS EKS Benchmark §4.4.1 |
| Public access | `[SECURITY OVERRIDE]` — public endpoint enabled for sandbox operator access from locations without private VPC connectivity. Private endpoint (`endpoint_private_access = true`) remains hardcoded active inside the module; node-to-control-plane traffic is unaffected. CIDRs restricted via `cluster_endpoint_public_access_cidrs` (default `0.0.0.0/0`; SHOULD be narrowed in practice). Accepted risk: sandbox environment only. | `module.eks_cluster`: `cluster_endpoint_public_access = true`, `cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs` | AWS Security Hub [EKS.1] — **overridden**; CIS AWS EKS Benchmark §3.1.1 — **exception documented** |
| IAM least privilege | Dynamic credentials: HCP Terraform injects short-lived STS credentials via OIDC `AssumeRoleWithWebIdentity` using the role `arn:aws:iam::492487827579:role/hcp-terraform-dynamic-admin`. No static IAM keys exist in the deployment. IRSA OIDC provider created by the module enables pod-level least-privilege IAM roles without node-level credentials. | `module.eks_cluster`: `enable_irsa` defaults to `true`; provider uses HCP Terraform dynamic credentials (constitution §3.1) | AWS Well-Architected Security Pillar SEC02-BP02 (use temporary credentials); CIS AWS Foundations Benchmark v1.4 §1.15 (no active IAM access keys for root/users) |
| Logging | Module default honoured — all five EKS control-plane log types (`api`, `audit`, `authenticator`, `controllerManager`, `scheduler`) are shipped to CloudWatch Logs with 90-day retention. Consumer does not override `cluster_log_types` or `cluster_log_retention_in_days`. | `module.eks_cluster`: `cluster_log_types` defaults to all 5 types; `cluster_log_retention_in_days` defaults to `90` (Security Hub EKS.8) | AWS Security Hub [EKS.8]; CIS AWS EKS Benchmark §2.1.1 (enable audit logging); AWS Well-Architected Security Pillar SEC04-BP01 (configure service and application logging) |
| Tagging | Provider `default_tags` block applies `ManagedBy = "terraform"`, `Environment`, `Project`, `Owner` to all resources via the AWS provider. The module additionally applies `Name`, `Application`, and `ManagedBy` tags internally. Module `tags` input is not explicitly set by the consumer — `default_tags` propagation is sufficient for the sandbox environment. | `provider "aws"`: `default_tags` with `ManagedBy`, `Environment`, `Project`, `Owner` (constitution §3.3); `module.eks_cluster`: internal module tags merged at resource level | AWS Well-Architected Operational Excellence Pillar OPS11-BP07 (use tags to organize resources); CIS AWS Foundations Benchmark v1.4 §1.22 (ensure resource tagging) |

---

## 5. Implementation Checklist

- [ ] **A: Scaffold** — Create the 7-file root module structure: `versions.tf` (Terraform `>= 1.7`, `hashicorp/aws ~> 5.0`), `backend.tf` (`cloud {}` block with org `jose-merchan`, project `sandbox`, workspace `sandbox-bob-demo-eks`), `providers.tf` (AWS provider with `region = var.aws_region` and `default_tags`), `variables.tf` (all 10 variables from the Variables table in Section 3), `outputs.tf` (all 10 outputs from the Outputs table in Section 3), `locals.tf` (empty scaffold, no computed locals needed for single-module topology), and `terraform.auto.tfvars.example` (example values for all variables).

- [ ] **B: Core module** — Populate `main.tf` with the single `module "eks_cluster"` block sourced from `app.terraform.io/jose-merchan/eks-bob/aws` at version `~> 0.1`. Wire all 7 required inputs (`cluster_name`, `kubernetes_version`, `environment`, `node_instance_types`, `node_min_size`, `node_max_size`, `node_desired_size`) from consumer variables per the Wiring Table in Section 3. Apply security override: set `cluster_endpoint_public_access = true` and wire `cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs`. Accept all other security-relevant module defaults without override (`kms_key_enabled`, `cluster_log_types`, `enable_irsa`).

- [ ] **C: Workspace creation** — Create workspace `sandbox-bob-demo-eks` in the `sandbox` project (`prj-cJR1vdDjwGbiHqzE`) of the `jose-merchan` HCP Terraform org with execution mode `remote`, Terraform version `~> 1.12.0`, `auto_apply = false`, and no VCS connection. Add workspace-level environment variable `AWS_REGION = eu-west-1` to override the global varset's `us-east-1` default. Confirm global varset `aws-dynamic-provider-credentials` is auto-applied (no explicit assignment step needed).

- [ ] **D: Polish** — Run `terraform fmt` across all `.tf` files. Add inline comments to `main.tf` explaining which module defaults are being honoured for security controls. Populate `README.md` with deployment description, prerequisites, variable reference (link to Section 3), output reference, and `terraform init` / `terraform plan` quick-start steps. Verify `terraform.auto.tfvars.example` covers all 10 variables with the sandbox defaults (`cluster_name = "bob-demo"`, `environment = "sandbox"`, etc.).

- [ ] **E: Validate** — Run `terraform init -backend=false` to confirm provider and module resolution. Run `terraform validate` to confirm no syntax or type errors. Confirm all 10 outputs defined in `outputs.tf` match the source expressions in the Outputs table. Confirm `cluster_certificate_authority_data` output carries `sensitive = true`. Confirm no raw `resource` blocks exist in `main.tf` (constitution §1.1 check).

---

## 6. Open Questions

**[DEFERRED] AWS_REGION workspace-level override — operational risk**: The global varset `aws-dynamic-provider-credentials` sets `AWS_REGION = us-east-1`. This deployment targets `eu-west-1`. Two mitigations are in place: (1) `var.aws_region` defaults to `"eu-west-1"` in `variables.tf`, which is passed to the provider `region` argument, making the region explicit in code; (2) a workspace-level env variable `AWS_REGION = eu-west-1` must be set on `sandbox-bob-demo-eks` to override the global varset value. If the workspace variable is omitted and `var.aws_region` is not explicitly set in the workspace's Terraform variables, the provider would receive `us-east-1` from the environment. The implementation checklist item C includes the workspace variable creation step. This dependency on a manual workspace setup step is noted here as a residual operational risk until workspace-as-code (Terraform workspace provisioning) is adopted for this org.
