# bob-demo EKS Cluster Consumer

Deploys a production-grade Amazon EKS cluster named `bob-demo` in the `eu-west-1` region for the `sandbox` environment, using the private registry module [`jose-merchan/eks-bob/aws`](https://app.terraform.io/app/jose-merchan/registry/modules/private/jose-merchan/eks-bob/aws).

**What this deploys:**

- A dedicated VPC with public and private subnets (auto-created by the module — no existing VPC required).
- An EKS control plane at Kubernetes `1.32` with a public API endpoint (CIDR-restricted) and a private endpoint always active.
- A managed node group of `t3.medium` instances (ON_DEMAND) in private subnets — min 1, desired 2, max 3 nodes.
- A customer-managed KMS key for Kubernetes secrets envelope encryption.
- CloudWatch control-plane logging for all five log types (`api`, `audit`, `authenticator`, `controllerManager`, `scheduler`) with 90-day retention.
- An OIDC provider for IAM Roles for Service Accounts (IRSA).

Managed by: **HCP Terraform** — workspace `sandbox-bob-demo-eks` in project `sandbox`, org `jose-merchan`.

---

## Prerequisites

| Requirement | Detail |
|---|---|
| Terraform | `>= 1.7` (workspace executor pinned to `~> 1.12.0`) |
| HCP Terraform | Account in org `jose-merchan`; `sandbox` project must exist (`prj-cJR1vdDjwGbiHqzE`) |
| AWS credentials | Dynamic provider credentials via OIDC — **no static IAM access keys needed**. The global varset `aws-dynamic-provider-credentials` injects `TFC_AWS_PROVIDER_AUTH` and `TFC_AWS_RUN_ROLE_ARN` automatically. |
| Workspace env var | `AWS_REGION = eu-west-1` must be set at workspace level to override the global varset default (`us-east-1`). |

---

## Quick Start

```bash
# 1. Initialise — downloads the eks-bob module from app.terraform.io/jose-merchan
terraform init

# 2. Preview the plan (runs remotely in HCP Terraform)
terraform plan

# 3. Apply (auto_apply = false — review the plan output before confirming)
terraform apply
```

> **Note**: All runs execute remotely in HCP Terraform. Local AWS credentials are not required.

---

## Variable Reference

All 11 consumer variables. Declared in [`variables.tf`](variables.tf).

| Variable | Type | Default | Description |
|---|---|---|---|
| `aws_region` | `string` | `"eu-west-1"` | AWS region to deploy into. Also controlled by workspace env var `AWS_REGION`. |
| `project_name` | `string` | `"bob-demo-eks"` | Project name applied to `default_tags` `Project` key and workspace labelling. |
| `owner` | `string` | `"platform-team"` | Owner value for `default_tags` `Owner` key; used for cost allocation reporting. |
| `cluster_name` | `string` | *(required)* | Name of the EKS cluster. Also used as the VPC name and node group name prefix inside the module. Must match `^[a-zA-Z0-9_-]+$`, length 1–100. |
| `kubernetes_version` | `string` | `"1.32"` | Kubernetes control-plane version. No `v` prefix (e.g. `"1.32"`). |
| `environment` | `string` | `"sandbox"` | Deployment environment. One of: `dev`, `staging`, `prod`, `sandbox`. Applied to all resource tags. |
| `node_instance_types` | `list(string)` | `["t3.medium"]` | EC2 instance types for the managed node group. Must contain at least 1 element. |
| `node_min_size` | `number` | `1` | Minimum number of nodes in the managed node group. Must be >= 1. |
| `node_max_size` | `number` | `3` | Maximum number of nodes in the managed node group. Must be >= 1. |
| `node_desired_size` | `number` | `2` | Desired node count at cluster creation time. Must be >= 1. |
| `cluster_endpoint_public_access_cidrs` | `list(string)` | `["0.0.0.0/0"]` | **[SECURITY OVERRIDE]** CIDR blocks allowed to reach the public EKS API endpoint. Default is fully open; operators **SHOULD** restrict to known IPs in non-sandbox environments. |

Copy [`terraform.auto.tfvars.example`](terraform.auto.tfvars.example) to `terraform.auto.tfvars` and adjust values before running.

---

## Output Reference

All 10 consumer outputs. Declared in [`outputs.tf`](outputs.tf).

| Output | Type | Sensitive | Description |
|---|---|---|---|
| `cluster_name` | `string` | No | EKS cluster name — used in `kubectl` commands and kubeconfig generation. |
| `cluster_endpoint` | `string` | No | EKS API server URL — required for kubeconfig and downstream Terraform provider configuration. |
| `cluster_arn` | `string` | No | EKS cluster ARN — used in IAM policy condition keys and tagging. |
| `cluster_certificate_authority_data` | `string` | **Yes** | Base64-encoded cluster CA certificate — required for kubeconfig TLS verification. |
| `cluster_oidc_issuer_url` | `string` | No | OIDC issuer URL — used in the subject claim of IRSA trust policy documents. |
| `oidc_provider_arn` | `string` | No | OIDC provider ARN — required in `assume_role_policy` trust documents for IRSA IAM roles. |
| `cluster_security_group_id` | `string` | No | Cluster-managed security group ID — referenced when granting cross-service network access. |
| `vpc_id` | `string` | No | VPC ID created by the module — consumed by future modules (RDS, ALB, cache). |
| `private_subnet_ids` | `list(string)` | No | Private subnet IDs — consumed by future RDS, ElastiCache, or additional node group modules. |
| `cloudwatch_log_group_name` | `string` | No | CloudWatch log group name for control-plane logs — used in dashboard queries and metric-filter alarms. |

---

## Security Notes

### [SECURITY OVERRIDE] — Public API Endpoint

The EKS API endpoint is enabled for **public access** (`cluster_endpoint_public_access = true`). This is an explicit override of the module's secure default (`false`), justified by the sandbox environment requirement: operators and CI/CD pipelines reach the API server over the internet from locations without private VPC connectivity.

**Mitigations in place:**

- The **private endpoint remains active** (`endpoint_private_access = true`) — hardcoded inside the `eks-bob` module. Node-to-control-plane traffic never traverses the public internet.
- Public access is **CIDR-restricted** via `cluster_endpoint_public_access_cidrs` (variable). The default `["0.0.0.0/0"]` is suitable for sandbox; operators **SHOULD** narrow this to known IP ranges in staging/prod.

This override is documented in [`consumer-design.md`](../../specs/004-bob-demo-eks/consumer-design.md) Section 4 (Security Controls) and Section 2 (Architectural Decisions).

### Honoured Module Defaults (not overridden)

| Control | Module Default | Compliance Reference |
|---|---|---|
| KMS encryption at rest | `kms_key_enabled = true` — CMK envelope encryption for Kubernetes secrets | AWS Security Hub EKS.3; CIS AWS Foundations §5.3.1 |
| Control-plane logging | All 5 log types shipped to CloudWatch, 90-day retention | AWS Security Hub EKS.8; CIS EKS Benchmark §2.1.1 |
| OIDC / IRSA | `enable_irsa = true` — OIDC provider created for pod-level IAM | AWS Well-Architected SEC02-BP02 |
| Encryption in transit | TLS 1.2+ enforced by the EKS service (AWS-managed, cannot be disabled) | CIS EKS Benchmark §4.4.1 |

### Dynamic Credentials

AWS authentication uses short-lived STS credentials via OIDC `AssumeRoleWithWebIdentity`. The global varset `aws-dynamic-provider-credentials` injects `TFC_AWS_PROVIDER_AUTH` and `TFC_AWS_RUN_ROLE_ARN` into every run. **No static IAM access keys exist in this deployment.**

---

## HCP Terraform Workspace

| Setting | Value |
|---|---|
| Organization | `jose-merchan` |
| Project | `sandbox` (`prj-cJR1vdDjwGbiHqzE`) |
| Workspace | `sandbox-bob-demo-eks` |
| Execution mode | `remote` |
| Terraform version | `~> 1.12.0` |
| Auto-apply | `false` |
| VCS connection | None (API-driven workflow) |
| Variable sets | `aws-dynamic-provider-credentials` (global, auto-applied) |
| Workspace env var | `AWS_REGION = eu-west-1` |
