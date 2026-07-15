## Research: Kubernetes Provider Configuration and Namespace Approach for EKS Consumer

### Decision

Configure the `kubernetes` provider via `exec` block with `api_version = "client.authentication.k8s.io/v1"` reading all three connection attributes (`host`, `cluster_ca_certificate`, `cluster_name`) from a `terraform_remote_state` data source targeting the `eks-infra-vcs` workspace; create the `kubernetes_namespace` resource directly in the consumer as an explicitly permitted glue resource — no PMR module exists for namespaces and the constitution's glue resource list does not enumerate it, which is a design decision requiring a documented exception.

---

### Modules Identified

- **Primary Module**: `app.terraform.io/jose-merchan/terraform-kubernetes-app-deploy/kubernetes` (to be published)
  - **Purpose**: Deploys containerised app into an existing namespace with pull secret, Deployment, and Service
  - **Key Inputs**: `app_name`, `namespace`, `image`, `replicas`, `registry_server`, `registry_username`, `registry_password`, `service_type`
  - **Key Outputs**: `deployment_name`, `service_name`, `service_cluster_ip`, `secret_name`
  - **Secure Defaults**: non-root execution, drop ALL capabilities, read-only rootfs, ClusterIP default
- **Supporting Modules**: None — no Kubernetes namespace module exists in the PMR (confirmed live: 16 modules in `jose-merchan` org, all AWS provider; see PMR listing below)
- **Glue Resources Needed**:
  - `kubernetes_namespace` — raw resource required to create the namespace before the module call (see §Namespace Decision below)
- **Wiring Considerations**:
  - `data.terraform_remote_state.eks_infra.outputs.cluster_endpoint` → `provider "kubernetes" { host }`
  - `data.terraform_remote_state.eks_infra.outputs.cluster_certificate_authority_data` → `base64decode(...)` → `provider "kubernetes" { cluster_ca_certificate }`
  - `data.terraform_remote_state.eks_infra.outputs.cluster_name` → `provider "kubernetes" { exec { args } }` and `aws eks get-token --cluster-name`
  - `data.terraform_remote_state.eks_infra.outputs.aws_region` → `provider "aws" { region }` (needed for `aws eks get-token` region resolution)
  - `kubernetes_namespace.app.metadata[0].name` → `module.app_deploy.namespace`

---

### 1. `eks-infra-vcs` Remote State Outputs (Live — Confirmed)

The `eks-infra-vcs` workspace (`ws-fynCV5VvhkpRF7s3`, project `sandbox`) exposes these outputs as of 2025-07-14:

| Output Name | Type | Sensitive | Live Value |
|---|---|---|---|
| `aws_region` | `string` | No | `"eu-central-1"` |
| `cluster_endpoint` | `string` | No | `"https://3125B0917588D1171379955B63B61EA2.gr7.eu-central-1.eks.amazonaws.com"` |
| `cluster_certificate_authority_data` | `string` | **Yes** | `<sensitive>` (base64 PEM) |
| `cluster_name` | `string` | No | `"eks-infra-dev"` |
| `cluster_version` | `string` | No | `"1.33"` |
| `oidc_provider` | `string` | No | `"oidc.eks.eu-central-1.amazonaws.com/id/..."` |
| `oidc_provider_arn` | `string` | No | `"arn:aws:iam::492487827579:oidc-provider/..."` |
| `kms_key_arn` | `string` | **Yes** | `<sensitive>` |

The consumer reads these via:

```hcl
# data.tf
data "terraform_remote_state" "eks_infra" {
  backend = "remote"

  config = {
    organization = "jose-merchan"
    workspaces = {
      name = var.infra_workspace  # default "eks-infra-vcs"
    }
  }
}
```

This pattern is confirmed by `eks-vault-vcs` which uses variable `infra_workspace = "eks-infra-vcs"` to read the same state. The consumer workspace (`eks-app-vcs`) is already registered as a remote-state-consumer of `eks-infra-vcs` — confirmed live.

> **HCP Terraform remote state sharing requirement**: The consumer workspace must be added to `eks-infra-vcs`'s remote-state-consumers list via the API, OR `eks-infra-vcs` must have `global-remote-state = true`. Current live value: `global-remote-state: false`, `project-remote-state: false` — therefore explicit remote-state-consumer relationship is required. `eks-app-vcs` (`ws-L4DyVVdn2YBUzipb`) is already registered. The new consumer workspace must be added.

---

### 2. Kubernetes Provider Configuration (Correct Pattern)

