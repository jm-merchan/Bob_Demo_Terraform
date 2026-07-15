## Research: Private Registry Source Path and Version for `kubernetes-app-deploy`

### Decision

The `kubernetes-app-deploy` module is **NOT yet published** to the `jose-merchan` PMR. The consumer workspace cannot `terraform init` or plan until the module is published. Once published, the consumer source will be `app.terraform.io/jose-merchan/kubernetes-app-deploy/kubernetes` with version constraint `~> 0.1`.

---

### Modules Identified

- **Primary Module**: `app.terraform.io/jose-merchan/kubernetes-app-deploy/kubernetes` _(not yet published)_
  - **Purpose**: Deploys a containerised application to Kubernetes — creates a `kubernetes_secret_v1` pull secret (write-only credentials), a `kubernetes_deployment_v1`, and a `kubernetes_service_v1`
  - **Key Inputs** (required — no defaults):
    - `app_name` — RFC 1123 DNS label, 1–63 chars, used as resource name + pod selector label
    - `namespace` — target K8s namespace (must pre-exist)
    - `image` — full OCI image reference including registry and tag
    - `replicas` — pod replica count, 1–100
    - `registry_server` — private registry hostname (sensitive)
    - `registry_username` — registry auth username (sensitive)
    - `registry_password` — registry auth password/API key (sensitive, write-only — never stored in state)
  - **Key Inputs** (optional — with defaults):
    - `registry_secret_revision` — default `1`; increment to rotate credentials
    - `container_port` — default `8080`
    - `service_type` — `ClusterIP | NodePort | LoadBalancer`, default `ClusterIP`
    - `cpu_request` / `cpu_limit` — default `250m` / `500m`
    - `memory_request` / `memory_limit` — default `256Mi` / `512Mi`
    - `liveness_path` / `readiness_path` — default `/health/live` / `/health/ready`
    - `enable_liveness_probe` / `enable_readiness_probe` — default `true`
  - **Key Outputs**:
    - `deployment_name` — `string` — name of the `kubernetes_deployment_v1` resource
    - `service_name` — `string` — name of the `kubernetes_service_v1` resource
    - `service_cluster_ip` — `string` — ClusterIP address (plan-unknown until apply)
    - `secret_name` — `string` — name of the registry pull secret
  - **Secure Defaults**:
    - Pod security context: `run_as_non_root = true`, `run_as_user = 1000`, `fs_group = 2000`
    - Container security context: `allow_privilege_escalation = false`, `privileged = false`, `read_only_root_filesystem = true`, drops all Linux capabilities
    - Registry credentials via `data_wo` — write-only, never stored in state
    - Pull secret has `prevent_destroy = true` lifecycle guard

- **Supporting Modules**: None — this is a standalone module; no other private registry modules are needed.

- **Glue Resources Needed**: None — the module manages the pull secret, deployment, and service internally.

- **Wiring Considerations**:
  - The consumer must supply a pre-existing K8s `namespace` and a valid `image` reference.
  - `service_cluster_ip` is plan-unknown until apply — do not reference it in count/for_each.
  - `registry_password` must be passed as a sensitive workspace variable (not hardcoded).

---

### PMR Status: Confirmed NOT Published

Live PMR query (`GET /api/v2/organizations/jose-merchan/registry-modules`, run against `app.terraform.io`) returned **16 modules**, all with `aws` or `google` providers. No `kubernetes` provider module exists. Direct lookup of path `/private/jose-merchan/kubernetes-app-deploy/kubernetes` returned **HTTP 404**.

**Full PMR module list as of query date:**

| Module Name                    | Provider | Publishing Mechanism |
|-------------------------------|----------|----------------------|
| `alb`                          | aws      | branch               |
| `autoscaling`                  | aws      | branch               |
| `cloudfront`                   | aws      | branch               |
| `cloudwatch`                   | aws      | branch               |
| `ec2-instance`                 | aws      | branch               |
| `eks`                          | aws      | branch               |
| `eks-agentic`                  | aws      | branch               |
| `eks-bob`                      | aws      | git_tag (v0.1–0.5)   |
| `eks-cluster`                  | aws      | non_vcs (v0.0.1–12)  |
| `erraform-google-vaultgke`     | google   | git_tag              |
| `iam`                          | aws      | branch               |
| `lambda`                       | aws      | branch               |
| `security-group`               | aws      | branch               |
| `sns`                          | aws      | branch               |
| `sqs`                          | aws      | branch               |
| `vpc`                          | aws      | branch               |

