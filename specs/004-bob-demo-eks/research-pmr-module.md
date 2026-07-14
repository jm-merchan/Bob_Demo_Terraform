# Research: `jose-merchan/eks-bob/aws` v0.1.0 Module Interface

## Research: What are the exact inputs, outputs, secure defaults, required variables, and optional variables of the `jose-merchan/eks-bob/aws` module version `0.1.0`? What version constraint should a consumer use?

### Decision

Consume `app.terraform.io/jose-merchan/eks-bob/aws` with `version = "~> 0.1"` — the module fully encapsulates VPC + EKS composition with secure defaults for Security Hub EKS.1 / EKS.3 / EKS.8, requiring only 7 inputs at minimum.

---

### Modules Identified

- **Primary Module**: `app.terraform.io/jose-merchan/eks-bob/aws` v0.1.0
  - **Purpose**: Composes `jose-merchan/vpc/aws` (created when no `vpc_id` supplied) and `jose-merchan/eks/aws` (always) into a single, production-ready EKS cluster with a managed node group, CloudWatch logging, KMS secrets encryption, and IRSA OIDC provider.
  - **Key Inputs**: See full variable tables below.
  - **Key Outputs**: See full output table below.
  - **Secure Defaults**:
    - `cluster_endpoint_public_access = false` → API server is private-only (Security Hub EKS.1)
    - `kms_key_enabled = true` → customer-managed KMS key for Kubernetes secrets envelope encryption (Security Hub EKS.3)
    - `cluster_log_types = ["api","audit","authenticator","controllerManager","scheduler"]` → all 5 control-plane log types shipped to CloudWatch (Security Hub EKS.8)
    - `cluster_log_retention_in_days = 90` → 90-day CloudWatch retention
    - `enable_irsa = true` → OIDC provider created for IRSA by default
    - `authentication_mode = "API_AND_CONFIG_MAP"` → supports both EKS access entries and the legacy `aws-auth` ConfigMap
    - `node_capacity_type = "ON_DEMAND"` → no Spot interruption risk by default
    - `endpoint_private_access` → hardcoded `true` inside the module (not a consumer variable)
    - Worker nodes hardcoded to private subnets only
    - EKS subnet tags for AWS Load Balancer Controller autodiscovery applied automatically
- **Supporting Modules** (called internally, not by consumer):
  - `app.terraform.io/jose-merchan/vpc/aws` — VPC with public/private subnets, NAT gateway, EKS subnet tags; created only when `vpc_id` is null/empty
  - `app.terraform.io/jose-merchan/eks/aws` — EKS control plane + managed node group (`default` node group keyed `"${cluster_name}-ng"`)
- **Glue Resources Needed**: None — no `random_id` or `null_resource` required by the consumer. The module internally uses `data "aws_availability_zones" "available"` (count-gated on `local.create_vpc`).
- **Wiring Considerations**:
  - `vpc_id` output can be passed to downstream modules that need the VPC (e.g., RDS, ALB)
  - `private_subnet_ids` / `public_subnet_ids` outputs are already resolved whether VPC was created or provided
  - `cluster_name`, `cluster_endpoint`, `cluster_certificate_authority_data` (sensitive), and `cluster_oidc_issuer_url` are the canonical kubeconfig inputs for any Kubernetes/Helm provider configuration
  - `oidc_provider_arn` + `cluster_oidc_issuer_url` are the two values required to write IRSA `assume_role_policy` trust documents
  - `node_security_group_id` / `cluster_security_group_id` allow consumer to attach ingress/egress rules without knowing the SG IDs in advance
  - `kms_policy_arn` is `null` when `kms_key_enabled = false` — use `try()` when referencing it cross-module

---

### Required Variables (no default — must be supplied by consumer)

| Variable | Type | Validation | Description |
|---|---|---|---|
| `cluster_name` | `string` | 1–100 chars; `^[a-zA-Z0-9_-]+$` | EKS cluster name. Also used as VPC `name` and node group name prefix |
| `kubernetes_version` | `string` | `^[0-9]+\.[0-9]+$` (e.g. `"1.32"`) | Kubernetes control-plane version; no `v` prefix |
| `environment` | `string` | one of `["dev","staging","prod","sandbox"]` | Applied to all resource tags |
| `node_instance_types` | `list(string)` | `length >= 1` | EC2 instance types for the managed node group (e.g. `["t3.medium"]`) |
| `node_min_size` | `number` | `>= 1` | Managed node group minimum node count |
| `node_max_size` | `number` | `>= 1` | Managed node group maximum node count |
| `node_desired_size` | `number` | `>= 1` | Managed node group desired node count at cluster creation |

---

### Optional Variables (have defaults)

#### VPC / Networking

