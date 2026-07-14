## Research: Consumer HCL Code Structure for Single-Module EKS Deployment

### Decision

Use a single `module "eks_cluster"` call against `app.terraform.io/jose-merchan/eks-bob/aws` with seven required variables
exposed at the consumer level; no cross-module wiring is needed because VPC provisioning is encapsulated inside the module
when `vpc_id` is omitted.

---

### Modules Identified

- **Primary Module**: `app.terraform.io/jose-merchan/eks-bob/aws` v0.0.1
  - **Purpose**: Full EKS cluster with embedded VPC (auto-created when `vpc_id = null`), managed node group, KMS secrets
    encryption, CloudWatch control-plane logging, and OIDC/IRSA — all with secure defaults
  - **Key Inputs** (required, no defaults):
    - `cluster_name` — `string`, 1–100 chars, alphanumeric/hyphen/underscore
    - `kubernetes_version` — `string`, `MAJOR.MINOR` format (e.g. `"1.32"`)
    - `environment` — `string`, enum `dev|staging|prod|sandbox`
    - `node_instance_types` — `list(string)`, ≥ 1 type (e.g. `["t3.medium"]`)
    - `node_min_size` — `number`, ≥ 1
    - `node_max_size` — `number`, ≥ 1
    - `node_desired_size` — `number`, ≥ 1
  - **Key Inputs** (optional with secure defaults):
    - `vpc_id` — `string`, default `null` → auto-creates VPC
    - `vpc_cidr` — `string`, default `"10.0.0.0/16"`
    - `availability_zones` — `list(string)`, default `[]` → AWS auto-discovery
    - `public_subnet_cidrs` — `list(string)`, default `["10.0.101.0/24","10.0.102.0/24"]`
    - `private_subnet_cidrs` — `list(string)`, default `["10.0.1.0/24","10.0.2.0/24"]`
    - `one_nat_gateway_per_az` — `bool`, default `false`
    - `enable_vpc_flow_logs` — `bool`, default `false`
    - `cluster_endpoint_public_access` — `bool`, default `false` (Security Hub EKS.1)
    - `cluster_endpoint_public_access_cidrs` — `list(string)`, default `["0.0.0.0/0"]`
    - `kms_key_enabled` — `bool`, default `true` (Security Hub EKS.3)
    - `cluster_log_types` — `list(string)`, default all five types (Security Hub EKS.8)
    - `cluster_log_retention_in_days` — `number`, default `90`
    - `enable_irsa` — `bool`, default `true`
    - `authentication_mode` — `string`, default `"API_AND_CONFIG_MAP"`
    - `node_capacity_type` — `string`, default `"ON_DEMAND"`
    - `node_disk_size` — `number`, default `20` GiB
    - `tags` — `map(string)`, default `{}`
  - **Key Outputs** (surfaced by the module):
    - `cluster_name` — `string`
    - `cluster_endpoint` — `string`
    - `cluster_arn` — `string`
    - `cluster_certificate_authority_data` — `string` (sensitive)
    - `cluster_oidc_issuer_url` — `string`
    - `oidc_provider_arn` — `string`
    - `cluster_security_group_id` — `string`
    - `node_security_group_id` — `string`
    - `cluster_iam_role_arn` — `string`
    - `node_iam_role_arn` — `string`
    - `worker_iam_role_arn` — `string` (alias for `node_iam_role_arn`)
    - `worker_iam_role_name` — `string`
    - `kms_policy_arn` — `string` (null when KMS disabled)
    - `cloudwatch_log_group_name` — `string`
    - `vpc_id` — `string`
    - `private_subnet_ids` — `list(string)`
    - `public_subnet_ids` — `list(string)`
  - **Secure Defaults**: private endpoint only, KMS CMK encryption, all 5 control-plane log types at 90-day retention,
    IRSA enabled, API+ConfigMap auth mode

- **Supporting Modules**: none — VPC is internally composed inside `eks-bob`
- **Glue Resources Needed**: none — single module call, no cross-module wiring
- **Wiring Considerations**: No module-to-module wiring. All consumer variables pass directly into
  `module "eks_cluster"` inputs. Consumer outputs are direct passthroughs from `module.eks_cluster.<output>`.

---

### File Structure

Per the consumer constitution (`.bob/skills/tf-consumer-constitution/SKILL.md` §2.1), the mandatory file layout is:

```
/
├── main.tf                          # Single module "eks_cluster" call
├── variables.tf                     # All consumer variable declarations
├── outputs.tf                       # Surfaced module outputs
├── locals.tf                        # Naming locals (project/env prefix if needed)
├── versions.tf                      # terraform{} block — required_version + required_providers
├── providers.tf                     # aws provider with default_tags + dynamic credentials
├── backend.tf                       # cloud{} block for HCP Terraform
└── terraform.auto.tfvars.example    # Example values for all variables
```

