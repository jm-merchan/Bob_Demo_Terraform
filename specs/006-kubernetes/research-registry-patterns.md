## Research: Public Terraform Registry Module Patterns for Kubernetes Application Deployment

### Decision

Use `kubernetes_deployment_v1` + `kubernetes_service_v1` + `kubernetes_secret_v1` as the three-resource core, construct the `dockerconfigjson` payload with `jsonencode()` + inline `base64encode()` (the canonical provider example pattern), and keep the module provider-agnostic by inheriting the `kubernetes` provider from the consumer — no `provider {}` block in the module root.

---

### Resources Identified

- **Primary Resource**: `kubernetes_deployment_v1` — schedules the containerised workload; references the pull secret via `image_pull_secrets { name }` inside `spec.template.spec`
- **Supporting Resources**:
  - `kubernetes_secret_v1` — type `kubernetes.io/dockerconfigjson`; holds registry credentials; created first, referenced by name in the deployment
  - `kubernetes_service_v1` — exposes the deployment; `type` is a variable (default `ClusterIP`); `selector` matches the deployment's pod labels
- **Key Arguments — deployment**: `replicas`, `selector.match_labels`, `template.metadata.labels` (must equal selector), `container.image`, `container.resources.limits/requests`, `image_pull_secrets.name`
- **Key Arguments — service**: `spec.selector` (matches deployment pod labels), `spec.type`, `spec.port.port`, `spec.port.target_port`
- **Key Arguments — secret**: `type = "kubernetes.io/dockerconfigjson"`, `data[".dockerconfigjson"]` built with `jsonencode()`
- **Key Outputs**: `deployment_name` (`string`), `service_cluster_ip` (`string`), `secret_name` (`string`)
- **Security Considerations**: All registry credential variables must be `sensitive = true`; secret data is stored in Terraform state in plaintext — document this in the module README; service type defaults to `ClusterIP` (no external exposure by default); resource `limits` enforce against runaway CPU/memory consumption

---

### 1. Variable Interface Patterns

**Required inputs (no default — consumer must supply)**

Every observed module treats these as required:
- `namespace` — target Kubernetes namespace (`string`); used in every resource's `metadata.namespace`
- `app_name` / `name` — logical application name; drives `metadata.name` and pod selector labels (`string`)
- `image` — full container image reference including tag (`string`)
- `replicas` — replica count (`number`); **StayWell/jenkins** hardcodes `1`, but app-deploy modules universally expose this as a required or defaulted variable
- Registry credentials — `registry_server`, `registry_username`, `registry_password` — all `sensitive = true`; the **official provider example_3.tf** also includes `registry_email` as a fourth field

**Optional inputs with defaults (observed defaults from registry modules)**

| Variable | Observed Default | Source |
|---|---|---|
| `service_type` | `"ClusterIP"` | sailthru/ambassador, MarvelOrange/dashboard, kiwicom |
| `container_port` | `8080` | StayWell/jenkins uses `web_port = "8080"` |
| `cpu_request` | `"250m"` – `"400m"` | kiwicom (`400m`), official example (`250m`) |
| `memory_request` | `"500Mi"` – `"500M"` | kiwicom (`500M`), official example (`50Mi`) |
| `cpu_limit` | `"0.5"` – `"1"` | official example (`0.5`), sailthru (`1`) |
| `memory_limit` | `"512Mi"` – `"1Gi"` | official example (`512Mi`), sailthru (`1Gi`) |
| `image_pull_policy` | `"IfNotPresent"` | sl1pm4t/redis, sailthru/ambassador |
| `wait_for_rollout` | `true` | StayWell/jenkins |

**Pattern**: Required = namespace + name + image + replicas + credentials. Everything else has a safe default. Resource requests/limits are always exposed as separate variables for requests vs limits.

---

### 2. Deployment–Service–Secret Relationship Pattern

All observed modules follow this dependency chain:

```
kubernetes_secret_v1  (created first, no dependencies)
        ↓  name referenced in:
kubernetes_deployment_v1
  spec.template.spec.image_pull_secrets { name = kubernetes_secret_v1.this.metadata[0].name }
        ↓  pod labels referenced in:
kubernetes_service_v1
  spec.selector = { app = var.app_name }   # same value used in deployment's template.metadata.labels
```

**Label coupling**: The deployment's `spec.selector.match_labels` and `spec.template.metadata.labels` must be identical. The service's `spec.selector` must match those same labels. The universal pattern is a single `{ app = var.app_name }` map — keeping label coupling to one variable prevents selector drift across the three resources.

**StayWell/jenkins concrete pattern** (confirmed from source):
```hcl
# deployment
selector { match_labels = { app = "jenkins" } }
template { metadata { labels = { app = "jenkins" } } }

# service
spec { selector = { app = "jenkins" } }
```

For a module, replace the hardcoded string with `var.app_name`.

