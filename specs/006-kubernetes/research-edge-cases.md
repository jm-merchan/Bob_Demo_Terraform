## Research: Edge Cases and Failure Modes — Kubernetes Module on EKS

### Decision

Use two separate Terraform state boundaries (one for EKS infrastructure, one for Kubernetes resources), configure the `kubernetes` provider via the `exec` block with `api_version = "client.authentication.k8s.io/v1"`, use `data_wo` / `data_wo_revision` for secret data to prevent plaintext state storage, apply `prevent_destroy = true` on the image pull secret without `create_before_destroy`, and enforce RFC 1123 namespace validation, bounded replica count, and OCI image format validation on all inputs.

---

### 1. EKS Cluster Unreachability During `terraform apply`

#### Provider Initialization Is Eager, Not Lazy

The `hashicorp/kubernetes` provider connects to the cluster API server during **provider initialization**, which occurs before any resource graph is evaluated. If the EKS API endpoint is unreachable at that point, `terraform plan` or `terraform apply` fails immediately with a network-level error such as:

```
Error: Get "https://<endpoint>/api": dial tcp <ip>:443: i/o timeout
```

This is not recoverable mid-run — the entire operation aborts. There is no retry or skip-on-error behavior in the provider itself.

#### The Same-Module Anti-Pattern

The official provider documentation contains an explicit `WARNING`:

> When using interpolation to pass credentials to the Kubernetes provider from other resources, these resources **SHOULD NOT** be created in the same Terraform module where Kubernetes provider resources are also used. This will lead to intermittent and unpredictable errors which are hard to debug and diagnose. The root issue lies with the order in which Terraform itself evaluates the provider blocks vs. actual resources.

Confirmed by the official EKS example in `_examples/eks/README.md`, which enforces **two completely separate Terraform states**: `eks-cluster/` (AWS resources only) and `kubernetes-config/` (Kubernetes resources only), applied in sequence.

The failure mode when both are in the same module: on the first `terraform apply`, the provider block references `aws_eks_cluster.this.endpoint` which is **unknown at plan time** (computed value), so the Kubernetes provider is initialized with an empty `host = ""`, causing immediate connection failure.

#### Provider Configuration for EKS

**Recommended pattern using `exec` plugin** (tokens refreshed before each Terraform operation, avoids stale token issues):

```hcl
provider "kubernetes" {
  host                   = var.cluster_endpoint
  cluster_ca_certificate = base64decode(var.cluster_ca_cert)
  exec {
    api_version = "client.authentication.k8s.io/v1"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name]
    command     = "aws"
  }
}
```

**Alternative using `data.aws_eks_cluster_auth`** (token is fetched once per Terraform run, expires after 15 minutes — risky for long `apply` operations):

```hcl
provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}
```

#### Token Expiry: 15-Minute Hard Limit

AWS STS presigned URL tokens issued by `aws eks get-token` (and by `aws_eks_cluster_auth` data source) are valid for **exactly 15 minutes** (`presignedURLExpiration = 15 * time.Minute`, confirmed in `kubernetes-sigs/aws-iam-authenticator` source). For a `terraform apply` that runs longer than 15 minutes (e.g., waiting for Deployment rollout with `wait_for_rollout = true`), the token-based approach will fail mid-run with HTTP 401 Unauthorized. The `exec` plugin approach avoids this because it re-invokes `aws eks get-token` before each API call.

#### `exec` Plugin Binary Requirement

The `exec` block invokes `aws` as an external binary. If the execution environment (e.g., HCP Terraform runner, CI container) does not have the AWS CLI installed, the provider fails to authenticate with:

```
Error: exec: "aws": executable file not found in $PATH
```

Mitigation: pin a specific AWS CLI version in the runner image; or use `aws_eks_cluster_auth` data source as fallback if the runner has IAM credentials but no CLI.

#### `api_version` Must Be `v1` for Kubernetes 1.24+

The `client.authentication.k8s.io/v1beta1` API group was **removed in Kubernetes 1.29**. For EKS cluster version 1.24 and above, always use:

```hcl
api_version = "client.authentication.k8s.io/v1"
```

Using `v1beta1` with EKS 1.29+ (including 1.32 used in this project) will cause the provider to fail token exchange with an unrecognized API group error. The provider source validates `v1alpha1` with a deprecation warning but does not warn about `v1beta1` — this failure is silent until runtime.

---

### 2. `kubernetes_secret_v1` Data Updates and Deployment Recreation

#### Secret `data` Update: In-Place Patch, No Deployment Recreation