Note: `data.tf` is not needed — the consumer does not call any data sources directly (AZ discovery is
internal to the module).

---

### Provider Configuration Pattern

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

  # Dynamic credentials via HCP Terraform — no static key/secret variables
  # assume_role { role_arn = var.deploy_role_arn }  # If cross-account
}
```

Key rules (constitution §3.1):
- **No static credential variables** (`AWS_ACCESS_KEY_ID`, etc.) — HCP Terraform dynamic provider credentials only
- `default_tags` block MUST include `ManagedBy = "terraform"`, `Environment`, `Project`, `Owner`
- Cross-account access uses `assume_role` block in the provider, not environment variables

---

### versions.tf Pattern

```hcl
# versions.tf
terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
```

Note: constitution §4.1 requires `~>` (pessimistic constraint) for providers in consumers.
The module itself requires `>= 5.0`; the consumer uses `~> 5.0` for stability.

---

### backend.tf Pattern

```hcl
# backend.tf
terraform {
  cloud {
    organization = "jose-merchan"

    workspaces {
      project = "bob-demo-eks"
      name    = "bob-demo-eks-dev"   # or environment-specific name
    }
  }
}
```

Note: constitution §4.2 — `cloud {}` block is the ONLY backend type permitted.

---

### main.tf Pattern (single module call)

```hcl
# main.tf
module "eks_cluster" {
  source  = "app.terraform.io/jose-merchan/eks-bob/aws"
  version = "~> 0.0"

  # Required inputs
  cluster_name       = var.cluster_name
  kubernetes_version = var.kubernetes_version
  environment        = var.environment

  # Node group sizing
  node_instance_types = var.node_instance_types
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
  node_desired_size   = var.node_desired_size

  # Tags merged with provider default_tags
  tags = {
    Owner = var.owner
  }
}
```

Secure defaults honored implicitly (no overrides needed for private endpoint, KMS, logging, IRSA).

---

### Consumer Variables to Expose

Drawn from required module inputs plus deployment-level concerns:

| Variable | Type | Required | Default | Validation Rule | Sensitive | Description |
|---|---|---|---|---|---|---|
| `aws_region` | `string` | No | `"us-east-1"` | -- | No | AWS region to deploy into |
| `project_name` | `string` | No | `"bob-demo-eks"` | -- | No | Project name for `default_tags` and workspace label |
| `owner` | `string` | No | `"platform-team"` | -- | No | Owner tag value for cost allocation |
| `cluster_name` | `string` | Yes | -- | 1–100 chars, `^[a-zA-Z0-9_-]+$` | No | Name of the EKS cluster |
| `kubernetes_version` | `string` | No | `"1.32"` | `^[0-9]+\.[0-9]+$` | No | Kubernetes control-plane version |
| `environment` | `string` | No | `"dev"` | `dev\|staging\|prod\|sandbox` | No | Deployment environment identifier |
| `node_instance_types` | `list(string)` | No | `["t3.medium"]` | ≥ 1 element | No | EC2 instance types for managed node group |
| `node_min_size` | `number` | No | `1` | ≥ 1 | No | Minimum node group size |
| `node_max_size` | `number` | No | `3` | ≥ 1 | No | Maximum node group size |
| `node_desired_size` | `number` | No | `2` | ≥ 1 | No | Desired node count at creation |

All VPC and security inputs can remain at module defaults for the basic deployment — they need not be surfaced unless
the operator needs to override them.

---

### Outputs to Surface

Drawn from the module's declared outputs (`outputs.tf`) and the complete example (`examples/complete/outputs.tf`).
Priority outputs are those consumed by CI/CD, kubeconfig generation, IRSA trust policy authoring, and monitoring.

| Output | Type | Source Expression | Sensitive | Description |
|---|---|---|---|---|
| `cluster_name` | `string` | `module.eks_cluster.cluster_name` | No | EKS cluster name — used in kubeconfig and CLI commands |
| `cluster_endpoint` | `string` | `module.eks_cluster.cluster_endpoint` | No | API server URL — required for kubeconfig |
| `cluster_arn` | `string` | `module.eks_cluster.cluster_arn` | No | Cluster ARN for IAM policy conditions |
| `cluster_certificate_authority_data` | `string` | `module.eks_cluster.cluster_certificate_authority_data` | **Yes** | Base64 CA data for kubeconfig — sensitive |
| `cluster_oidc_issuer_url` | `string` | `module.eks_cluster.cluster_oidc_issuer_url` | No | OIDC URL for IRSA trust policy subject claim |
| `oidc_provider_arn` | `string` | `module.eks_cluster.oidc_provider_arn` | No | OIDC provider ARN for IRSA IAM role trust policies |
| `cluster_security_group_id` | `string` | `module.eks_cluster.cluster_security_group_id` | No | Cluster SG — referenced when allowing cross-service access |
| `vpc_id` | `string` | `module.eks_cluster.vpc_id` | No | VPC ID — consumed by future modules added to this consumer |
| `private_subnet_ids` | `list(string)` | `module.eks_cluster.private_subnet_ids` | No | Private subnets — consumed by future RDS/cache modules |
| `cloudwatch_log_group_name` | `string` | `module.eks_cluster.cloudwatch_log_group_name` | No | Log group name for dashboard and alarm configuration |

`cluster_certificate_authority_data` MUST be marked `sensitive = true` (constitution §2.4).

---

### Wiring Diagram

Single-module topology — no cross-module wiring:

```
var.cluster_name        ──→ module.eks_cluster.cluster_name
var.kubernetes_version  ──→ module.eks_cluster.kubernetes_version
var.environment         ──→ module.eks_cluster.environment
var.node_instance_types ──→ module.eks_cluster.node_instance_types
var.node_min_size       ──→ module.eks_cluster.node_min_size
var.node_max_size       ──→ module.eks_cluster.node_max_size
var.node_desired_size   ──→ module.eks_cluster.node_desired_size