| Variable | Type | Default | Description |
|---|---|---|---|
| `vpc_id` | `string` | `null` | Existing VPC ID. When `null` or `""`, the module creates a new VPC automatically (BYO-VPC mode off) |
| `private_subnet_ids` | `list(string)` | `[]` | Existing private subnet IDs. Required when `vpc_id` is provided; ignored when creating a new VPC |
| `public_subnet_ids` | `list(string)` | `[]` | Existing public subnet IDs. Required when `vpc_id` is provided; ignored when creating a new VPC |
| `vpc_cidr` | `string` | `"10.0.0.0/16"` | CIDR for the new VPC. Only used when `vpc_id` is not provided. Validated with `cidrnetmask()` |
| `availability_zones` | `list(string)` | `[]` (auto-discover) | AZs for subnet creation. Auto-discovered via `data.aws_availability_zones` when empty. Must be 0 or >= 2 |
| `public_subnet_cidrs` | `list(string)` | `["10.0.101.0/24","10.0.102.0/24"]` | Public subnet CIDRs (one per AZ). Only used when creating a new VPC |
| `private_subnet_cidrs` | `list(string)` | `["10.0.1.0/24","10.0.2.0/24"]` | Private subnet CIDRs (one per AZ). `/20` or larger recommended for pod IP space |
| `one_nat_gateway_per_az` | `bool` | `false` | `true` = one NAT per AZ (HA, higher cost); `false` = single shared NAT |
| `enable_vpc_flow_logs` | `bool` | `false` | Enable VPC Flow Logs for the created VPC. Recommended for production |

#### Security / Cluster

| Variable | Type | Default | Description |
|---|---|---|---|
| `cluster_endpoint_public_access` | `bool` | `false` ✅ | Expose the EKS API server on the public internet. `false` = private-only (Security Hub EKS.1) |
| `cluster_endpoint_public_access_cidrs` | `list(string)` | `["0.0.0.0/0"]` | CIDRs allowed to reach the public endpoint. Only active when `cluster_endpoint_public_access = true`. Should be restricted in production |
| `kms_key_enabled` | `bool` | `true` ✅ | Create a customer-managed KMS key for Kubernetes secrets envelope encryption (Security Hub EKS.3) |
| `cluster_log_types` | `list(string)` | `["api","audit","authenticator","controllerManager","scheduler"]` ✅ | Control-plane log types forwarded to CloudWatch (Security Hub EKS.8) |
| `cluster_log_retention_in_days` | `number` | `90` | CloudWatch log group retention. Must be a valid CW value: `1,3,5,7,14,30,60,90,120,150,180,365,400,545,731,1827,3653` |
| `enable_irsa` | `bool` | `true` ✅ | Create an OIDC provider enabling IAM Roles for Service Accounts (IRSA) |
| `authentication_mode` | `string` | `"API_AND_CONFIG_MAP"` | EKS auth mode. One of `CONFIG_MAP`, `API`, `API_AND_CONFIG_MAP` |

#### Node Group

| Variable | Type | Default | Description |
|---|---|---|---|
| `node_capacity_type` | `string` | `"ON_DEMAND"` | `ON_DEMAND` (stable) or `SPOT` (cost-optimised, interruptible) |
| `node_disk_size` | `number` | `20` | EBS root volume size in GiB. Must be >= 20 |

#### Tagging

| Variable | Type | Default | Description |
|---|---|---|---|
| `tags` | `map(string)` | `{}` | Additional tags merged onto all taggable resources. Consumer tags take precedence over module defaults |

> **Module-applied default tags** (always present, cannot be disabled):
> ```
> Name        = var.cluster_name
> ManagedBy   = "terraform"
> Environment = var.environment
> Application = var.cluster_name
> ```

---

### Outputs

| Output | HCL Type | Sensitive | Conditional | Description |
|---|---|---|---|---|
| `cluster_name` | `string` | no | always | EKS cluster name |
| `cluster_endpoint` | `string` | no | always | EKS API server URL — `[plan-unknown]` |
| `cluster_arn` | `string` | no | always | EKS cluster ARN — `[plan-unknown]` |
| `cluster_certificate_authority_data` | `string` | **yes** | always | Base64-encoded cluster CA — `[plan-unknown]` |
| `cluster_oidc_issuer_url` | `string` | no | always | OIDC issuer URL for IRSA trust policies — `[plan-unknown]` |
| `oidc_provider_arn` | `string` | no | always | OIDC provider ARN for IRSA `assume_role_policy` — `[plan-unknown]` |
| `cluster_security_group_id` | `string` | no | always | Cluster-managed security group ID — `[plan-unknown]` |
| `node_security_group_id` | `string` | no | always | Shared node security group ID — `[plan-unknown]` |
| `cluster_iam_role_arn` | `string` | no | always | IAM role ARN attached to EKS control plane — `[plan-unknown]` |
| `node_iam_role_arn` | `string` | no | always | IAM role ARN attached to managed nodes — `[plan-unknown]` |
| `worker_iam_role_arn` | `string` | no | always | Alias for `node_iam_role_arn` — preserved for design §3 contract compatibility |
| `worker_iam_role_name` | `string` | no | always | IAM role name attached to managed nodes — `[plan-unknown]` |
| `kms_policy_arn` | `string` | no | `kms_key_enabled = true`; `null` otherwise (via `try()`) | KMS key policy ARN — `[plan-unknown]` |
| `cloudwatch_log_group_name` | `string` | no | always | CloudWatch log group name for control-plane logs — `[plan-unknown]` |
| `vpc_id` | `string` | no | always | VPC ID — created or passed-through from `var.vpc_id` — `[plan-unknown]` |
| `private_subnet_ids` | `list(string)` | no | always | Private subnet IDs — created or passed-through from `var.private_subnet_ids` — `[plan-unknown]` |
| `public_subnet_ids` | `list(string)` | no | always | Public subnet IDs — created or passed-through from `var.public_subnet_ids` — `[plan-unknown]` |