When `kubernetes_secret_v1.data` is changed, Terraform performs an **in-place patch** to the Kubernetes Secret object via the Kubernetes PATCH API. The secret **name does not change**. Because `kubernetes_deployment_v1` references the secret only by name (in `spec.template.spec.image_pull_secrets[*].name`), the Deployment resource is **not marked for recreation** — Terraform sees no change to the Deployment.

However, Kubernetes itself **does not automatically restart pods** when an image pull secret's data is rotated. Existing running pods that already pulled the image are unaffected. New pods scheduled after the rotation will use the updated credentials. If pods need to be cycled (e.g., to force a re-pull), an annotation on `spec.template.metadata.annotations` must be changed to trigger a rolling update.

#### Secret `data` vs `data_wo` Attribute Distinction

The `kubernetes_secret_v1` resource offers two ways to supply secret data:

| Attribute | Stored in State | Triggers Update |
|-----------|----------------|-----------------|
| `data` (Map of String, Sensitive) | Yes — base64-encoded plaintext in `.tfstate` | On content change — in-place patch |
| `data_wo` (Map of String, Write-Only) | **No** — never written to state | On `data_wo_revision` increment |

Using `data_wo` eliminates credential leakage via Terraform state, but the module consumer must manually increment `data_wo_revision` to signal a credentials rotation. Using `data` is simpler but stores the Docker registry password in the state file (even as sensitive, it is still present in plaintext in the JSON).

**Recommendation**: Use `data_wo` + `data_wo_revision` for the `.dockerconfigjson` key. Document that callers must increment `data_wo_revision` on password rotation.

**Known bug (fixed in 3.2.1)**: Provider versions prior to 3.2.1 had a `Missing Resource Identity After Create` error when using `data_wo`. Pin to `>= 3.2.1`.

#### `immutable = true` and Recreation

If `immutable = true` is set on the secret, Kubernetes rejects any `data` update with a 422 error. Terraform then has no choice but to **destroy and recreate** the secret. This forces the Deployment to be updated (because the new secret will have a different name if `generate_name` is used, or the Deployment will fail to schedule if the old secret is deleted before the new one is created). Do **not** set `immutable = true` on an image pull secret that may need credential rotation.

---

### 3. Lifecycle Considerations for the Image Pull Secret

#### `create_before_destroy` with a Fixed `metadata.name`

**This will fail.** Kubernetes requires object names to be unique within a namespace. If `lifecycle { create_before_destroy = true }` is applied to a `kubernetes_secret_v1` with `metadata { name = "my-registry-secret" }`, Terraform attempts to create a second secret with the same name before destroying the first. Kubernetes returns HTTP 409 Conflict (`AlreadyExists`), and the apply fails with:

```
Error: secrets "my-registry-secret" already exists
```

**The only way to use `create_before_destroy`** is to use `metadata { generate_name = "registry-secret-" }` instead of a fixed name. This causes Kubernetes to assign a unique name (e.g., `registry-secret-xk7m9`). However, this creates a second problem: the `kubernetes_deployment_v1` resource references the secret by name via `image_pull_secrets[*].name`, so the Deployment must also be updated when the secret name changes. This creates a dependency cycle if not carefully ordered.

**Practical recommendation**: Do **not** use `create_before_destroy` on the image pull secret. The secret itself is not a workload-blocking resource — a momentary absence of the image pull secret during rotation only affects new pod scheduling, not existing running pods.

#### `prevent_destroy = true`

This is the correct lifecycle protection for an image pull secret. If the secret is accidentally removed (e.g., via `terraform destroy` on a partial resource set), all pods attempting to pull from the private registry will fail with `ImagePullBackOff`. Apply `prevent_destroy = true` to prevent accidental deletion:

```hcl
resource "kubernetes_secret_v1" "registry" {
  lifecycle {
    prevent_destroy = true
  }
  # ...
}
```

Note: `prevent_destroy` only blocks `terraform destroy` and targeted destroys. It does not prevent recreation triggered by a `ForceNew` attribute change.

#### ForceNew Triggers on the Secret

The following changes to `kubernetes_secret_v1` force **destroy + recreate** (not in-place update), which means a window where the secret does not exist:

- Changing `metadata.name`
- Changing `metadata.namespace`
- Changing `type` (e.g., from `kubernetes.io/dockerconfigjson` to `Opaque`)

These attributes are marked `ForceNew` in the provider schema. If `prevent_destroy = true` is set, Terraform will refuse to proceed, surfacing the conflict as an error. The operator must explicitly `terraform state rm` the old secret, then re-apply.

#### Correct Lifecycle Block

