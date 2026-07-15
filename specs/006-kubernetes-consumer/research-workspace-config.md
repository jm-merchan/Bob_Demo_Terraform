# Research: HCP Terraform Workspace Configuration for `k8s-app-demo-bob`

## Research: What HCP Terraform workspace configuration is needed for the new `k8s-app-demo-bob` consumer workspace?

### Decision

Create `k8s-app-demo-bob` in the **Default Project** (`prj-PmbVsprg8DoogHW7`) with execution mode `remote`, Terraform version `~> 1.15.0` (matching eks-app-vcs peer), three workspace-level Terraform variables for IBM ICR credentials, one workspace variable for the infra workspace name, and a POST to eks-infra-vcs remote-state-consumers after the workspace ID is known.

---

### Live API Findings (verified 2026-07-15)

#### Workspace: `eks-app-vcs` (ws-L4DyVVdn2YBUzipb) — reference peer

| Attribute | Value |
|---|---|
| ID | `ws-L4DyVVdn2YBUzipb` |
| Project | `prj-PmbVsprg8DoogHW7` (Default Project) |
| Execution mode | `remote` |
| Terraform version | `~> 1.15.0` |
| `global-remote-state` | `false` |
| `project-remote-state` | `false` |
| VCS repo | `jm-merchan/terraform-aws-eks-app` (GitHub App) |
| Workspace-level vars | **NONE** — `"vars": {"data": []}` confirmed empty |
| Variable sets attached | `varset-8U26zCRUDWXf3zkL` (aws-dynamic-provider-credentials, **global=true**) |
| Auto-apply | `true` |

**Key observation**: `eks-app-vcs` carries zero workspace-level variables. All AWS credential injection is handled entirely by the global varset `aws-dynamic-provider-credentials`. The kubernetes/app-specific variables (registry credentials, infra workspace name) are NOT present because this workspace sources them differently — they are absent from the remote peer at this time and must be set on the new workspace.

#### Workspace: `eks-infra-vcs` (ws-fynCV5VvhkpRF7s3) — infra dependency

| Attribute | Value |
|---|---|
| ID | `ws-fynCV5VvhkpRF7s3` |
| Project | `prj-cJR1vdDjwGbiHqzE` (**different project** — NOT Default Project) |
| Execution mode | `remote` |
| Terraform version | `~> 1.12.0` |
| `global-remote-state` | `false` ← **explicit consumer add required** |
| `project-remote-state` | `false` ← project boundary does NOT grant cross-workspace state access |

**Critical**: `eks-infra-vcs` lives in project `prj-cJR1vdDjwGbiHqzE` while `k8s-app-demo-bob` will live in `prj-PmbVsprg8DoogHW7`. Both `global-remote-state=false` and `project-remote-state=false` on eks-infra-vcs confirm that the new workspace MUST be explicitly added as a remote-state consumer.

#### eks-infra-vcs outputs (live state)

| Output | Type | Sensitive | Live Value |
|---|---|---|---|
| `aws_region` | `string` | No | `eu-central-1` |
| `cluster_certificate_authority_data` | `string` | **Yes** | `<sensitive>` |
| `cluster_endpoint` | `string` | No | `https://3125B0917588D1171379955B63B61EA2.gr7.eu-central-1.eks.amazonaws.com` |
| `cluster_name` | `string` | No | `eks-infra-dev` |
| `cluster_version` | `string` | No | `1.33` |
| `kms_key_arn` | `string` | **Yes** | `<sensitive>` |
| `oidc_provider` | `string` | No | `oidc.eks.eu-central-1.amazonaws.com/id/3125B0917588D1171379955B63B61EA2` |
| `oidc_provider_arn` | `string` | No | `arn:aws:iam::492487827579:oidc-provider/...` |

The consumer workspace's `data "terraform_remote_state"` block will consume `cluster_endpoint`, `cluster_certificate_authority_data`, `cluster_name`, and `aws_region`.

