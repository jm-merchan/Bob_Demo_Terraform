## Research: Terraform hashicorp/kubernetes Provider Schema — `kubernetes_deployment`, `kubernetes_service`, `kubernetes_secret` (provider >= 2.30)

### Decision

Use the `_v1`-suffixed canonical resource names (`kubernetes_deployment_v1`, `kubernetes_service_v1`, `kubernetes_secret_v1`) — the unversioned aliases (`kubernetes_deployment`, etc.) are identical in schema but the `_v1` names are the preferred form going forward. All three resources use the SDKv2 plugin framework with `TypeList` blocks for single-instance nested objects (not `TypeSet`).

---

### Resources Identified

- **Primary Resources**:
  - `kubernetes_deployment_v1` — manages a Kubernetes Deployment (apps/v1); unversioned alias `kubernetes_deployment` is identical
  - `kubernetes_service_v1` — manages a Kubernetes Service (core/v1); unversioned alias `kubernetes_service` is identical
  - `kubernetes_secret_v1` — manages a Kubernetes Secret (core/v1); unversioned alias `kubernetes_secret` is identical

- **Key Outputs**:
  - `kubernetes_deployment_v1`: `id` (`string`, `<namespace>/<name>`)
  - `kubernetes_service_v1`: `id` (`string`), `status.0.load_balancer.0.ingress.0.hostname` (`string`), `status.0.load_balancer.0.ingress.0.ip` (`string`)
  - `kubernetes_secret_v1`: `id` (`string`)

- **Security Considerations**:
  - `kubernetes_secret_v1.data` is `Sensitive = true` — stored in state as plaintext; use `data_wo` (write-only, added in 2.36) to avoid state exposure
  - Docker registry pull secrets must use `type = "kubernetes.io/dockerconfigjson"` with `.dockerconfigjson` key
  - Container `security_context`: set `run_as_non_root = true`, `read_only_root_filesystem = true`, `allow_privilege_escalation = false`

---

### 1. `kubernetes_deployment_v1` — Argument Schema

#### Top-level required

| Argument | Type | Notes |
|----------|------|-------|
| `metadata` | Block List (Min:1, Max:1) | Standard object metadata |
| `spec` | Block List (Min:1, Max:1) | Deployment specification |

#### Top-level optional

| Argument | Type | Default | Notes |
|----------|------|---------|-------|
| `wait_for_rollout` | Boolean | `true` | Wait for rollout completion before marking resource created |
| `timeouts` | Block | — | `create`, `update`, `delete` (default 10 min each) |

#### `metadata` block

| Argument | Type | Required | Notes |
|----------|------|----------|-------|
| `name` | String | Optional | Must be unique per namespace; omit to use `generate_name` |
| `namespace` | String | Optional | Defaults to `default` |
| `labels` | Map of String | Optional | Key/value label map |
| `annotations` | Map of String | Optional | Key/value annotation map |
| `generate_name` | String | Optional | Server-generated unique suffix; mutually exclusive with `name` |
| `generation` | Number | Read-Only | |
| `resource_version` | String | Read-Only | |
| `uid` | String | Read-Only | |

#### `spec` block

| Argument | Type | Required | Default | Notes |
|----------|------|----------|---------|-------|
| `template` | Block List (Min:1, Max:1) | **Required** | — | Pod template |
| `selector` | Block List (Max:1) | Optional | — | Label selector; `ForceNew = true` |
| `replicas` | **String** | Optional | Computed | ⚠️ Schema quirk: `TypeString`, not Int — allows distinguishing explicit `"0"` from unset |
| `min_ready_seconds` | Number | Optional | `0` | |
| `paused` | Boolean | Optional | `false` | |
| `progress_deadline_seconds` | Number | Optional | `600` | |
| `revision_history_limit` | Number | Optional | `10` | |
| `strategy` | Block List (Max:1) | Optional | — | Rolling update strategy |

