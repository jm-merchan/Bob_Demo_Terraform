## Research: HCP Terraform Workspace Configuration for `eks-bob/aws` Consumer in `sandbox` Project

### Decision

Create workspace `sandbox-bob-demo-eks` in the existing `sandbox` project (`prj-cJR1vdDjwGbiHqzE`) with
`remote` execution mode, Terraform `~> 1.12.0`, and no manual variable set assignment — the
`aws-dynamic-provider-credentials` varset is **global** and auto-applies to every workspace in the org.
A workspace-level `TFC_AWS_RUN_ROLE_ARN` override is **required** only if the consumer must deploy into a
different account or role; the global varset already points to `arn:aws:iam::492487827579:role/hcp-terraform-dynamic-admin`.
The `AWS_REGION` in the global varset is `us-east-1`; for `eu-west-1` the consumer must supply the override
either as a workspace variable or via `var.aws_region` in Terraform code.

---

### Org Structure (live, as of research date)

#### Projects

| Project Name      | Project ID                |
|-------------------|---------------------------|
| `Default Project` | `prj-PmbVsprg8DoogHW7`    |
| `sandbox`         | `prj-cJR1vdDjwGbiHqzE`    |

#### Variable Sets

| Varset Name                       | Varset ID                  | Scope  |
|-----------------------------------|----------------------------|--------|
| `DataDog Provider Vars`           | `varset-m1Vw16WvsguFAHCL`  | scoped |
| `aws-dynamic-provider-credentials`| `varset-8U26zCRUDWXf3zkL`  | **global** |

#### `aws-dynamic-provider-credentials` Variable Set Contents

| Variable                  | Category | Sensitive | Value                                                          |
|---------------------------|----------|-----------|----------------------------------------------------------------|
| `TFC_AWS_PROVIDER_AUTH`   | `env`    | no        | `"true"`                                                       |
| `TFC_AWS_RUN_ROLE_ARN`    | `env`    | no        | `"arn:aws:iam::492487827579:role/hcp-terraform-dynamic-admin"` |
| `AWS_REGION`              | `env`    | no        | `"us-east-1"` ⚠️ consumer target is `eu-west-1` — see below  |

Because `global = true`, these env vars are injected into every workspace automatically — no explicit varset
assignment is needed when creating `sandbox-bob-demo-eks`.

---

### Existing Sandbox Workspaces (reference pattern)

All workspaces in `prj-cJR1vdDjwGbiHqzE` share these settings:

| Workspace           | Execution Mode | Terraform Version | Auto-Apply | Working Dir                  | VCS Repo                                    |
|---------------------|----------------|-------------------|------------|------------------------------|---------------------------------------------|
| `eks-dev-test-vcs`  | `remote`       | `~> 1.12.0`       | `true`     | `deployments/eks-dev-test`   | `jm-merchan/terraform-aws-eks-cluster@main` |
| `eks-dev-test-cli`  | `remote`       | `~> 1.12.0`       | `false`    | `deployments/eks-dev-test-cli`| `jm-merchan/terraform-aws-eks-cluster@main` |
| `eks-vault-vcs`     | `remote`       | `~> 1.12.0`       | `true`     | *(root)*                     | `jm-merchan/terraform-aws-vault-app@main`   |
| `eks-infra-vcs`     | `remote`       | `~> 1.12.0`       | `true`     | *(root)*                     | `jm-merchan/terraform-aws-eks-infra@main`   |

**Pattern derived**: execution mode is always `remote`; Terraform version is `~> 1.12.0`; CLI-driven workspaces
set `auto_apply = false`; VCS workspaces use the GitHub App (`ghain-HWJpTEomJJGi1d4r`).

---

### New Workspace Specification: `sandbox-bob-demo-eks`