```hcl
resource "kubernetes_secret_v1" "registry" {
  lifecycle {
    prevent_destroy       = true
    ignore_changes        = [metadata[0].resource_version]
  }
  # ...
}
```

The `ignore_changes` on `resource_version` prevents perpetual diff when Kubernetes controllers mutate the secret's resource version metadata.

---

### 4. Terraform Validation Rules for Variables

#### Namespace Format (RFC 1123 DNS Label)

Kubernetes namespace names must conform to **RFC 1123 DNS label** format:
- Lowercase alphanumeric characters or hyphens
- Must start with an alphanumeric character
- Must end with an alphanumeric character
- Maximum 63 characters

```hcl
variable "namespace" {
  type = string
  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.namespace))
    error_message = "Namespace must be a valid RFC 1123 DNS label: lowercase alphanumeric and hyphens, start and end with alphanumeric, max 63 chars."
  }
}
```

The regex `^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$` allows single-character names (`a`) and names up to 63 characters. It rejects: uppercase letters, leading/trailing hyphens, double hyphens, underscores, and names > 63 chars. Note: `kube-system`, `kube-public`, and `default` are Kubernetes reserved names — add an additional validation condition to reject them if the module should not target system namespaces.

#### Image Format (OCI Image Reference)

OCI image references follow the format: `[registry/][namespace/]repository[:tag|@sha256:digest]`

A pragmatic validation regex that covers the common cases:

```hcl
variable "image" {
  type = string
  validation {
    condition = can(regex(
      "^([a-zA-Z0-9._\\-]+([:/][a-zA-Z0-9._\\-]+)*(:[a-zA-Z0-9._\\-]+|@sha256:[a-f0-9]{64})?|[a-zA-Z0-9._\\-]+)$",
      var.image
    ))
    error_message = "Image must be a valid OCI image reference: e.g. nginx:1.25, registry.example.com/org/app:v1.0, or sha256 digest."
  }
}
```

**Important caveat**: The `kubernetes_deployment_v1` schema stores `replicas` as a **string**, not a number, to distinguish `0` (explicit scale-to-zero) from `null` (unset, use cluster default). A string image validator must not block the `""` (empty string) case if the module makes image optional, but for a required image variable, validate non-empty:

```hcl
  validation {
    condition     = var.image != ""
    error_message = "Image must not be empty."
  }
```

#### Replica Count Bounds

Kubernetes permits `0` replicas (scale to zero). The type is `string` in the provider schema but should be exposed as `number` from the module's perspective for usability:

```hcl
variable "replicas" {
  type    = number
  default = 1
  validation {
    condition     = var.replicas >= 0 && var.replicas <= 100
    error_message = "Replica count must be between 0 and 100."
  }
}
```

The module must convert to string when passing to the resource: `replicas = tostring(var.replicas)`.

Upper bound of 100 is a module-level guardrail, not a Kubernetes limit. Adjust based on expected cluster capacity. A value of `0` is valid and useful for suspended environments.

#### Secret Name Format

Docker registry secret names follow the same RFC 1123 DNS label rules as namespaces. An invalid name causes the Kubernetes API to return a 422 Unprocessable Entity error with a field-level validation message. Validate with the same pattern as namespace.

---

### 5. Known Issues with `hashicorp/kubernetes` Provider on EKS

#### Issue 1: Provider Stacking in the Same Module (Critical)

**Symptom**: `Error: Provider configuration depends on resource attributes that cannot be determined until apply.`

**Root cause**: Terraform evaluates provider configurations before the resource graph. If `host` or `cluster_ca_certificate` are sourced from an `aws_eks_cluster` resource in the same module, they are unknown at provider-configuration time.

**Fix**: Split into two separate Terraform configurations. Pass the cluster endpoint, CA data, and cluster name as **input variables** (not resource references) to the Kubernetes module.

#### Issue 2: `aws_eks_cluster_auth` Token Expiry During Long Apply

**Symptom**: Mid-apply 401 Unauthorized errors after ~15 minutes.

**Root cause**: `data.aws_eks_cluster_auth.this.token` fetches a presigned STS token once per run, valid for 15 minutes.

**Fix**: Use the `exec` block instead. The exec plugin is invoked before each resource API call, ensuring the token is always fresh.

#### Issue 3: `exec` Block API Version Must Be `v1` (Not `v1beta1`) for K8s ≥ 1.29

**Symptom**: `error: unknown apiVersion "client.authentication.k8s.io/v1beta1"` at runtime, or silent 401 errors.