**`image_pull_secrets` placement**: Inside `spec.template.spec`, not at deployment level:
```hcl
spec {
  template {
    spec {
      image_pull_secrets {
        name = kubernetes_secret_v1.this.metadata[0].name
      }
      container { ... }
    }
  }
}
```

---

### 3. Output Patterns

Observed outputs across all surveyed modules are **sparse** — most kubernetes modules expose 0–2 outputs. The strongest pattern from the official provider example (`service_v1/example_2.tf`) is:

```hcl
# service_v1 status path for ClusterIP:
kubernetes_service_v1.this.spec[0].cluster_ip

# service_v1 status path for LoadBalancer hostname:
kubernetes_service_v1.this.status[0].load_balancer[0].ingress[0].hostname
```

**Recommended output set** (synthesised from provider docs + observed module patterns):

| Output | Source Attribute | Conditional | Notes |
|---|---|---|---|
| `deployment_name` | `kubernetes_deployment_v1.this.metadata[0].name` | always | consumed by CI/CD pipelines for `kubectl rollout status` |
| `service_cluster_ip` | `kubernetes_service_v1.this.spec[0].cluster_ip` | always | `""` for headless services; always a string |
| `service_name` | `kubernetes_service_v1.this.metadata[0].name` | always | needed for other resources that reference the service |
| `secret_name` | `kubernetes_secret_v1.this.metadata[0].name` | always | allows consumers to reference the secret in other deployments |