| Setting              | Value                                        | Notes                                                                              |
|----------------------|----------------------------------------------|------------------------------------------------------------------------------------|
| Organization         | `jose-merchan`                               | HCP Terraform org                                                                  |
| Workspace Name       | `sandbox-bob-demo-eks`                       | Follows `<project>-<feature>` naming pattern                                       |
| Project              | `sandbox` (`prj-cJR1vdDjwGbiHqzE`)          | Existing project; target for all EKS sandbox workloads                            |
| Execution Mode       | `remote`                                     | Consistent with all other sandbox workspaces                                      |
| Terraform Version    | `~> 1.12.0`                                  | Consistent with existing sandbox workspaces                                       |
| Auto-Apply           | `false`                                      | CLI-driven deployment; operator reviews plan before apply                          |
| Working Directory    | *(root of consumer repo)*                    | Consumer will be a standalone repo/directory, not a subdirectory                  |
| VCS Connection       | None initially (CLI-driven)                  | Can be upgraded to VCS later by attaching GitHub App repo                         |
| Variable Sets        | `aws-dynamic-provider-credentials` (global)  | Auto-applied — no explicit assignment step required                               |
| Workspace Variables  | `AWS_REGION = eu-west-1` (env, override)     | **Required** — overrides the global varset's `us-east-1` default for this workspace|

---

### Region Override: Workspace-Level Variable

The global varset sets `AWS_REGION = us-east-1`. Since the consumer must deploy to `eu-west-1`, a
workspace-level environment variable must be set on `sandbox-bob-demo-eks`:

```
Key:      AWS_REGION
Value:    eu-west-1
Category: env
Sensitive: false
```

Workspace-level variables take precedence over varset variables in HCP Terraform.

Alternatively, the consumer can pass `region = "eu-west-1"` explicitly in the `provider "aws"` block
and source it from a Terraform variable — this removes dependency on the env var override and is the
recommended approach for explicit, reviewable configuration.

---

### Dynamic Credentials: How It Works

HCP Terraform injects the following into each plan/apply run for the workspace:

1. `TFC_AWS_PROVIDER_AUTH = "true"` — activates the dynamic credentials handshake
2. `TFC_AWS_RUN_ROLE_ARN = "arn:aws:iam::492487827579:role/hcp-terraform-dynamic-admin"` — role assumed per-run
3. `AWS_REGION = eu-west-1` (workspace override) — provider region

The AWS provider automatically exchanges a short-lived OIDC token for STS credentials via
`AssumeRoleWithWebIdentity`. **No static `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY` variables are
required or permitted** in the consumer code (consumer constitution §3.1).

The `provider "aws"` block in the consumer does NOT need an `assume_role {}` block — the dynamic
credentials mechanism handles it at the Terraform Cloud agent level.

---

### `cloud {}` Block (backend.tf)

Based on the existing workspace template at
[`specs/feat-consumer-uplift/demo/consumer-code/versions.tf.tpl`](../feat-consumer-uplift/demo/consumer-code/versions.tf.tpl)
and org/project IDs confirmed live:

```hcl
# backend.tf
terraform {
  cloud {
    organization = "jose-merchan"
    hostname     = "app.terraform.io"

    workspaces {
      name    = "sandbox-bob-demo-eks"
      project = "sandbox"
    }
  }
}
```

> **Note**: `hostname` defaults to `app.terraform.io` if omitted; include it explicitly for clarity per the
> established org template. `project` must match the exact HCP Terraform project name (`"sandbox"`) not the ID.

---

### `versions.tf` Pattern

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

> `required_version = ">= 1.7"` satisfies the module's floor constraint. The workspace-level pin
> `~> 1.12.0` controls the actual executor version; `>= 1.7` in code ensures compatibility with any
> operator running locally.

---

### `providers.tf` Pattern

```hcl
# providers.tf
provider "aws" {
  region = var.aws_region   # default "eu-west-1" in variables.tf

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = var.owner
    }
  }

  # Dynamic credentials are injected by HCP Terraform via TFC_AWS_PROVIDER_AUTH +
  # TFC_AWS_RUN_ROLE_ARN — no static keys, no assume_role {} block needed here.
}
```