---

### Consumer Source and Version Constraint

Once the module is published, consumers must reference it as:

```hcl
module "app" {
  source  = "app.terraform.io/jose-merchan/kubernetes-app-deploy/kubernetes"
  version = "~> 0.1"

  app_name  = "my-app"
  namespace = "production"
  image     = "de.icr.io/san-clients/backend:v1.2.3"
  replicas  = 2

  registry_server   = var.registry_server
  registry_username = var.registry_username
  registry_password = var.registry_password
}
```

Version constraint `~> 0.1` permits `>= 0.1.0, < 0.2.0` — safe for first-publish assuming the first tag pushed is `v0.1.0`.

---

### Publication Prerequisite

The `terraform-kubernetes-app-deploy` module at the repo root must be published to the PMR **before** any consumer workspace can run. Publication steps:

1. **Register** the module in `jose-merchan` org via the HCP Terraform UI or API:
   - Module name: `kubernetes-app-deploy`
   - Provider: `kubernetes`
   - VCS connection: link to the GitHub repo containing this code (`jm-merchan/terraform-kubernetes-app-deploy` or equivalent)
   - Publishing mechanism: `git_tag`
2. **Push a semver tag** (e.g., `v0.1.0`) to the linked GitHub repository — HCP Terraform ingests the tag and sets `status: ok` for that version.
3. **Verify** with `GET /api/v2/organizations/jose-merchan/registry-modules/private/jose-merchan/kubernetes-app-deploy/kubernetes` — expect HTTP 200 with `version-statuses[0].version = "0.1.0"`.
4. Only after step 3 passes can the consumer workspace run `terraform init` successfully.

---

### Module Provider and Terraform Constraints (from `versions.tf`)

```hcl
terraform {
  required_version = ">= 1.14"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 3.2.1"
    }
  }
}
```

The consumer workspace must configure the `hashicorp/kubernetes` provider (version ≥ 3.2.1) with valid cluster credentials (kubeconfig or in-cluster service account).

---

### Rationale

The PMR was queried live via the HCP Terraform API — zero false positives are possible. The module interface was read directly from [`variables.tf`](variables.tf), [`outputs.tf`](outputs.tf), [`main.tf`](main.tf), [`locals.tf`](locals.tf), and [`versions.tf`](versions.tf) in the repo root. No speculation.

---

### Alternatives Considered

| Alternative | Why Not |
|---|---|
| Use a local path module `source = "../"` | Consumer constitution prohibits local path modules; only PMR sources allowed in consumer workspaces |
| Reference existing `eks-cluster` or `eks-bob` modules | Wrong abstraction — those provision EKS infra, not application deployments into a cluster |
| Use raw `kubernetes_*` resources in the consumer | Consumer constitution prohibits raw resources; compose from PMR modules only |
| Publish via `non_vcs` API upload | Valid alternative if VCS connection is unavailable, but `git_tag` is the org standard for versioned modules |

---

### Sources

- Live PMR API response: `GET https://app.terraform.io/api/v2/organizations/jose-merchan/registry-modules` (HTTP 200, 16 modules, no kubernetes entry)
- Direct module path check: `GET /private/jose-merchan/kubernetes-app-deploy/kubernetes` → HTTP 404
- [`versions.tf`](versions.tf) — Terraform `>= 1.14`, provider `hashicorp/kubernetes >= 3.2.1`
- [`variables.tf`](variables.tf) — all 16 input variables with types, descriptions, validations
- [`outputs.tf`](outputs.tf) — 4 string outputs: `deployment_name`, `service_name`, `service_cluster_ip`, `secret_name`
- [`main.tf`](main.tf) — resource definitions: `kubernetes_secret_v1`, `kubernetes_deployment_v1`, `kubernetes_service_v1`
- HCP Terraform docs: [Publish Modules to the Private Registry](https://developer.hashicorp.com/terraform/cloud-docs/registry/publish-modules)
