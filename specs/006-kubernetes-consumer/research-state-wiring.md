## Research: eks-infra-vcs Outputs and `terraform_remote_state` Wiring

### Decision

Read EKS cluster coordinates from the `eks-infra-vcs` HCP Terraform workspace via
`data "terraform_remote_state" "eks"` pointing at org `jose-merchan` / workspace
`eks-infra-vcs`, then derive the `kubernetes` provider's `host`, `cluster_ca_certificate`,
and `token` from those outputs. The auth token comes from
`data "aws_eks_cluster_auth"` (AWS provider data source) using `cluster_name` from
remote state — not from static credentials. The new consumer workspace must be added
to `eks-infra-vcs` remote state consumers list as a post-deploy step
(since `global_remote_state = false`).

---

### Modules Identified

- **Primary Module**: none — this consumer wires providers and data sources to connect to
  an existing EKS cluster; it uses the `jose-merchan/kubernetes-app-deploy/kubernetes`
  private module (feature-006) for actual workload resources.
- **Supporting Modules**: none additional beyond the primary workload module.
- **Glue Resources Needed**: none (`random_id` / `terraform_data` not needed for state wiring).
- **Wiring Considerations**: Three data sources serve as the bridge between the
  `eks-infra-vcs` remote state and the `kubernetes` provider:
  1. `data.terraform_remote_state.eks` → reads all EKS outputs
  2. `data.aws_eks_cluster_auth.this` → exchanges `cluster_name` for a short-lived bearer token
  3. `provider "kubernetes"` → receives `host`, `cluster_ca_certificate`, and `token`

---

### Confirmed `eks-infra-vcs` Outputs (from state-version API)

These are the outputs that a consumer can reference via
`data.terraform_remote_state.eks.outputs.<key>`:

| Output key                           | Type             | Sensitive | Notes                                          |
|--------------------------------------|------------------|-----------|------------------------------------------------|
| `cluster_name`                       | `string`         | No        | Used to call `aws_eks_cluster_auth`             |
| `cluster_endpoint`                   | `string`         | No        | Kubernetes API server URL → `host`             |
| `cluster_certificate_authority_data` | `string`         | **Yes**   | Base64 CA cert → `cluster_ca_certificate`      |
| `aws_region`                         | `string`         | No        | Region for the `aws` provider alias            |
| `cluster_version`                    | `string`         | No        | K8s version string (e.g. `"1.32"`)             |
| `oidc_provider`                      | `string`         | No        | OIDC issuer URL for IRSA trust documents       |
| `oidc_provider_arn`                  | `string`         | No        | OIDC provider ARN for IAM role trust policies  |
| `kms_key_arn`                        | `string`         | **Yes**   | CMK ARN — consumed only if re-encrypting data  |

> **Cross-check against `consumers/004-bob-demo-eks/outputs.tf`**: The `eks-infra-vcs`
> workspace (which runs the same EKS infrastructure code) exposes outputs matching the
> names declared there. Note that `consumers/004-bob-demo-eks/outputs.tf` uses the key
> `cluster_oidc_issuer_url` while the live state-version API reports the key as
> `oidc_provider` — the consumer must reference the **actual state key name**
> (`oidc_provider`), not the local outputs.tf alias.

---

### HCL Pattern: `data "terraform_remote_state" "eks"`

```hcl
# data.tf
data "terraform_remote_state" "eks" {
  backend = "remote"

  config = {
    organization = "jose-merchan"
    workspaces = {
      name = "eks-infra-vcs"
    }
  }
}
```

**Attribute reference cheat sheet:**

```hcl
# Cluster coordinates — needed by the kubernetes provider
local.cluster_endpoint = data.terraform_remote_state.eks.outputs.cluster_endpoint
local.cluster_ca_cert  = data.terraform_remote_state.eks.outputs.cluster_certificate_authority_data
local.cluster_name     = data.terraform_remote_state.eks.outputs.cluster_name

# OIDC — needed for IRSA IAM role trust policies
local.oidc_provider_arn = data.terraform_remote_state.eks.outputs.oidc_provider_arn
local.oidc_issuer_url   = data.terraform_remote_state.eks.outputs.oidc_provider

# Region — can be used to configure a scoped AWS provider alias if needed
local.aws_region = data.terraform_remote_state.eks.outputs.aws_region
```