Setting `aws_region` default to `"eu-west-1"` in [`variables.tf`] makes the deployment self-documenting
and means the workspace env var override for `AWS_REGION` is belt-and-suspenders rather than mandatory.

---

### Modules Identified

- **Primary Module**: `app.terraform.io/jose-merchan/eks-bob/aws` v0.1.0
  - **Purpose**: EKS cluster with embedded VPC, managed node group, KMS, CloudWatch, OIDC/IRSA
  - **Key Inputs**: `cluster_name`, `kubernetes_version`, `environment`, `node_instance_types`, sizing variables
  - **Key Outputs**: `cluster_endpoint`, `vpc_id`, `private_subnet_ids`, `oidc_provider_arn`
  - **Secure Defaults**: private endpoint, KMS CMK, all 5 control-plane log types, IRSA enabled

- **Supporting Modules**: none — VPC is internally composed inside `eks-bob`
- **Glue Resources Needed**: none
- **Wiring Considerations**: single module call; no cross-module output/input wiring required

---

### Rationale

- **Global varset confirmed**: `aws-dynamic-provider-credentials` has `global = true` — no action needed
  to attach it to the new workspace. This was verified directly via the HCP Terraform API.
- **Execution mode `remote`**: 100% of sandbox workspaces use `remote`; confirmed via workspace listing.
- **Terraform `~> 1.12.0`**: universal across all sandbox workspaces; adopt the same constraint.
- **Region override required**: the global varset value is `us-east-1`; the feature requires `eu-west-1`.
  Setting `region = var.aws_region` in the provider (defaulting to `"eu-west-1"`) is the explicit, auditable
  approach — the workspace env var is an additional safety net.
- **`cloud {}` in `backend.tf`**: consumer constitution §4.2 mandates `cloud {}` as the only backend type.
  The `versions.tf.tpl` template in the org confirms the exact attribute structure.

---

### Alternatives Considered

| Alternative                                 | Why Not                                                                                |
|---------------------------------------------|----------------------------------------------------------------------------------------|
| Assign varset explicitly                    | Varset is global — explicit assignment is redundant and would duplicate the binding   |
| `backend "s3"` backend                      | Consumer constitution §4.2 prohibits any backend other than `cloud {}`               |
| Rely solely on global `AWS_REGION=us-east-1`| Target region is `eu-west-1`; must override — either workspace var or provider config |
| `auto_apply = true`                         | CLI-driven workspace; operator must review plan — `false` is the safe default         |
| Place `cloud {}` inside `versions.tf`       | Org template (`versions.tf.tpl`) keeps `cloud {}` in a separate `backend.tf` — follow existing pattern |

---

### Sources

- Live API: `tfctl api /organizations/jose-merchan/projects` — project IDs and names
- Live API: `tfctl api /organizations/jose-merchan/varsets` — varset IDs and names
- Live API: `tfctl api /varsets/varset-8U26zCRUDWXf3zkL` — global scope confirmation
- Live API: `tfctl api /varsets/varset-8U26zCRUDWXf3zkL/relationships/vars` — variable keys and values
- Live API: `tfctl api /organizations/jose-merchan/workspaces` — sandbox workspace listing with execution modes
- [`specs/feat-consumer-uplift/demo/consumer-code/versions.tf.tpl`](../feat-consumer-uplift/demo/consumer-code/versions.tf.tpl) — `cloud {}` block structure template
- [HCP Terraform docs: Dynamic provider credentials for AWS](https://developer.hashicorp.com/terraform/cloud-docs/workspaces/dynamic-provider-credentials/aws-configuration)
- Consumer constitution §3.1 — no static credentials; §4.1 — `~>` constraints; §4.2 — `cloud {}` only backend