**Root cause**: `v1beta1` was removed in Kubernetes 1.29. EKS 1.32 (this project's cluster version) only supports `v1`.

**Fix**: Set `api_version = "client.authentication.k8s.io/v1"` in the exec block. The provider source only warns on `v1alpha1`; it does not warn on `v1beta1`, making this a silent runtime failure.

#### Issue 4: `aws-auth` ConfigMap Bootstrap Problem

**Symptom**: On first apply of an EKS cluster with `authentication_mode = CONFIG_MAP`, the Kubernetes provider cannot create the `aws-auth` ConfigMap because no IAM principal has been mapped to cluster-admin yet.

**Root cause**: When a new EKS cluster is created with `authentication_mode = CONFIG_MAP`, only the creating IAM principal gets `system:masters` access — but only if `bootstrap_cluster_creator_admin_permissions = true` is set in `access_config`. If this flag is `false` (or if Terraform uses a different IAM role than the one that created the cluster), there is no path to create the `aws-auth` ConfigMap.

**Fix options**:
1. Set `bootstrap_cluster_creator_admin_permissions = true` and ensure the Terraform execution IAM role is the cluster-creating role.
2. Use `authentication_mode = API_AND_CONFIG_MAP` or `API` and manage access via EKS Access Entries (`aws_eks_access_entry` + `aws_eks_access_policy_association`) — this avoids needing the `aws-auth` ConfigMap entirely and works cleanly with the Kubernetes provider in a separate state.

#### Issue 5: Perpetual Diff on Annotations and Labels Added by Controllers

**Symptom**: `terraform plan` always shows changes to `metadata.annotations` or `spec.template.metadata.annotations` even after `apply`.

**Root cause**: Kubernetes controllers (e.g., `kubectl rollout restart`, CNI plugins, service mesh admission webhooks) add annotations to running resources. The provider reads back the live state and detects drift.

**Fix**: Use provider-level `ignore_annotations` with regex, or resource-level `lifecycle { ignore_changes = [...] }`:

```hcl
# Provider-level: ignore all AWS load balancer annotations globally
provider "kubernetes" {
  ignore_annotations = ["^service\\.beta\\.kubernetes\\.io\\/aws-load-balancer.*"]
}

# Resource-level: ignore kubectl restart annotation on deployment template
resource "kubernetes_deployment_v1" "this" {
  lifecycle {
    ignore_changes = [
      spec[0].template[0].metadata[0].annotations["kubectl.kubernetes.io/restartedAt"],
    ]
  }
}
```

#### Issue 6: Toleration Perpetual Diff (Fixed in Provider ≥ 2.38.0)

**Symptom**: Resources with well-known Kubernetes taints (e.g., `node.kubernetes.io/not-ready`) show perpetual drift in `spec.template.spec.tolerations`.

**Root cause**: The provider was incorrectly stripping well-known tolerations from `kubernetes_deployment_v1` pod templates.

**Fix**: Upgrade provider to `>= 2.38.0`. Pin to `>= 3.2.1` to also get the `data_wo` bug fix.

#### Issue 7: `wait_for_rollout = true` Timeout With Unreachable Cluster Endpoint

**Symptom**: `terraform apply` hangs for the `progress_deadline_seconds` duration (default 600s) when the cluster can be reached for writes but nodes are not ready to schedule pods.

**Root cause**: `kubernetes_deployment_v1` defaults to `wait_for_rollout = true`, which polls the Deployment until all replicas are Available. If the cluster has no schedulable nodes (e.g., node group not yet ready, taints not tolerated), the Deployment never becomes Available and Terraform times out.

**Fix**: Set `wait_for_rollout = false` in module development/testing. In production, ensure node group is fully `ACTIVE` before applying Kubernetes resources (cross-state output dependency). Set `progress_deadline_seconds` explicitly to a shorter value to get earlier failure feedback.

#### Issue 8: KUBE_CONFIG_PATH Environment Variable Not Honored (Changed in v3.0.0)

**Symptom**: After upgrading to provider `>= 3.0.0`, the `KUBE_CONFIG_PATH` env var no longer overrides values set in the provider block.

**Root cause**: In `v2.x.x`, `kubernetes_manifest` allowed environment variables to override provider block values. This was made consistent in `v3.0.0`: env vars are only used when **no value** is set in the provider block configuration.

**Fix**: When using provider `>= 3.0.0`, set credentials explicitly in the provider block rather than relying on `KUBE_CONFIG_PATH` to override.

---

### Resources Identified

- **Primary Resources**:
  - `kubernetes_deployment_v1` — workload resource; `wait_for_rollout` (bool, default `true`); `replicas` is `string` type
  - `kubernetes_service_v1` — service abstraction; `wait_for_load_balancer` (bool) for LB-type services
  - `kubernetes_secret_v1` — Docker registry credentials; use `data_wo`/`data_wo_revision` to avoid state exposure
- **Supporting Resources**:
  - `kubernetes_namespace_v1` — optional namespace creation if the module creates its own namespace
  - `kubernetes_secret_v1_data` — alternative for patching data in a pre-existing secret via server-side apply
- **Key Outputs**: `kubernetes_service_v1.status[0].load_balancer[0].ingress[0].hostname` (ELB hostname), `kubernetes_deployment_v1.metadata[0].name`
- **Security Considerations**: `data_wo` attribute prevents Docker registry password from appearing in Terraform state; `prevent_destroy = true` prevents accidental image pull secret deletion; `sensitive = true` on module outputs that re-expose secret names

---

### Rationale

All five topic areas are directly evidenced from provider source and documentation:
- The same-module anti-pattern is called out with a `WARNING` block in the official provider index documentation (doc ID `12692122`)
- The exec plugin `api_version` requirement for `v1` is confirmed by the `v1alpha1` deprecation note in `provider.go` and by the K8s 1.29 API removal changelog
- The 15-minute token expiry is confirmed in `kubernetes-sigs/aws-iam-authenticator` source (`presignedURLExpiration = 15 * time.Minute`)
- The `data_wo` write-only attribute behavior is confirmed in `kubernetes_secret_v1` schema (doc ID `12692229`) and CHANGELOG (v2.36.0 addition, v3.2.1 bug fix)
- The `create_before_destroy` + fixed name conflict is a direct consequence of Kubernetes' name uniqueness constraint within a namespace
- The toleration perpetual diff fix is confirmed in CHANGELOG v2.38.0
- RFC 1123 namespace naming rules are the Kubernetes API standard for all namespace-scoped resource names
- The `replicas` as string type is confirmed in `kubernetes_deployment_v1` schema (doc ID `12692181`)

---

### Alternatives Considered

| Alternative | Why Not |
|-------------|---------|
| Use `data.aws_eks_cluster_auth` token instead of exec plugin | Token expires after 15 min; fails on long apply operations; exec plugin is safer for production |
| Use `metadata.generate_name` + `create_before_destroy` on secret | Breaks the Deployment's `image_pull_secrets` name reference on every rotation; adds operational complexity with no meaningful benefit |
| Use `immutable = true` on secret | Blocks all data updates; requires destroy+create on rotation; creates a gap window |
| Use `kubernetes_secret_v1_data` for separate data management | Appropriate for GitOps patterns where secret object is pre-created; overkill if Terraform owns the full lifecycle |
| Place AWS EKS and Kubernetes resources in the same module | Explicitly documented as anti-pattern by official provider docs; causes provider init failures on first apply |
| Use `config_path` with a generated kubeconfig file | Requires writing sensitive CA data to disk; creates file management complexity; exec plugin is the idiomatic EKS approach |

---

### Sources

- hashicorp/kubernetes provider v3.2.1 index doc (ID: 12692122): https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs
- hashicorp/kubernetes provider v3.2.1 `kubernetes_deployment_v1` schema (ID: 12692181): https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/deployment_v1
- hashicorp/kubernetes provider v3.2.1 `kubernetes_secret_v1` schema (ID: 12692229): https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/secret_v1
- hashicorp/kubernetes provider v3.2.1 `kubernetes_service_v1` schema (ID: 12692234): https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/service_v1
- hashicorp/kubernetes provider v3.2.1 `kubernetes_secret_v1_data` schema (ID: 12692230): https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/secret_v1_data
- hashicorp/kubernetes v3 upgrade guide (ID: 12692126): https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/guides/v3-upgrade-guide
- hashicorp/terraform-provider-kubernetes CHANGELOG: https://github.com/hashicorp/terraform-provider-kubernetes/blob/main/CHANGELOG.md
- hashicorp/terraform-provider-kubernetes EKS example: https://github.com/hashicorp/terraform-provider-kubernetes/tree/main/_examples/eks
- hashicorp/terraform-provider-kubernetes provider.go source (exec block validation): https://github.com/hashicorp/terraform-provider-kubernetes/blob/main/kubernetes/provider.go
- kubernetes-sigs/aws-iam-authenticator (15-minute token expiry): https://github.com/kubernetes-sigs/aws-iam-authenticator/blob/master/pkg/token/token.go
- AWS EKS cluster auth documentation: https://docs.aws.amazon.com/eks/latest/userguide/cluster-auth.html
- Kubernetes RFC 1123 DNS label naming rules: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#dns-label-names