#### `spec.selector` block

```hcl
selector {
  match_labels = {          # TypeMap — flat label equality map
    app = "my-app"
  }
  match_expressions {       # TypeList — label requirement expressions
    key      = "env"
    operator = "In"         # In | NotIn | Exists | DoesNotExist
    values   = ["prod"]     # TypeSet of String
  }
}
```

> **Important**: `spec.selector` is `ForceNew = true` — changing it destroys and recreates the Deployment.

#### `spec.template` block

| Argument | Type | Required | Notes |
|----------|------|----------|-------|
| `metadata` | Block List (Min:1, Max:1) | **Required** | Pod metadata — `labels` here must match `spec.selector.match_labels` |
| `spec` | Block List (Min:1, Max:1) | **Required** | Pod spec |

#### `spec.template.spec` (pod spec) — key arguments

| Argument | Type | Required | Notes |
|----------|------|----------|-------|
| `container` | Block List | Optional | No Min constraint in schema; at least one required by Kubernetes |
| `image_pull_secrets` | Block List | Optional | List of secret name references; `TypeList` (not Set) |
| `service_account_name` | String | Optional | |
| `security_context` | Block List (Max:1) | Optional | Pod-level security context |
| `init_container` | Block List | Optional | Init containers |
| `volume` | Block List | Optional | Named volumes |
| `node_selector` | Map of String | Optional | |
| `affinity` | Block List (Max:1) | Optional | |
| `toleration` | Block List | Optional | |
| `termination_grace_period_seconds` | Number | Optional | |
| `automount_service_account_token` | Boolean | Optional | Default `true` |
| `dns_policy` | String | Optional | Default `"ClusterFirst"` |
| `restart_policy` | String | Optional | Default `"Always"` |

---

### 2. `container` Block Schema

Nested under `spec.template.spec.container`:

#### Required

| Argument | Type | Notes |
|----------|------|-------|
| `name` | String | DNS_LABEL; unique within pod |

#### Optional (key fields)

| Argument | Type | Notes |
|----------|------|-------|
| `image` | String | Docker image name |
| `image_pull_policy` | String | `Always` / `Never` / `IfNotPresent`; defaults to `Always` if `:latest` tag |
| `command` | List of String | Overrides Docker ENTRYPOINT |
| `args` | List of String | Overrides Docker CMD |
| `port` | Block List | Container port declarations (**TypeList**, not TypeSet) |
| `resources` | Block List (Max:1) | CPU/memory limits and requests |
| `env` | Block List | Environment variables |
| `env_from` | Block List | Bulk env from ConfigMap/Secret |
| `volume_mount` | Block List | Volume mounts |
| `liveness_probe` | Block List (Max:1) | |
| `readiness_probe` | Block List (Max:1) | |
| `startup_probe` | Block List (Max:1) | |
| `security_context` | Block List (Max:1) | Container-level security |
| `working_dir` | String | |
| `tty` | Boolean | |

#### `container.port` sub-block (TypeList)

```hcl
port {
  container_port = 8080        # Number, Required — 0 < x < 65536
  protocol       = "TCP"       # Optional, default "TCP"
  name           = "http"      # Optional — IANA_SVC_NAME, must be unique in pod
  host_port      = 0           # Optional
  host_ip        = ""          # Optional
}
```

> **Schema quirk**: `container.port` is `TypeList` — blocks are ordered and accessed by index (`container.0.port.0.container_port`). No hash function; use numeric index in test assertions.

#### `container.resources` sub-block (TypeList, Max:1)

```hcl
resources {
  limits = {            # TypeMap of String — Kubernetes resource quantity strings
    cpu    = "500m"
    memory = "512Mi"
  }
  requests = {          # TypeMap of String
    cpu    = "250m"
    memory = "128Mi"
  }
}
```