---

### HCL Pattern: `data "aws_eks_cluster_auth"` — Kubernetes Auth Token

The `kubernetes` provider requires a bearer token. For EKS, the canonical source is
`data "aws_eks_cluster_auth"`, which calls STS `GetCallerIdentity` behind the scenes and
returns a short-lived (15-minute) token valid for the given cluster:

```hcl
# data.tf
data "aws_eks_cluster_auth" "this" {
  name = data.terraform_remote_state.eks.outputs.cluster_name
}
```

**Output**: `data.aws_eks_cluster_auth.this.token` — `string`, sensitive.

> **Why this and not a static token**: EKS uses AWS IAM for authentication via the AWS
> IAM Authenticator protocol. There is no long-lived Kubernetes service-account token
> available at provisioning time for a fresh cluster. `aws_eks_cluster_auth` generates
> a pre-signed STS URL token (same as `aws eks get-token`) that the Kubernetes API server
> accepts via the `aws-iam-authenticator` webhook. The AWS provider's dynamic credentials
> (injected by HCP Terraform) provide the IAM identity that signs the token.

---

### HCL Pattern: `provider "kubernetes"` — EKS Wiring

```hcl
# providers.tf
provider "kubernetes" {
  host                   = data.terraform_remote_state.eks.outputs.cluster_endpoint
  cluster_ca_certificate = base64decode(
    data.terraform_remote_state.eks.outputs.cluster_certificate_authority_data
  )
  token = data.aws_eks_cluster_auth.this.token
}
```

**Why `base64decode()`?** The `cluster_certificate_authority_data` output from EKS is
already base64-encoded (the raw DER certificate encoded as base64). The
`kubernetes` provider's `cluster_ca_certificate` attribute expects the **PEM-decoded**
(raw DER bytes) certificate — i.e., the binary form. `base64decode()` unwraps the
base64 layer, yielding the certificate in the form the TLS library expects.

> **Anti-pattern warning** (from `specs/006-kubernetes/design.md` §2 Architectural
> Decisions): Do NOT configure the `kubernetes` provider from computed values of
> resources created in the **same** workspace on first apply — this triggers provider
> initialisation failures because the provider is initialised before the plan runs.
> Reading from `terraform_remote_state` is safe because the remote state is already
> settled before the plan begins.

---

### `exec` Alternative (not recommended for this pattern)

The `exec` block pattern (used in `examples/basic/` of the 006-kubernetes module) is
appropriate for **module examples** where the author controls the kubeconfig
environment. For a **consumer workspace on HCP Terraform** with dynamic credentials,
the `token = data.aws_eks_cluster_auth.this.token` pattern is simpler, does not require
the `aws` CLI binary to be present in the agent, and works natively with the AWS
provider's STS credentials:

```hcl
# Only use exec if aws_eks_cluster_auth is unavailable
exec {
  api_version = "client.authentication.k8s.io/v1"
  command     = "aws"
  args        = ["eks", "get-token", "--cluster-name", local.cluster_name, "--region", local.aws_region]
}
```

---

### `versions.tf` — Required Providers

```hcl
# versions.tf
terraform {
  required_version = ">= 1.14"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.2"   # >= 3.2.1 for data_wo bug fix; ~> 3.2 satisfies the floor
    }
  }
}
```

> **Note on AWS provider version**: `consumers/004-bob-demo-eks/versions.tf` pins
> `~> 6.52`. The new consumer inherits the same AWS account and region; use `~> 6.0`
> as a floor to allow point releases while staying on the v6 line.

---

### Remote State Consumer: Post-Deploy Step

`eks-infra-vcs` has `global_remote_state = false`. The new consumer workspace **MUST**
be explicitly added as a remote state consumer **before** its first plan run — otherwise
`data "terraform_remote_state" "eks"` will return a 403.

**Current remote state consumers on `eks-infra-vcs` (ws-fynCV5VvhkpRF7s3):**

| Workspace ID           | Workspace Name    |
|------------------------|-------------------|
| `ws-L4DyVVdn2YBUzipb`  | `eks-app-vcs`     |
| `ws-3MgtdSUWuLy9ktnL`  | `eks-vault-vcs`   |