module.eks_cluster.cluster_endpoint                  ──→ output.cluster_endpoint
module.eks_cluster.cluster_certificate_authority_data ──→ output.cluster_certificate_authority_data (sensitive)
module.eks_cluster.cluster_oidc_issuer_url           ──→ output.cluster_oidc_issuer_url
module.eks_cluster.oidc_provider_arn                 ──→ output.oidc_provider_arn
module.eks_cluster.vpc_id                            ──→ output.vpc_id
module.eks_cluster.private_subnet_ids                ──→ output.private_subnet_ids
```

---

### Rationale

- `examples/basic/main.tf` and `examples/complete/main.tf` confirm the module call name is `module "eks_cluster"` and
  source is `app.terraform.io/jose-merchan/eks-cluster-bob/aws` (note: research task specifies `eks-bob/aws` — use
  the actual published name from the registry; examples show `eks-cluster-bob/aws` which should be verified at build
  time).
- `variables.tf` at workspace root shows all required inputs, their types, and validation rules — these were copied
  verbatim into the consumer variable table above.
- `outputs.tf` at workspace root enumerates all 17 module outputs; the consumer surfaces the 10 most operationally
  relevant ones.
- Consumer constitution §2.1 mandates the 8-file layout; §3.1 prohibits static credentials; §3.3 requires
  `default_tags` with four mandatory keys; §4.1 requires `~>` version constraints.
- The complete example (`examples/complete/outputs.tf`) independently confirms the same output subset pattern.

---

### Alternatives Considered

| Alternative | Why Not |
|---|---|
| Separate VPC module call at consumer level | `eks-bob` encapsulates VPC creation internally when `vpc_id = null` — adding a second module call would duplicate the VPC subnet logic and require manual wiring of `vpc_id`, `private_subnet_ids`, `public_subnet_ids` |
| Raw `aws_eks_cluster` resource + `aws_vpc` resources | Constitution §1.1 prohibits raw resources in consumers; module-first composition is mandatory |
| Exposing all 17 module outputs | Outputs that are only useful in multi-module compositions (e.g., `node_security_group_id`, `kms_policy_arn`, `worker_iam_role_arn`) are omitted to keep the consumer interface clean; they can be added later |
| `>= 5.0` provider constraint | Constitution §4.1 requires `~>` in consumers, not `>=` (which the module itself uses) |

---

### Sources

- `examples/basic/main.tf` — minimum viable module consumption pattern, module call name `eks_cluster`
- `examples/complete/main.tf` — all optional inputs, VPC/security/node overrides
- `examples/complete/outputs.tf` and `examples/basic/outputs.tf` — confirmed output passthroughs
- `variables.tf` (workspace root) — authoritative input types, defaults, and validation rules
- `outputs.tf` (workspace root) — authoritative list of all 17 module outputs with types
- `.bob/skills/tf-consumer-constitution/SKILL.md` — file layout, provider pattern, `default_tags`, version constraint,
  credential, tagging, and output requirements
- `specs/feat-consumer-uplift/demo/consumer-code/versions.tf.tpl` — concrete `cloud {}` + `required_providers` template