> **Schema quirk**: Both `limits` and `requests` are `TypeMap` (flat string maps). The provider applies `suppressEquivalentResourceQuantity` diff suppression, so `"1000m"` and `"1"` are treated as equal. Access in tests: `kubernetes_deployment_v1.example.spec.0.template.0.spec.0.container.0.resources.0.limits.cpu`

#### `container.env` sub-block

```hcl
env {
  name  = "DATABASE_URL"         # Required
  value = "postgres://..."       # Optional literal value
  # OR:
  value_from {
    secret_key_ref {             # Max:1
      name     = "my-secret"
      key      = "db-url"
      optional = false
    }
    config_map_key_ref {}        # Max:1 — mutually exclusive usage
    field_ref {}                 # Max:1
    resource_field_ref {}        # Max:1
  }
}
```

---

### 3. `kubernetes_service_v1` — Argument Schema

#### Top-level required

| Argument | Type | Notes |
|----------|------|-------|
| `metadata` | Block List (Min:1, Max:1) | Same structure as deployment metadata |
| `spec` | Block List (Min:1, Max:1) | Service specification |

#### Top-level optional

| Argument | Type | Default | Notes |
|----------|------|---------|-------|
| `wait_for_load_balancer` | Boolean | — | Wait for LB to have ≥1 endpoint |
| `timeouts` | Block | — | `create` timeout string |

#### `spec` block

| Argument | Type | Required | Default | Notes |
|----------|------|----------|---------|-------|
| `port` | Block List (MinItems:1) | Optional | — | **TypeList**; at least 1 item when specified |
| `selector` | **Map of String** | Optional | — | ⚠️ `TypeMap` — NOT a block; flat label equality map |
| `type` | String | Optional | `"ClusterIP"` | `ClusterIP` / `NodePort` / `LoadBalancer` / `ExternalName` |
| `cluster_ip` | String | Optional | Computed | `"None"` for headless services |
| `session_affinity` | String | Optional | `"None"` | `"None"` or `"ClientIP"` |
| `external_traffic_policy` | String | Optional | — | `"Local"` or `"Cluster"` |
| `load_balancer_ip` | String | Optional | — | Only for `type = LoadBalancer` |
| `load_balancer_source_ranges` | Set of String | Optional | — | CIDR whitelist |
| `external_name` | String | Optional | — | Required when `type = ExternalName` |
| `publish_not_ready_addresses` | Boolean | Optional | `false` | |

> **Schema quirk**: `spec.selector` in a Service is a `TypeMap`, not a nested block. Write it as `selector = { app = "my-app" }`, not as a `selector {}` block.

#### `spec.port` sub-block (TypeList, MinItems:1)

```hcl
port {
  port        = 80           # Number, Required — the Service port
  target_port = "8080"       # String (Optional, Computed) — pod port number or named port
  protocol    = "TCP"        # Optional, default "TCP" (TCP | UDP | SCTP)
  name        = "http"       # Optional — required when >1 port defined
  node_port   = 30080        # Number (Optional, Computed) — for NodePort/LoadBalancer
  app_protocol = "http"      # Optional — IANA or custom protocol label
}
```

> **Schema quirk**: `target_port` is `TypeString` (accepts both number strings and named port strings). Use `"80"` not `80` in HCL when specifying numeric target port.

#### `status` output (Read-Only)

```
status.0.load_balancer.0.ingress.0.hostname  # String
status.0.load_balancer.0.ingress.0.ip        # String
```

---

### 4. `kubernetes_secret_v1` — Argument Schema

#### Top-level required

| Argument | Type | Notes |
|----------|------|-------|
| `metadata` | Block List (Min:1, Max:1) | Same structure as other resources |

#### Top-level optional