No observed module uses `sensitive = true` on outputs for the secret name (it's not sensitive) but the underlying `kubernetes_secret_v1` data is always sensitive in state.

---

### 4. dockerconfigjson Secret Creation Pattern

**Two approaches exist in the wild:**

#### Approach A — External file (provider example_2.tf)
```hcl
data = {
  ".dockerconfigjson" = file("${path.module}/.docker/config.json")
}
```
**Problem**: Requires a file at a known path — not usable in a reusable module that accepts credentials as variables.

#### Approach B — `jsonencode()` with inline `base64encode()` (provider example_3.tf — canonical)
```hcl
data = {
  ".dockerconfigjson" = jsonencode({
    auths = {
      "${var.registry_server}" = {
        "username" = var.registry_username
        "password" = var.registry_password
        "email"    = var.registry_email
        "auth"     = base64encode("${var.registry_username}:${var.registry_password}")
      }
    }
  })
}
```
This is the **canonical approach** — it is the official `kubernetes_secret_v1` documentation example (example_3.tf), equivalent to `kubectl create secret docker-registry`. The `auth` field is `base64(username:password)`, a legacy Docker field; modern clients use `username`/`password` directly but `auth` is included for maximum compatibility.

**kiwicom pattern** (inline string interpolation — older, avoid):
```hcl
# Anti-pattern: raw string interpolation, no jsonencode
data = {
  ".dockercfg" = "{\"${var.registry}\":{\"username\":\"${var.username}\",\"password\":\"${var.password}\"}}"
}
type = "kubernetes.io/dockercfg"    # Note: older .dockercfg type, not .dockerconfigjson
```
Avoid: brittle, not JSON-safe for passwords containing quotes/special characters.

**Decision**: Use `jsonencode()` + `base64encode()` (Approach B). It is type-safe, handles special characters in passwords correctly, matches the provider's own documented example, and is equivalent to `kubectl create secret docker-registry`.

**`registry_email` handling**: The official example includes it as a variable. However, modern Docker registries (including IBM ICR `de.icr.io`) do not require the email field. Pattern: include `registry_email` as an optional variable with `default = ""` — `jsonencode` will include an empty string which is harmless.

---

### 5. Provider-Agnostic Patterns (EKS, GKE, AKS)

**Core principle**: The `kubernetes` provider requires cluster credentials (`host`, `cluster_ca_certificate`, `token` or `exec` block). These are cloud-specific. Modules achieve provider-agnosticism by **never declaring a `provider {}` block** — the consumer configures the provider before calling the module.

**Confirmed pattern from official provider docs** (`service_v1/example_2.tf`):
```hcl
# Consumer's root module (NOT inside the module):
provider "kubernetes" {
  host                   = data.aws_eks_cluster.example.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.example.certificate_authority[0].data)
  exec {
    api_version = "client.authentication.k8s.io/v1"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name]
    command     = "aws"
  }
}
```

For GKE the consumer would use `google_container_cluster` data sources; for AKS, `azurerm_kubernetes_cluster`. The module itself is identical in all three cases.

**Module constitution alignment**: Section 2.1 states "Root module MUST NOT contain `provider {}` blocks — modules inherit providers from consumers." This is exactly the pattern used by all public kubernetes modules surveyed.

**versions.tf pattern** for a kubernetes-only module:
```hcl
terraform {
  required_version = ">= 1.7"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.23"  # minimum version with _v1 resource aliases
    }
  }
}
```

Use `>=` (not `~>`) per module constitution §4.1 to maximize consumer compatibility. Version `2.23` is the minimum that ships all `_v1` resource types used (`kubernetes_deployment_v1`, `kubernetes_service_v1`, `kubernetes_secret_v1`).

**`_v1` vs legacy resource names**: The `hashicorp/kubernetes` provider ships both `kubernetes_deployment` (legacy) and `kubernetes_deployment_v1` (current alias). All new modules should use `_v1` suffixed names — they map to stable Kubernetes API versions (`apps/v1`, `core/v1`) and avoid deprecation warnings. Confirmed by provider template docs (`deployment_v1.md.tmpl` subcategory: `apps/v1`).

---

### Rationale

1. **`jsonencode()` for dockerconfigjson**: The official provider documentation (example_3.tf) uses this exclusively for variable-driven registry credentials. The `kubectl` equivalence comment in `secret_v1.md.tmpl` confirms it produces identical output to the CLI command. The kiwicom inline-string alternative is a well-known anti-pattern — it breaks on passwords with special characters.

2. **Label coupling via single variable**: All surveyed modules (StayWell/jenkins, 4ops/clickhouse, sailthru/ambassador) use a single app-name value across deployment selector, pod template labels, and service selector. This prevents label drift and is testable as a single assertion.

3. **`image_pull_secrets` inside `spec.template.spec`**: Confirmed from the Kubernetes API spec. The pod-level `imagePullSecrets` field is under `Pod.spec`, not `Deployment.spec`. The `kubernetes_deployment_v1` HCL nesting reflects this: `spec.template.spec.image_pull_secrets`.

4. **Provider-agnosticism by omission**: Every public module surveyed that has real adoption (kiwicom: 161K downloads, iplabs/alb-ingress: 969K downloads, sailthru/ambassador: 9.5K) contains no `provider {}` block in root. Provider configuration always lives in the consumer.

5. **Output sparsity**: Public modules expose minimal outputs. The pattern is: name (for reference), cluster_ip or load balancer hostname (for connectivity), and secret name (for cross-module reference). Computed attributes like `cluster_ip` are only available post-apply (`[plan-unknown]` in unit tests).

---

### Alternatives Considered

| Alternative | Why Not |
|---|---|
| `kubernetes_deployment` (legacy resource) | Deprecated alias; `kubernetes_deployment_v1` is the current name mapping to `apps/v1` API; new modules must use `_v1` |
| Inline base64 of entire JSON blob | Requires the caller to pre-encode; not ergonomic; `jsonencode()` is idiomatic HCL and handles escaping |
| `kubernetes.io/dockercfg` type (old format) | Superseded by `kubernetes.io/dockerconfigjson`; kiwicom uses old format — avoid; modern registries and kubelets expect `.dockerconfigjson` |
| Embedding `provider {}` in module | Violates module constitution §2.1; prevents EKS/GKE/AKS reuse; rejected universally by all public modules |
| `count` for conditional secret creation | `for_each` is preferred per module constitution §2.2; but for a single optional resource, `count = var.create_pull_secret ? 1 : 0` is the observed pattern |
| Separate `image_pull_secret_name` input (pre-existing secret) | Valid pattern for advanced use; add `create_pull_secret = true` toggle with `image_pull_secret_name` override as optional enhancement |

---

### Sources

- Official provider examples: `hashicorp/terraform-provider-kubernetes` GitHub — `examples/resources/secret_v1/example_{1,2,3,4}.tf`, `deployment_v1/example_1.tf`, `service_v1/example_{1,2}.tf`
- Provider documentation templates: `templates/resources/secret_v1.md.tmpl`, `deployment_v1.md.tmpl`, `service_v1.md.tmpl`
- StayWell/jenkins module source: `https://github.com/StayWell/terraform-kubernetes-jenkins` — `main.tf`, `variables.tf`
- kiwicom/namespace module: Terraform Registry `kiwicom/namespace/kubernetes` v3.0.3 (161K downloads) — input/output schema + `main.tf`
- 4ops/clickhouse-server module: `https://github.com/4ops/terraform-kubernetes-clickhouse-server` — `main.tf`, `outputs.tf`
- sailthru/ambassador module: Terraform Registry `sailthru/ambassador/kubernetes` — input schema (30+ variables)
- MarvelOrange/dashboard module: Terraform Registry `MarvelOrange/dashboard/kubernetes` — service_type pattern
- sl1pm4t/redis module: `https://github.com/sl1pm4t/terraform-kubernetes-redis` — `variables.tf` (image/resource/pull-policy variable patterns)
- Terraform Registry search: `https://registry.terraform.io/v1/modules?provider=kubernetes&limit=15`
- Kubernetes provider latest version: `hashicorp/kubernetes` v3.2.1 (1.48B downloads)
- Module constitution: `.foundations/memory/module-constitution.md` §2.1, §2.2, §3.1, §4.1