**Required API call** (using TFE token from `~/.terraform.d/credentials.tfrc.json`):

```bash
# POST to add the new consumer workspace
curl -s -X POST \
  -H "Authorization: Bearer $TFE_TOKEN" \
  -H "Content-Type: application/vnd.api+json" \
  -d '{
    "data": [{
      "id": "<new-consumer-workspace-id>",
      "type": "workspaces"
    }]
  }' \
  "https://app.terraform.io/api/v2/workspaces/ws-fynCV5VvhkpRF7s3/relationships/remote-state-consumers"
```

Replace `<new-consumer-workspace-id>` with the workspace ID returned when the new
consumer workspace is created (e.g. `ws-xxxxxxxxxxxxxxxx`).

> This step is a **post-deploy** gate: create the consumer workspace → get its ID →
> add it as a remote state consumer → then trigger the first plan.

---

### Rationale

- **`data "terraform_remote_state"`** is the canonical HCP Terraform cross-workspace
  state reading mechanism. The `backend = "remote"` backend type with `organization`
  and `workspaces.name` is the correct config for HCP Terraform (Terraform Cloud)
  workspaces — confirmed from `specs/004-bob-demo-eks/research-workspace.md` and the
  HCP Terraform docs.
- **`aws_eks_cluster_auth`** is the AWS-provider-native way to obtain a Kubernetes
  bearer token for EKS; it requires only the cluster name and the ambient AWS credentials
  already provided by HCP Terraform dynamic credentials — no additional IAM policy
  beyond `eks:DescribeCluster` is needed.
- **`base64decode()` on CA data** is mandatory: the EKS API returns the CA as a
  base64 PEM string; the `kubernetes` provider `cluster_ca_certificate` expects decoded
  bytes. Omitting `base64decode()` causes TLS certificate parse errors at provider init.
- **`global_remote_state = false`** means the remote state read is blocked by default;
  an explicit relationship must be created via the Workspaces API before the first plan.

---

### Alternatives Considered

| Alternative                              | Why Not                                                                                      |
|------------------------------------------|----------------------------------------------------------------------------------------------|
| `exec` block with `aws eks get-token`    | Requires `aws` CLI binary in the HCP Terraform agent image; `aws_eks_cluster_auth` is native to the provider and simpler |
| Hardcode `cluster_endpoint` as a variable | Defeats the purpose of remote state; creates manual drift risk when cluster is recreated     |
| `data "aws_eks_cluster"` data source     | Fetches cluster metadata from AWS API — adds an extra API call and `eks:DescribeCluster` permission; redundant when the endpoint and CA are already in remote state |
| `global_remote_state = true` on eks-infra | Would expose eks-infra state to ALL workspaces in the org — violates least-privilege state access; not an option (controlled by the platform team on eks-infra-vcs) |
| KUBE_CONFIG_PATH env variable            | Not reproducible in HCP Terraform agents; no kubeconfig file is present in the agent environment |

---

### Sources

- `consumers/004-bob-demo-eks/outputs.tf` — EKS module outputs declared in the infra workspace
- `consumers/004-bob-demo-eks/README.md` — confirms workspace name `sandbox-bob-demo-eks`, project `sandbox`, org `jose-merchan`
- `consumers/004-bob-demo-eks/versions.tf` — AWS provider version `~> 6.52`
- `specs/004-bob-demo-eks/research-workspace.md` — HCP Terraform org/project IDs, workspace list, `eks-infra-vcs` workspace details
- `specs/006-kubernetes/design.md` §2 — same-module anti-pattern warning for kubernetes provider; `exec` block note in §6 Implementation Checklist step E
- `specs/006-kubernetes/research-provider-schema.md` — kubernetes provider `cluster_ca_certificate` expects PEM bytes
- Research task context: confirmed state-version API outputs, workspace ID `ws-fynCV5VvhkpRF7s3`, existing consumers `ws-L4DyVVdn2YBUzipb` and `ws-3MgtdSUWuLy9ktnL`
- HCP Terraform docs: [Remote State data source](https://developer.hashicorp.com/terraform/language/state/remote-state-data)
- AWS provider docs: [`aws_eks_cluster_auth`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/eks_cluster_auth)
- Kubernetes provider docs: [`provider` configuration](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs#authentication)