| Argument | Type | Sensitive | Default | Notes |
|----------|------|-----------|---------|-------|
| `data` | Map of String | **Yes** | Computed | Plain-text key/value secret data; stored in state as plaintext |
| `binary_data` | Map of String | **Yes** | — | Base64-encoded binary data |
| `data_wo` | Map of String | Write-Only | — | Added in 2.36 — does NOT appear in state; requires `data_wo_revision` |
| `data_wo_revision` | Number | No | — | Increment to trigger `data_wo` update; requires `data_wo` |
| `binary_data_wo` | Map of String | Write-Only | — | Write-only binary data (base64); requires `binary_data_wo_revision` |
| `binary_data_wo_revision` | Number | No | — | Increment to trigger `binary_data_wo` update |
| `type` | String | No | `"Opaque"` | `ForceNew = true` — changing type destroys and recreates |
| `immutable` | Boolean | No | `false` | Once `true`, only metadata can change |
| `wait_for_service_account_token` | Boolean | No | `true` | Waits for SA token population |
| `timeouts` | Block | — | — | `create` timeout string |

#### Well-known `type` values

| Type | Use |
|------|-----|
| `"Opaque"` | Default; arbitrary key/value |
| `"kubernetes.io/dockerconfigjson"` | Docker registry credentials — key must be `.dockerconfigjson` |
| `"kubernetes.io/basic-auth"` | Basic auth — keys `username` and `password` |
| `"kubernetes.io/service-account-token"` | Service account token — set annotation `kubernetes.io/service-account.name` |
| `"kubernetes.io/tls"` | TLS cert/key — keys `tls.crt` and `tls.key` |

#### Docker registry secret example (canonical pattern)

```hcl
resource "kubernetes_secret_v1" "registry" {
  metadata {
    name      = "registry-credentials"
    namespace = "default"
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "https://index.docker.io/v1/" = {
          username = var.registry_username
          password = var.registry_password
          auth     = base64encode("${var.registry_username}:${var.registry_password}")
        }
      }
    })
  }
}
```

---

### 5. Wiring `imagePullSecrets` in a Deployment

`image_pull_secrets` sits on the **pod spec** (`spec.template.spec.image_pull_secrets`), not on the container. It references the secret by `.metadata.name`.

#### Schema of `image_pull_secrets` block

```
spec.template.spec.image_pull_secrets  →  TypeList (Block List), Computed = true
  .name  →  TypeString, Required
```

> **Schema quirk**: `image_pull_secrets` is `TypeList` (ordered, index-accessible). It is also `Computed = true` — the cluster may inject additional pull secrets (e.g., from a service account). Do NOT use `one()` in test assertions; use numeric index `.0.name`.

#### Complete wiring pattern

```hcl
resource "kubernetes_secret_v1" "registry" {
  metadata {
    name      = "registry-credentials"
    namespace = var.namespace
  }
  type = "kubernetes.io/dockerconfigjson"
  data = {
    ".dockerconfigjson" = jsonencode({ auths = { ... } })
  }
}

resource "kubernetes_deployment_v1" "app" {
  metadata {
    name      = "my-app"
    namespace = var.namespace
  }

  spec {
    replicas = "2"

    selector {
      match_labels = { app = "my-app" }
    }

    template {
      metadata {
        labels = { app = "my-app" }
      }

      spec {
        image_pull_secrets {
          name = kubernetes_secret_v1.registry.metadata[0].name
        }

        container {
          name  = "app"
          image = "private.registry.example.com/my-app:latest"

          port {
            container_port = 8080
          }

          resources {
            requests = { cpu = "100m", memory = "128Mi" }
            limits   = { cpu = "500m", memory = "512Mi" }
          }
        }
      }
    }
  }
}
```

> **Reference pattern**: `kubernetes_secret_v1.registry.metadata[0].name` — metadata is a `TypeList` so index `[0]` is required. The `metadata` attribute is accessed with bracket notation in expressions, dot notation in test assertions (`kubernetes_secret_v1.registry.metadata.0.name`).

---

### 6. Schema Quirks and Block Type Reference