#### eks-infra-vcs existing remote-state consumers (live)

| Workspace | ID |
|---|---|
| `eks-app-vcs` | `ws-L4DyVVdn2YBUzipb` |
| `eks-vault-vcs` | `ws-3MgtdSUWuLy9ktnL` |

`k8s-app-demo-bob` must be added as a third consumer.

#### Variable sets (org-level, live)

| varset ID | Name | Global | var-count |
|---|---|---|---|
| `varset-8U26zCRUDWXf3zkL` | `aws-dynamic-provider-credentials` | **true** | 3 |
| `varset-m1Vw16WvsguFAHCL` | `DataDog Provider Vars` | false | 7 |

`aws-dynamic-provider-credentials` is **global=true** — it automatically applies to every workspace in the organization including `k8s-app-demo-bob`. No explicit varset attachment call is needed.

#### eks-vault-vcs variable pattern (reference for infra_workspace naming)

The `eks-vault-vcs` peer workspace uses a `infra_workspace = "eks-infra-vcs"` variable (category: terraform) to locate the remote state source. The same pattern should be applied to `k8s-app-demo-bob`.

---

### Workspace Configuration Specification

#### 1. Workspace Creation Parameters

```json
{
  "data": {
    "type": "workspaces",
    "attributes": {
      "name": "k8s-app-demo-bob",
      "execution-mode": "remote",
      "terraform-version": "~> 1.15.0",
      "auto-apply": true,
      "global-remote-state": false,
      "project-remote-state": false,
      "description": "Kubernetes app deployment (terraform-kubernetes-app-deploy module) — consumer of eks-infra-vcs remote state"
    },
    "relationships": {
      "project": {
        "data": {
          "type": "projects",
          "id": "prj-PmbVsprg8DoogHW7"
        }
      }
    }
  }
}
```

**API endpoint**: `POST https://app.terraform.io/api/v2/organizations/jose-merchan/workspaces`

**Terraform version rationale**: `~> 1.15.0` matches `eks-app-vcs` (the direct peer) and satisfies the module's `>= 1.14` requirement.

---

#### 2. Workspace Variables

All four variables use `category: "terraform"` (Terraform input variables, not env vars). Registry credentials are `sensitive: true` and `hcl: false`.

| Variable | Value | Category | Sensitive | HCL | Purpose |
|---|---|---|---|---|---|
| `registry_password` | `<IBM ICR API key>` | terraform | **true** | false | IBM ICR API key for `de.icr.io`; maps to `registry_password` in the module's `data_wo` |
| `registry_username` | `iamapikey` | terraform | false | false | IBM ICR username; fixed value for all IBM Cloud API-key auth |
| `registry_server` | `de.icr.io` | terraform | false | false | IBM ICR Frankfurt registry hostname |
| `infra_workspace` | `eks-infra-vcs` | terraform | false | false | Name of the eks-infra-vcs workspace; used in `data "terraform_remote_state"` backend config |

**Note**: `aws_region` does NOT need to be set as a workspace variable. The consumer reads it from eks-infra-vcs remote state output (`aws_region = "eu-central-1"`). No AWS region override is needed.

**API endpoint for each variable**: `POST https://app.terraform.io/api/v2/workspaces/<new-ws-id>/vars`

Example payload for `registry_password`:
```json
{
  "data": {
    "type": "vars",
    "attributes": {
      "key": "registry_password",
      "value": "<IBM_ICR_API_KEY>",
      "sensitive": true,
      "category": "terraform",
      "hcl": false,
      "description": "IBM ICR API key for de.icr.io registry authentication. Stored as write-only in module state via data_wo."
    }
  }
}
```

---

#### 3. Remote State Consumer Registration

After the workspace is created and its ID is known (`<NEW_WS_ID>`), add it as a consumer of `eks-infra-vcs`:

**API endpoint**: `POST https://app.terraform.io/api/v2/workspaces/ws-fynCV5VvhkpRF7s3/relationships/remote-state-consumers`

**Payload**:
```json
{
  "data": [
    {
      "id": "<NEW_WS_ID>",
      "type": "workspaces"
    }
  ]
}
```

This grants `k8s-app-demo-bob` permission to call `data "terraform_remote_state" "eks_infra" {}` referencing `ws-fynCV5VvhkpRF7s3`.

---

#### 4. Variable Set Attachment

**No action required.** `aws-dynamic-provider-credentials` (varset-8U26zCRUDWXf3zkL) has `global=true` and applies to all workspaces automatically. Confirmed by the live API: `eks-app-vcs` lists it under its varsets despite having zero workspace-level variables and no explicit attachment.

---

#### 5. Execution Mode & Terraform Version

| Setting | Value | Source |
|---|---|---|
| `execution-mode` | `remote` | Matches all peers (eks-app-vcs, eks-vault-vcs); required for HCP Terraform-managed runs |
| `terraform-version` | `~> 1.15.0` | Matches eks-app-vcs (peer in same Default Project); satisfies module constraint `>= 1.14` |
| `auto-apply` | `true` | Matches eks-app-vcs; standard for sandbox consumer workspaces |

**Note**: The `~>` constraint on `terraform-version` means HCP Terraform will pin to the latest `1.15.x` patch available at workspace creation time and auto-upgrade within the minor.

---

#### 6. Backend Configuration in Consumer HCL

The consumer's `backend.tf` (or `terraform { cloud {} }` block) must reference the correct project and workspace name:

```hcl
terraform {
  cloud {
    organization = "jose-merchan"
    hostname     = "app.terraform.io"

    workspaces {
      project = "Default Project"
      name    = "k8s-app-demo-bob"
    }
  }
}
```

**Note**: The project name in the `cloud {}` block is `"Default Project"` (human-readable name). The project ID `prj-PmbVsprg8DoogHW7` is only used in the API workspace creation call.

---

#### 7. Remote State Data Source in Consumer HCL

```hcl
data "terraform_remote_state" "eks_infra" {
  backend = "remote"

  config = {
    organization = "jose-merchan"
    workspaces = {
      name = var.infra_workspace   # "eks-infra-vcs"
    }
  }
}
```

Consumed outputs:
- `data.terraform_remote_state.eks_infra.outputs.cluster_endpoint` → kubernetes provider `host`
- `data.terraform_remote_state.eks_infra.outputs.cluster_certificate_authority_data` → `base64decode(...)` for provider `cluster_ca_certificate`
- `data.terraform_remote_state.eks_infra.outputs.cluster_name` → `aws eks get-token --cluster-name`
- `data.terraform_remote_state.eks_infra.outputs.aws_region` → `aws eks get-token --region`

---

### Modules Identified

- **Primary Module**: `app.terraform.io/jose-merchan/kubernetes-app-deploy/kubernetes` (to be published from feat/006-kubernetes)
  - **Purpose**: Deploys containerised app workload (Deployment + Service + pull-secret) into existing K8s namespace
  - **Key Inputs consumed from workspace vars**: `registry_server`, `registry_username`, `registry_password`
  - **Key Inputs consumed from remote state**: `cluster_endpoint`, `cluster_certificate_authority_data`, `cluster_name`, `aws_region` (via kubernetes provider config — not direct module inputs)
  - **Wiring**: Provider is configured in consumer, not inside the module (provider-agnostic module per design §2)

- **Supporting Resources**: No glue modules needed; `data "terraform_remote_state"` is a built-in Terraform data source

---

### Rationale

1. **Terraform version `~> 1.15.0`**: eks-app-vcs uses `~> 1.15.0`; it is the direct peer workspace in the same project. Consistency prevents unexpected version skew between workspaces that share the same EKS cluster. The module requires `>= 1.14` — 1.15.x satisfies this.