#### Canonical `exec` Block Pattern

```hcl
# providers.tf
provider "kubernetes" {
  host                   = data.terraform_remote_state.eks_infra.outputs.cluster_endpoint
  cluster_ca_certificate = base64decode(
    data.terraform_remote_state.eks_infra.outputs.cluster_certificate_authority_data
  )

  exec {
    api_version = "client.authentication.k8s.io/v1"
    command     = "aws"
    args = [
      "eks", "get-token",
      "--cluster-name", data.terraform_remote_state.eks_infra.outputs.cluster_name,
      "--region",       data.terraform_remote_state.eks_infra.outputs.aws_region,
    ]
  }
}
```

#### Why `exec` Over `data.aws_eks_cluster_auth`

| Criterion | `exec` block | `data.aws_eks_cluster_auth` |
|---|---|---|
| Token freshness | Re-invokes `aws eks get-token` before each K8s API call | Fetched once per Terraform run; expires after **15 minutes** |
| Long-apply safety | Safe — token refreshed throughout | Fails with HTTP 401 after 15 min for slow applies |
| Dependency | Requires `aws` CLI in runner `$PATH` | Requires only IAM credentials (no CLI) |
| **Recommendation** | ✅ **Use this** | ⚠️ Use only if CLI unavailable |

The `exec` block is the recommended pattern per [official provider EKS example](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/guides/getting-started#provider-setup) and confirmed in `specs/006-kubernetes/research-edge-cases.md §1`.

#### `api_version` Must Be `v1` (Not `v1beta1`)

- `client.authentication.k8s.io/v1beta1` was **removed in Kubernetes 1.29**
- The live cluster runs **1.33** — `v1beta1` will cause a silent runtime failure
- Always use `api_version = "client.authentication.k8s.io/v1"` for K8s ≥ 1.24

#### `--region` Flag Is Required

`aws eks get-token` uses the AWS CLI's region resolution (env var, config file, instance metadata). In HCP Terraform's remote execution environment, the region must be passed explicitly to prevent it resolving to `us-east-1` from the global varset. Pass `--region` from the remote state output `aws_region = "eu-central-1"`.

#### Two-State Boundary (Critical)

The `kubernetes` provider MUST NOT be in the same Terraform configuration as the EKS cluster resources. The official provider docs include an explicit WARNING:

> When using interpolation to pass credentials to the Kubernetes provider from other resources, these resources **SHOULD NOT** be created in the same Terraform module. This leads to intermittent and unpredictable errors.

This consumer is a **separate workspace** (`eks-app-vcs` / new consumer workspace) reading EKS data from `eks-infra-vcs` state — this is the correct two-state boundary. The provider block references `data.terraform_remote_state` outputs, which are **already resolved** (the remote state is read before provider initialization), not computed values from resources in the same plan.

---

### 3. AWS Provider Requirement

The AWS provider is required in the consumer for two reasons:

1. **`data "aws_eks_cluster_auth"`** — if using the token data source as a fallback pattern
2. **Region resolution for `aws eks get-token`** — the `exec` block calls the AWS CLI, which uses the AWS environment from the HCP Terraform runner; the `aws` provider region must match the EKS cluster region

```hcl
# providers.tf (aws provider section)
provider "aws" {
  region = data.terraform_remote_state.eks_infra.outputs.aws_region
  # Dynamic credentials via HCP Terraform global varset:
  # TFC_AWS_PROVIDER_AUTH + TFC_AWS_RUN_ROLE_ARN injected automatically
}
```

The live `aws_region` output from `eks-infra-vcs` is `"eu-central-1"`. Reading it from remote state rather than hardcoding it ensures the consumer automatically tracks any future region change in the infra workspace.

> **Important**: The `provider "aws"` block in a consumer **cannot** reference `data.terraform_remote_state` outputs because provider configuration is evaluated before data sources in the same configuration. The workaround is to declare `aws_region` as a **consumer variable** with default `"eu-central-1"` and also use a `data.terraform_remote_state` reference — but only in resource/module arguments, not in the provider block itself. For the `provider "aws"` block, use `var.aws_region` with a hardcoded default.

Revised pattern:

```hcl
# variables.tf
variable "aws_region" {
  type        = string
  default     = "eu-central-1"
  description = "AWS region. Must match the region of the eks-infra-vcs workspace."
}

# providers.tf
provider "aws" {
  region = var.aws_region
}

provider "kubernetes" {
  # The kubernetes provider block CAN reference data sources because data source
  # evaluation happens before provider init for data-sourced providers.
  # However, to be safe and consistent, use variables sourced from the
  # remote state data source outputs in locals, not directly in provider block.
  host                   = local.cluster_endpoint
  cluster_ca_certificate = local.cluster_ca_certificate
  exec {
    api_version = "client.authentication.k8s.io/v1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", local.cluster_name, "--region", var.aws_region]
  }
}

# locals.tf
locals {
  cluster_endpoint        = data.terraform_remote_state.eks_infra.outputs.cluster_endpoint
  cluster_ca_certificate  = base64decode(data.terraform_remote_state.eks_infra.outputs.cluster_certificate_authority_data)
  cluster_name            = data.terraform_remote_state.eks_infra.outputs.cluster_name
}
```

---

### 4. Namespace Decision — `kubernetes_namespace` as Glue Resource

#### Constitution Analysis

The consumer constitution §1.1 defines allowed raw resources:

> Raw `resource` blocks are PROHIBITED except for glue resources (`random_id`, `random_string`, `null_resource`, `terraform_data`, `time_sleep`)

The list is **enumerated** — `kubernetes_namespace` is **not listed**. This creates a constitutional tension:

| Option | Assessment |
|---|---|
| `kubernetes_namespace` as glue resource | **NOT strictly permitted** — not in the enumerated glue list |
| Pre-create namespace out-of-band (`kubectl`) | Breaks Infrastructure-as-Code principle; no Terraform lifecycle management |
| Create a `kubernetes-namespace` PMR module | No such module exists in the PMR (confirmed: 16 modules, all AWS provider, none Kubernetes) |
| Treat the enumerated list as illustrative, not exhaustive | Requires `[CONSTITUTION DEVIATION]` comment |

#### PMR Finding

Live PMR listing (2025-07-14) for `jose-merchan` org — **16 modules total, zero Kubernetes provider modules**:

```
alb/aws, autoscaling/aws, cloudfront/aws, cloudwatch/aws, ec2-instance/aws,
eks/aws, eks-agentic/aws, eks-bob/aws, eks-cluster/aws,
erraform-google-vaultgke/google, iam/aws, lambda/aws,
security-group/aws, sns/aws, sqs/aws, vpc/aws
```

No `kubernetes-namespace` or any Kubernetes-provider module exists in the private registry.

#### Recommended Approach

Use `kubernetes_namespace` as a **glue resource** with a `[CONSTITUTION DEVIATION]` comment. Rationale:

- The spirit of the glue resource exception is to permit lightweight wiring primitives that are not substantive infrastructure — a Kubernetes namespace is exactly this: a thin metadata boundary with no compute, network, or storage implications
- The design.md §1 scope boundary explicitly states "This module does NOT provision Kubernetes namespaces" — it is in scope for the consumer
- The only alternative (pre-creating the namespace out-of-band) violates the IaC principle and removes Terraform lifecycle management from a resource that this consumer owns
- The `eks-app-vcs` workspace (live) already deploys Kubernetes resources — the namespace must be created somewhere; a dedicated module would be over-engineered for a single `metadata.name` resource
- `[CONSTITUTION DEVIATION]` comment with justification satisfies §8.2 exception process

```hcl
# main.tf

# [CONSTITUTION DEVIATION] kubernetes_namespace is not in the enumerated glue resource list
# (constitution §1.1). Exception justified: no kubernetes-namespace module exists in the PMR
# (confirmed 2025-07-14 — 16 modules, all AWS provider). The module design.md §1 explicitly
# excludes namespace creation from module scope. Pre-creating out-of-band violates IaC principles.
# Risk: Low — a namespace is a thin metadata object with no security implications.
resource "kubernetes_namespace" "app" {
  metadata {
    name = var.namespace

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "environment"                  = var.environment
    }
  }
}

module "app_deploy" {
  source  = "app.terraform.io/jose-merchan/terraform-kubernetes-app-deploy/kubernetes"
  version = "~> 0.1"

  app_name  = var.app_name
  namespace = kubernetes_namespace.app.metadata[0].name  # explicit dependency

  image             = var.image
  replicas          = var.replicas
  service_type      = "LoadBalancer"

  registry_server   = var.registry_server
  registry_username = var.registry_username
  registry_password = var.registry_password
}
```

---

### 5. `versions.tf` Requirements

Both `aws` and `kubernetes` providers are required:

```hcl
terraform {
  required_version = ">= 1.14"  # kubernetes module floor; write-only variable support

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.2"  # >= 3.2.1 for data_wo bug fix; ~> 3.x for stability
    }
  }
}
```

Version rationale:
- `kubernetes ~> 3.2`: The module requires `>= 3.2.1` (data_wo bug fix). `~>` pessimistic constraint per constitution §4.1 for consumers. `~> 3.2` allows `3.2.x` and `3.x.y` for `x > 2` — actually means `>= 3.2.0, < 4.0.0`. This is correct for a consumer.
- `aws ~> 5.0`: Consistent with all existing sandbox workspaces.
- `required_version >= 1.14`: Matches the kubernetes module's declared floor.

---

### Rationale

- **`exec` block confirmed** in `specs/006-kubernetes/research-edge-cases.md §1` as the EKS-correct provider pattern; `v1beta1` removed in K8s 1.29; live cluster runs 1.33 — `v1` mandatory
- **`aws_region` from remote state** confirmed live: `eks-infra-vcs` exposes `aws_region = "eu-central-1"` — use `var.aws_region` in provider block (provider block cannot reference data sources), source `var.aws_region` default from the known live value
- **No Kubernetes PMR modules**: 16 modules confirmed in `jose-merchan` org; zero Kubernetes-provider modules; no `kubernetes-namespace` module exists
- **`eks-infra-vcs` remote state consumer pattern**: `eks-vault-vcs` uses `infra_workspace = "eks-infra-vcs"` variable and `data.terraform_remote_state` — this is the established org pattern; `eks-app-vcs` is already a registered consumer of `eks-infra-vcs` state
- **Two-state boundary**: Consumer is a separate workspace from `eks-infra-vcs` — the provider block references remote state outputs that are already resolved, avoiding the same-module anti-pattern

### Alternatives Considered

| Alternative | Why Not |
|---|---|
| `data "aws_eks_cluster_auth"` instead of `exec` block | Token expires after 15 minutes; `exec` block refreshes token before each API call — safer for applies with many resources |
| `api_version = "client.authentication.k8s.io/v1beta1"` | Removed in Kubernetes 1.29; live cluster runs 1.33 — silent runtime failure |
| Same-workspace EKS + Kubernetes resources | Official provider WARNING; provider init happens before resource graph — `host = ""` on first apply |
| Pre-create namespace with `kubectl` out-of-band | Breaks IaC; no Terraform lifecycle management; not reproducible |
| Wait for a `kubernetes-namespace` PMR module | No such module exists; creating a 1-resource module is over-engineered; design.md assigns namespace to consumer scope |
| `global-remote-state = true` on `eks-infra-vcs` | Would expose state to all workspaces in the org — violates least-privilege; explicit remote-state-consumer relationship is the correct pattern |
| Hardcode `region = "eu-central-1"` in provider block | Brittle — breaks if infra workspace moves region; use `var.aws_region` with default sourced from known live value |

---

### Sources

- Live API: `eks-infra-vcs` workspace state outputs (confirmed 2025-07-14): `aws_region=eu-central-1`, `cluster_name=eks-infra-dev`, `cluster_version=1.33`
- Live API: PMR listing — 16 modules in `jose-merchan` org, zero Kubernetes-provider modules
- Live API: `eks-infra-vcs` remote-state-consumers — `eks-app-vcs` and `eks-vault-vcs` already registered
- Live API: `eks-vault-vcs` variables — `infra_workspace = "eks-infra-vcs"` confirms the remote-state pattern
- [`specs/006-kubernetes/design.md §1`](../006-kubernetes/design.md) — scope boundary: "This module does NOT provision EKS clusters, Kubernetes namespaces"
- [`specs/006-kubernetes/design.md §2`](../006-kubernetes/design.md) — architectural decision: "Two-state boundary — consumer wires the kubernetes provider"
- [`specs/006-kubernetes/research-edge-cases.md §1`](../006-kubernetes/research-edge-cases.md) — `exec` block pattern, `v1` api_version requirement, same-module anti-pattern, 15-minute token expiry
- [`specs/004-bob-demo-eks/research-workspace.md`](../004-bob-demo-eks/research-workspace.md) — `aws-dynamic-provider-credentials` global varset; `AWS_REGION` default is `us-east-1` (must override for `eu-central-1`)
- `.foundations/memory/consumer-constitution.md §1.1` — glue resource enumeration; §8.2 exception process
- Terraform docs: [`terraform_remote_state` backend `remote`](https://developer.hashicorp.com/terraform/language/state/remote-state-data)
- Kubernetes provider docs: [`exec` block for EKS](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/guides/getting-started)