| Resource / Path | Schema Type | HCL Style | Test Access Pattern | Notes |
|----------------|-------------|-----------|---------------------|-------|
| `deployment_v1.spec` | TypeList Max:1 | `spec { }` block | `.spec.0.replicas` | |
| `deployment_v1.spec.replicas` | **TypeString** | `replicas = "3"` | `.spec.0.replicas` | ⚠️ String, not Number — quote the value |
| `deployment_v1.spec.selector` | TypeList Max:1 | `selector { }` block | `.spec.0.selector.0.match_labels` | ForceNew |
| `deployment_v1.spec.selector.match_labels` | TypeMap | inline map | `.spec.0.selector.0.match_labels.app` | |
| `deployment_v1.spec.selector.match_expressions.values` | **TypeSet** | `values = [...]` | Use `contains()` or `toset()` — no stable index | Cannot index by position |
| `deployment_v1.spec.template.spec.container` | TypeList | `container { }` blocks | `.spec.0.template.0.spec.0.container.0.name` | Ordered list |
| `container.port` | TypeList | `port { }` blocks | `.container.0.port.0.container_port` | Not TypeSet |
| `container.resources` | TypeList Max:1 | `resources { }` block | `.container.0.resources.0.limits.cpu` | `one()` safe |
| `container.resources.limits` | TypeMap | inline map | `.resources.0.limits.cpu` | String quantities |
| `container.resources.requests` | TypeMap | inline map | `.resources.0.requests.memory` | String quantities |
| `container.image_pull_policy` | TypeString | string attribute | `.container.0.image_pull_policy` | |
| `pod_spec.image_pull_secrets` | TypeList | `image_pull_secrets { }` blocks | `.spec.0.image_pull_secrets.0.name` | Computed; cluster may add entries |
| `service_v1.spec.selector` | **TypeMap** | `selector = { }` inline map | `.spec.0.selector.app` | ⚠️ NOT a block — flat map |
| `service_v1.spec.port` | TypeList MinItems:1 | `port { }` blocks | `.spec.0.port.0.port` | |
| `service_v1.spec.port.target_port` | **TypeString** | `target_port = "8080"` | `.spec.0.port.0.target_port` | ⚠️ String, not Number |
| `service_v1.spec.port.node_port` | TypeInt | `node_port = 30080` | `.spec.0.port.0.node_port` | Computed when not set |
| `service_v1.status` | TypeList (Read-Only) | — | `.status.0.load_balancer.0.ingress.0.hostname` | |
| `secret_v1.data` | TypeMap Sensitive | inline map | `.data.key_name` | Stored in state plaintext |
| `secret_v1.type` | TypeString | string attribute | `.type` | ForceNew |
| `metadata` (all resources) | TypeList Min:1 Max:1 | `metadata { }` block | `.metadata.0.name` | Use index `[0]` in expressions, `.0.` in assertions |

#### Critical differences: `kubernetes_deployment_v1` selector vs `kubernetes_service_v1` selector

```hcl
# Deployment selector — nested BLOCK with match_labels map
spec {
  selector {
    match_labels = { app = "my-app" }
  }
}

# Service selector — flat MAP attribute (no block)
spec {
  selector = { app = "my-app" }
}
```

#### `one()` usage guidance

`one()` is appropriate for `TypeList Max:1` blocks where the block may or may not be present. Do NOT use `one()` for:
- `container` (TypeList, unbounded)
- `image_pull_secrets` (TypeList, Computed — cluster may inject entries)
- `spec.selector.match_expressions.values` (TypeSet — use `contains()` or `toset()`)

Use `one()` for: `resources`, `security_context`, `liveness_probe`, `readiness_probe`, `affinity`, `strategy`.

#### `replicas` string quirk detail

```hcl
# Correct
replicas = "2"

# Also valid — explicitly zero pods
replicas = "0"

# If omitted entirely, Kubernetes defaults to 1 and the provider marks it Computed
```