---

### Provider & Terraform Requirements (`versions.tf`)

```hcl
terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}
```

> The module declares only the `aws` provider. Consumers must NOT place `provider {}` blocks inside this module — provider configuration is the consumer's responsibility (passed via `providers` argument if using aliased providers).

---

### Recommended Consumer Version Constraint

```hcl
module "eks_bob" {
  source  = "app.terraform.io/jose-merchan/eks-bob/aws"
  version = "~> 0.1"
  # ...
}
```

`~> 0.1` pins to `>= 0.1.0, < 0.2.0`. It allows patch-level bug fixes within the `0.1.x` series but prevents breaking changes that would arrive in `0.2.0`. Since `0.1.0` is the only published version, this is the safe pessimistic constraint.

---

### Minimum Consumer Block Example

```hcl
module "eks_bob" {
  source  = "app.terraform.io/jose-merchan/eks-bob/aws"
  version = "~> 0.1"

  # Required — no defaults
  cluster_name        = "my-cluster"
  kubernetes_version  = "1.32"
  environment         = "dev"
  node_instance_types = ["t3.medium"]
  node_min_size       = 1
  node_max_size       = 3
  node_desired_size   = 2

  # VPC is auto-created; secure defaults apply for all other variables
}
```

### BYO-VPC Consumer Block Example

```hcl
module "eks_bob" {
  source  = "app.terraform.io/jose-merchan/eks-bob/aws"
  version = "~> 0.1"

  cluster_name        = "my-cluster"
  kubernetes_version  = "1.32"
  environment         = "prod"
  node_instance_types = ["m5.large"]
  node_min_size       = 2
  node_max_size       = 10
  node_desired_size   = 3

  # BYO-VPC — set vpc_id to skip VPC creation
  vpc_id             = data.aws_vpc.existing.id
  private_subnet_ids = data.aws_subnets.private.ids
  public_subnet_ids  = data.aws_subnets.public.ids
}
```

---

### Rationale

All findings are sourced directly from the module's root-level HCL files in the `Bob_Demo_Terraform` workspace:

- [`variables.tf`](../../variables.tf) — 27 variables (7 required, 20 optional); every validation block read verbatim
- [`outputs.tf`](../../outputs.tf) — 17 outputs; `kms_policy_arn` uses `try(..., null)` making it nullable; `cluster_certificate_authority_data` is `sensitive = true`
- [`locals.tf`](../../locals.tf) — `create_vpc` is auto-derived (`vpc_id == null || vpc_id == ""`), not a consumer input
- [`main.tf`](../../main.tf) — `endpoint_private_access = true` is hardcoded; VPC subnet tags for EKS LB controller autodiscovery applied internally; `update_config.max_unavailable = 1` hardcoded in node group
- [`versions.tf`](../../versions.tf) — `terraform >= 1.7`, `hashicorp/aws >= 5.0`

---

### Alternatives Considered

| Alternative | Why Not |
|---|---|
| Raw `aws_eks_cluster` + `aws_vpc` resources in consumer code | Constitution prohibits raw resources in consumer code; this module already wraps them |
| `version = "= 0.1.0"` exact pin | Too restrictive — prevents patch-level fixes; `~> 0.1` is standard pessimistic practice |
| `version = ">= 0.1"` | Allows future `0.2.0` breaking changes; `~> 0.1` is safer |
| Separate VPC and EKS modules called by consumer | More consumer complexity; `eks-bob` already composes both with correct wiring (subnet tags, `depends_on`) |

---

### Sources

- [`variables.tf`](../../variables.tf) — complete variable definitions with validations
- [`outputs.tf`](../../outputs.tf) — complete output definitions with sensitivity markers
- [`locals.tf`](../../locals.tf) — `create_vpc` derivation and subnet resolution logic
- [`main.tf`](../../main.tf) — module composition wiring, hardcoded security values
- [`versions.tf`](../../versions.tf) — Terraform and provider floor requirements
- [`specs/001-eks-cluster-bob/design.md`](../001-eks-cluster-bob/design.md) — module design intent and Security Hub control mapping