2. **No varset attachment needed**: Confirmed `global=true` on `aws-dynamic-provider-credentials` via live API call. The eks-app-vcs workspace already receives it without any explicit attachment, proving the global attachment works.

3. **`infra_workspace` variable pattern**: The `eks-vault-vcs` reference workspace uses `infra_workspace = "eks-infra-vcs"` as a workspace variable to parameterise the remote state lookup. This allows the workspace name to be visible in the HCP Terraform UI without hardcoding it in the VCS configuration.

4. **POST to remote-state-consumers, not PATCH**: The HCP Terraform API uses `POST` to add consumers to an existing list (additive), not `PUT`/`PATCH` which would replace the entire list. This ensures `eks-app-vcs` and `eks-vault-vcs` remain as consumers.

5. **No AWS_REGION env var needed**: Region is read from eks-infra-vcs remote state (`aws_region = "eu-central-1"`). Setting a duplicate workspace env var would be redundant and could cause confusion if values diverged.

---

### Alternatives Considered

| Alternative | Why Not |
|---|---|
| Set `global-remote-state=true` on eks-infra-vcs | Would expose infra state to all workspaces in org — excessive blast radius; explicit consumer list is more secure and auditable |
| Use `project-remote-state=true` | eks-infra-vcs is in project `prj-cJR1vdDjwGbiHqzE`; k8s-app-demo-bob is in `prj-PmbVsprg8DoogHW7` — different projects, so project-scoped remote state would not help |
| Hardcode cluster details as workspace vars instead of remote state | Would duplicate live infra values that eks-infra-vcs already exports; values would drift when cluster is rebuilt; not the established pattern in this org |
| Use `terraform-version = "~> 1.12.0"` (matching eks-infra-vcs) | eks-infra-vcs is the infra workspace, not the app workspace; eks-app-vcs (same-tier peer) uses `~> 1.15.0` which is the correct reference for app consumer workspaces |
| Attach `aws-dynamic-provider-credentials` varset explicitly | Confirmed global=true; explicit attachment is unnecessary and would show a redundant attachment in the UI |

---

### Sources

- Live HCP Terraform API: `GET /api/v2/workspaces/ws-L4DyVVdn2YBUzipb` (eks-app-vcs details)
- Live HCP Terraform API: `GET /api/v2/workspaces/ws-L4DyVVdn2YBUzipb/vars` (eks-app-vcs variables — confirmed empty)
- Live HCP Terraform API: `GET /api/v2/workspaces/ws-fynCV5VvhkpRF7s3` (eks-infra-vcs details, global-remote-state=false)
- Live HCP Terraform API: `GET /api/v2/workspaces/ws-fynCV5VvhkpRF7s3/relationships/remote-state-consumers` (2 existing consumers: ws-L4DyVVdn2YBUzipb, ws-3MgtdSUWuLy9ktnL)
- Live HCP Terraform API: `GET /api/v2/workspaces/ws-fynCV5VvhkpRF7s3/current-state-version-outputs` (8 eks-infra outputs confirmed)
- Live HCP Terraform API: `GET /api/v2/organizations/jose-merchan/varsets` (aws-dynamic-provider-credentials confirmed global=true)
- Live HCP Terraform API: `GET /api/v2/workspaces/ws-3MgtdSUWuLy9ktnL/vars` (eks-vault-vcs infra_workspace variable pattern reference)
- `specs/006-kubernetes/design.md` — module interface contract (provider configuration pattern, registry credential variables)
- `examples/basic/main.tf` and `examples/basic/variables.tf` — EKS provider exec pattern confirmed
- `consumers/004-bob-demo-eks/backend.tf` — Default Project `prj-PmbVsprg8DoogHW7` confirmed as the target project
- HCP Terraform API docs: Workspaces, Variables, Remote State Consumers — https://developer.hashicorp.com/terraform/cloud-docs/api-docs