The `validateTypeStringNullableInt` validator accepts `null` or any non-negative integer string. In test assertions compare as a string: `kubernetes_deployment_v1.example.spec.0.replicas == "2"`.

#### `data_wo` write-only pattern (2.36+)

```hcl
resource "kubernetes_secret_v1" "example" {
  metadata { name = "my-secret" }
  type = "Opaque"

  # Write-only: value never stored in state
  data_wo = {
    password = var.password
  }
  data_wo_revision = 1  # Increment to force update
}
```

When `data_wo_revision > 0`, the provider suppresses diffs on `data` to avoid conflicts.

---

### Rationale

All schema details are sourced directly from:
1. The generated `docs/resources/deployment_v1.md`, `docs/resources/service_v1.md`, and `docs/resources/secret_v1.md` at tag `v2.38.0` — produced by `tfplugindocs` from live schema introspection.
2. Go source files `kubernetes/resource_kubernetes_deployment_v1.go`, `kubernetes/schema_pod_spec.go`, `kubernetes/schema_container.go`, `kubernetes/resource_kubernetes_service_v1.go`, `kubernetes/resource_kubernetes_secret_v1.go` at tag `v2.38.0` — confirming exact `schema.Type*` declarations, `ForceNew` flags, `Computed` flags, `Sensitive` flags, and hash functions.
3. CHANGELOG for breaking changes in the 2.30–2.38 range.

### Alternatives Considered

| Alternative | Why Not |
|-------------|---------|
| `kubernetes_manifest` (generic) | Accepts raw YAML/JSON manifests; no schema validation, no plan-time type checking, cannot mock in unit tests with `mock_provider` |
| `kubernetes_deployment` (unversioned alias) | Identical schema; `_v1` suffix is the preferred canonical name per provider docs |
| Using `binary_data` for docker config | `binary_data` requires pre-base64 encoding; `data` with `jsonencode()` is cleaner and the documented pattern |
| `TypeSet` blocks for containers | The provider uses `TypeList` for containers — ordering is deterministic and index-based access works; no `one()` needed for single containers but numeric index is correct |

### Sources

- Provider registry docs: https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs
- `kubernetes_deployment_v1` schema (v2.38.0): https://raw.githubusercontent.com/hashicorp/terraform-provider-kubernetes/v2.38.0/docs/resources/deployment_v1.md
- `kubernetes_service_v1` schema (v2.38.0): https://raw.githubusercontent.com/hashicorp/terraform-provider-kubernetes/v2.38.0/docs/resources/service_v1.md
- `kubernetes_secret_v1` schema (v2.38.0): https://raw.githubusercontent.com/hashicorp/terraform-provider-kubernetes/v2.38.0/docs/resources/secret_v1.md
- Go source — container schema: https://github.com/hashicorp/terraform-provider-kubernetes/blob/v2.38.0/kubernetes/schema_container.go
- Go source — pod spec schema: https://github.com/hashicorp/terraform-provider-kubernetes/blob/v2.38.0/kubernetes/schema_pod_spec.go
- Go source — deployment resource: https://github.com/hashicorp/terraform-provider-kubernetes/blob/v2.38.0/kubernetes/resource_kubernetes_deployment_v1.go
- Go source — service resource: https://github.com/hashicorp/terraform-provider-kubernetes/blob/v2.38.0/kubernetes/resource_kubernetes_service_v1.go
- Go source — secret resource: https://github.com/hashicorp/terraform-provider-kubernetes/blob/v2.38.0/kubernetes/resource_kubernetes_secret_v1.go
- CHANGELOG (2.30–2.38): https://github.com/hashicorp/terraform-provider-kubernetes/blob/v2.38.0/CHANGELOG.md
- Kubernetes imagePullSecrets docs: https://kubernetes.io/docs/concepts/containers/images/#specifying-imagepullsecrets-on-a-pod
- Kubernetes Secret types: https://kubernetes.io/docs/concepts/configuration/secret/#secret-types
