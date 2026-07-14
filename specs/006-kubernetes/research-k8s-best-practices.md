## Research: Kubernetes and AWS EKS best practices for containerised workloads with ICR pull secret

### Decision

Use `kubernetes_secret_v1` (type `kubernetes.io/dockerconfigjson`) for the ICR pull secret, `kubernetes_deployment_v1` with hardened security context and explicit resource requests/limits, and `kubernetes_service_v1` with type `ClusterIP` as the secure default — exposing externally only through an AWS Load Balancer Controller Ingress, not a raw `LoadBalancer` Service. All five topic areas below are confirmed against hashicorp/kubernetes provider v3.2.1 docs and Kubernetes upstream documentation.

---

### 1. ICR Pull Secret — `kubernetes.io/dockerconfigjson`

#### Structure of the JSON payload

The Kubernetes `kubernetes.io/dockerconfigjson` secret type requires a single data key `.dockerconfigjson` whose value is the JSON-encoded Docker credentials object:

```json
{
  "auths": {
    "<registry-hostname>": {
      "username": "<username>",
      "password": "<password>",
      "email":    "<email>",
      "auth":     "<base64(username:password)>"
    }
  }
}
```

For IBM Container Registry (ICR) the registry hostname is region-specific:
- `us.icr.io` — US South
- `uk.icr.io` — UK South
- `de.icr.io` — EU Central
- `au.icr.io` — AP South
- `jp.icr.io` — AP North
- `global.icr.io` — global (multi-region)

The `auth` field value is `base64encode("<username>:<password>")` — commonly `iamapikey:<ICR_API_KEY>` for IBM Cloud IAM API key authentication.

#### Terraform resource — correct encoding pattern

The provider's `data` argument accepts a `Map of String`. The entire `.dockerconfigjson` value must be a JSON string. Use `jsonencode()` to produce the JSON and let Terraform handle escaping — do **not** use `base64encode()` on the outer payload; the provider stores `data` values as plain strings and base64-encodes them internally when writing to the Kubernetes API.

```hcl
resource "kubernetes_secret_v1" "icr_pull_secret" {
  metadata {
    name      = "${var.app_name}-icr-pull-secret"
    namespace = var.namespace
    labels    = local.common_labels
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "${var.icr_hostname}" = {
          username = var.icr_username          # typically "iamapikey"
          password = var.icr_api_key           # sensitive
          email    = var.icr_email
          auth     = base64encode("${var.icr_username}:${var.icr_api_key}")
        }
      }
    })
  }
}
```

The corresponding variable for `icr_api_key` must be `sensitive = true` in Terraform.

**Alternative — `binary_data_wo` (write-only, provider v3.x):** For Terraform >= 1.11 with provider v3.x, the `data_wo` / `binary_data_wo` write-only attributes prevent the secret payload from appearing in state at all. This is the preferred approach for new modules:

```hcl
resource "kubernetes_secret_v1" "icr_pull_secret" {
  metadata {
    name      = "${var.app_name}-icr-pull-secret"
    namespace = var.namespace
  }
  type = "kubernetes.io/dockerconfigjson"

  data_wo = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "${var.icr_hostname}" = {
          username = var.icr_username
          password = var.icr_api_key
          email    = var.icr_email
          auth     = base64encode("${var.icr_username}:${var.icr_api_key}")
        }
      }
    })
  }
  data_wo_revision = 1
}
```

#### Key schema notes

| Attribute | Type | Notes |
|---|---|---|
| `type` | `string` | Must be `"kubernetes.io/dockerconfigjson"` — enforced by kubelet |
| `data` | `map(string)` | Key must be exactly `".dockerconfigjson"` |
| `data_wo` | `map(string)`, write-only | Preferred — not stored in state |
| `metadata.namespace` | `string` | Must match the Deployment's namespace |
| `immutable` | `bool` | Set `true` once deployed — prevents accidental mutation |

#### Security considerations

- Mark `icr_api_key` variable `sensitive = true` — Terraform redacts it from plan output
- Prefer `data_wo` over `data` to keep the credential off the state file entirely
- Use a dedicated ICR service ID with `Reader` role scoped to the target namespace/registry only — do not use a personal IAM API key
- Rotate the pull secret by incrementing `data_wo_revision` — Kubernetes will rolling-restart pods that reference it

---

### 2. Deployment Security Context

#### Pod-level security context (`spec.template.spec.security_context`)

Set at the pod level to apply to all containers:

```hcl
security_context {
  run_as_non_root = true
  run_as_user     = "1000"   # non-zero UID; string type in Terraform provider
  run_as_group    = "3000"   # string type in Terraform provider
  fs_group        = "2000"   # string type; allows volume ownership handoff

  seccomp_profile {
    type = "RuntimeDefault"  # uses the container runtime's default seccomp filter
  }
}
```

#### Container-level security context (`spec.template.spec.container.security_context`)

```hcl
security_context {
  allow_privilege_escalation = false
  privileged                 = false
  read_only_root_filesystem  = true
  run_as_non_root            = true    # redundant with pod-level but belt-and-suspenders

  capabilities {
    drop = ["ALL"]           # drop every Linux capability
    # add = ["NET_BIND_SERVICE"]  # only re-add if port < 1024 is required
  }
}
```

**`drop = ["ALL"]` with `add = []`** is the NSA/CISA Kubernetes Hardening Guide baseline. Do not add capabilities unless the workload explicitly requires them. For an HTTP application serving on port ≥ 1024, no capabilities need to be re-added.

#### `read_only_root_filesystem` — write paths

When `read_only_root_filesystem = true`, any path the application writes to (temp files, logs, PID files) must be an explicit `emptyDir` volume mount:

```hcl
volume_mount {
  name       = "tmp"
  mount_path = "/tmp"
}
# In spec.template.spec.volume:
volume {
  name = "tmp"
  empty_dir {}
}
```

#### Resource requests and limits

Both `requests` and `limits` **must** be set to prevent noisy-neighbour eviction and to satisfy the Kubernetes LimitRange admission controller (common in EKS hardened clusters). The `resources` block uses `Map of String` — values are Kubernetes resource quantity strings.

```hcl
resources {
  requests = {
    cpu    = "100m"    # 0.1 vCPU guaranteed
    memory = "128Mi"   # 128 MiB guaranteed
  }
  limits = {
    cpu    = "500m"    # 0.5 vCPU maximum; omit CPU limit if workload is bursty
    memory = "256Mi"   # hard memory ceiling — OOMKilled if exceeded
  }
}
```

**CPU limits guidance**: Setting `cpu` in `limits` is optional — unbounded CPU is acceptable when Burstable QoS is desired. Setting `memory` in `limits` is mandatory to prevent unbounded memory growth from killing other pods. Setting both `requests == limits` gives the pod `Guaranteed` QoS (highest scheduling priority, never evicted under memory pressure unless it exceeds its own limit).

**Schema note**: `resources` is a single nested block (Max: 1). In `.tftest.hcl` assertions use `one(resource.kubernetes_deployment_v1.app.spec[0].template[0].spec[0].container[0].resources).limits["memory"]`.

#### Summary — security context checklist

| Control | Attribute | Value |
|---|---|---|
| Non-root enforcement (pod) | `security_context.run_as_non_root` | `true` |
| Non-root UID (pod) | `security_context.run_as_user` | `"1000"` (or image-specific) |
| Read-only rootfs (container) | `security_context.read_only_root_filesystem` | `true` |
| No privilege escalation | `security_context.allow_privilege_escalation` | `false` |
| Drop all capabilities | `security_context.capabilities.drop` | `["ALL"]` |
| Seccomp profile | `security_context.seccomp_profile.type` | `"RuntimeDefault"` |
| Not privileged | `security_context.privileged` | `false` (default, explicit) |
| CPU request | `resources.requests.cpu` | workload-appropriate (e.g., `"100m"`) |
| Memory request | `resources.requests.memory` | workload-appropriate (e.g., `"128Mi"`) |
| Memory limit | `resources.limits.memory` | required (e.g., `"256Mi"`) |

---

### 3. Service Type Selection — ClusterIP vs LoadBalancer on EKS

#### Recommendation: `ClusterIP` as default; use Ingress for external access

On EKS, `type = LoadBalancer` creates a **Classic ELB** (legacy) or NLB depending on annotations. This has significant drawbacks:

- Each `LoadBalancer` Service provisions a separate AWS load balancer — high cost at scale
- Classic ELB is deprecated; NLB does not support HTTP path-based routing
- `LoadBalancer` Services expose a public endpoint without WAF, TLS termination, or certificate management by default
- The AWS Load Balancer Controller (ALBC) replaces the in-tree cloud provider for EKS and is the recommended path

**Correct EKS pattern:**

```
Pods ← ClusterIP Service ← Ingress (ALBC) ← AWS ALB
```

Use `type = "ClusterIP"` for the `kubernetes_service_v1` resource. Expose the workload externally via a `kubernetes_ingress_v1` resource that ALBC converts into an AWS Application Load Balancer — this is the EKS-recommended approach for HTTP workloads.

```hcl
resource "kubernetes_service_v1" "app" {
  metadata {
    name      = var.app_name
    namespace = var.namespace
    labels    = local.common_labels
  }

  spec {
    type     = "ClusterIP"      # internal only — no AWS resource created
    selector = local.pod_labels # must match Deployment pod template labels

    port {
      name        = "http"
      port        = 80
      target_port = var.container_port   # e.g. 8080
      protocol    = "TCP"
    }
  }
}
```

#### When `LoadBalancer` IS appropriate

Use `type = "LoadBalancer"` with ALBC annotations only when:
- An NLB (layer 4 TCP/UDP) is explicitly required (e.g., gRPC, websockets needing preserve source IP)
- The service is internal (`service.beta.kubernetes.io/aws-load-balancer-scheme: internal`)
- Controlled through ALBC with `service.beta.kubernetes.io/aws-load-balancer-type: external`

If using `LoadBalancer`, always add:
```hcl
metadata {
  annotations = {
    "service.beta.kubernetes.io/aws-load-balancer-type"   = "external"
    "service.beta.kubernetes.io/aws-load-balancer-scheme" = "internal"   # default to internal
    "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
  }
}
```

#### Schema note for `kubernetes_service_v1`

- `spec` is a single block (Max: 1)
- `spec.type` valid values: `"ClusterIP"` (default), `"NodePort"`, `"LoadBalancer"`, `"ExternalName"`
- `spec.selector` is `Map of String` — must match pod template labels exactly
- `status` is Read-Only — `status[0].load_balancer[0].ingress[*].hostname` for ALB DNS (plan-unknown)
- `wait_for_load_balancer = true` is the default; set `false` for `ClusterIP` to avoid unnecessary wait

---

### 4. Health Check Probes — Liveness and Readiness

#### Probe types available (per provider v3.2.1)

Each probe block (`liveness_probe`, `readiness_probe`, `startup_probe`) supports:
- `http_get` — HTTP GET to a path/port (preferred for HTTP workloads)
- `tcp_socket` — TCP connection check (for non-HTTP services)
- `exec` — command execution in container
- `grpc` — gRPC health protocol

#### Recommended configuration for an HTTP application

```hcl
# Readiness probe: gates traffic — more conservative thresholds
readiness_probe {
  http_get {
    path   = "/health/ready"   # dedicated readiness endpoint
    port   = var.container_port
    scheme = "HTTP"
  }
  initial_delay_seconds = 10   # allow application to start
  period_seconds        = 10   # check every 10s
  timeout_seconds       = 5    # fail if no response in 5s
  failure_threshold     = 3    # 3 consecutive failures → remove from endpoints
  success_threshold     = 1    # 1 success → add back to endpoints
}

# Liveness probe: kills and restarts the pod — more tolerant thresholds
liveness_probe {
  http_get {
    path   = "/health/live"    # dedicated liveness endpoint (lightweight)
    port   = var.container_port
    scheme = "HTTP"
  }
  initial_delay_seconds = 30   # allow full startup before kill kicks in
  period_seconds        = 20   # check every 20s — less aggressive than readiness
  timeout_seconds       = 5
  failure_threshold     = 3    # 3 consecutive failures → restart pod
  success_threshold     = 1
}

# Startup probe: protects slow-starting containers from liveness killing them early
startup_probe {
  http_get {
    path   = "/health/live"
    port   = var.container_port
    scheme = "HTTP"
  }
  initial_delay_seconds = 0
  period_seconds        = 10
  failure_threshold     = 30   # 30 * 10s = 5 min max startup window
  success_threshold     = 1
  timeout_seconds       = 5
}
```

#### Key best practices — probe design

| Practice | Rationale |
|---|---|
| Use **separate** `/health/ready` and `/health/live` endpoints | Readiness can check downstream dependencies; liveness must NEVER check external dependencies (a failing dep would cause an infinite restart loop) |
| `startup_probe` for slow-starting JVM/Node apps | Prevents liveness from killing the pod during a long JVM warm-up; `failure_threshold × period_seconds` defines the max startup window |
| `initial_delay_seconds` on liveness ≥ startup time | Without a startup probe, set this to your p99 startup time |
| Readiness `failure_threshold = 3`, liveness `failure_threshold ≥ 3` | Liveness restarts are disruptive; prefer higher threshold to avoid flapping |
| HTTP probe path must return `2xx` for success | Any non-2xx (including 3xx redirects) is treated as failure |
| Avoid `exec` probes in resource-constrained pods | Each exec forks a process; at high pod density this creates CPU spikes |
| Do NOT use the root path (`/`) as a probe endpoint | Root paths often serve application traffic and may include auth middleware that causes false failures |

#### Schema notes

- Each probe is a single block (Max: 1)
- `http_get`, `tcp_socket`, `exec`, `grpc` are mutually exclusive per probe — only one may be set
- `success_threshold` for `liveness_probe` and `startup_probe` **must** be 1 (Kubernetes API enforces this)
- All timing fields are in seconds (`Number` type in Terraform)

---

### 5. Label and Selector Conventions

#### Kubernetes recommended label set (from k8s.io/docs/concepts/overview/working-with-objects/common-labels)

The upstream convention defines these well-known labels under the `app.kubernetes.io/` prefix:

| Label key | Example value | Applied to |
|---|---|---|
| `app.kubernetes.io/name` | `"my-app"` | All objects |
| `app.kubernetes.io/instance` | `"my-app-production"` | All objects |
| `app.kubernetes.io/version` | `"1.0.0"` | All objects |
| `app.kubernetes.io/component` | `"api"` | All objects |
| `app.kubernetes.io/part-of` | `"my-platform"` | All objects |
| `app.kubernetes.io/managed-by` | `"terraform"` | All objects |

#### Terraform pattern — single `locals` block as the source of truth

```hcl
locals {
  # Selector labels — MUST remain stable; changing these forces a Deployment replace
  pod_selector_labels = {
    "app.kubernetes.io/name"     = var.app_name
    "app.kubernetes.io/instance" = "${var.app_name}-${var.environment}"
  }

  # Full label set — applied to all metadata blocks
  common_labels = merge(local.pod_selector_labels, {
    "app.kubernetes.io/version"    = var.app_version
    "app.kubernetes.io/component"  = var.component
    "app.kubernetes.io/part-of"    = var.part_of
    "app.kubernetes.io/managed-by" = "terraform"
    "environment"                  = var.environment
  })
}
```

#### Wiring labels through all three resources

```
kubernetes_secret_v1.icr_pull_secret.metadata.labels    = local.common_labels
kubernetes_deployment_v1.app.metadata.labels             = local.common_labels
kubernetes_deployment_v1.app.spec.selector.match_labels  = local.pod_selector_labels  ← IMMUTABLE
kubernetes_deployment_v1.app.spec.template.metadata.labels = local.pod_selector_labels ← must match selector
kubernetes_service_v1.app.metadata.labels                = local.common_labels
kubernetes_service_v1.app.spec.selector                  = local.pod_selector_labels  ← must match pod labels
```

#### Critical constraint — selector immutability

`spec.selector.match_labels` in a Deployment is **immutable after creation**. Changing selector labels requires deleting and recreating the Deployment. For Terraform, use `lifecycle { create_before_destroy = true }` with a `name_prefix` (or version suffix) if label changes are expected.

The pod template labels (`spec.template.metadata.labels`) must be a **superset** of the selector labels. It is valid for pods to carry extra labels that the selector does not use — this is the standard pattern for carrying version and component labels without forcing selector changes on every release.

#### Namespace label

Always label the `kubernetes_namespace_v1` resource with the same `app.kubernetes.io/managed-by = "terraform"` label to enable namespace-scoped RBAC and NetworkPolicy targeting:

```hcl
resource "kubernetes_namespace_v1" "app" {
  metadata {
    name   = var.namespace
    labels = local.common_labels
  }
}
```

---

### Resources Identified

- **Primary Resources**:
  - `kubernetes_secret_v1` (providerDocID: 12692229) — ICR pull secret storage
  - `kubernetes_deployment_v1` (providerDocID: 12692181) — workload deployment and pod template
  - `kubernetes_service_v1` (providerDocID: 12692234) — ClusterIP service exposing pods

- **Supporting Resources**:
  - `kubernetes_namespace_v1` (providerDocID: 12692203) — namespace isolation
  - `kubernetes_ingress_v1` (providerDocID: 12692193) — external HTTP(S) exposure via ALBC

- **Key Arguments** (Deployment):
  - `spec.template.spec.image_pull_secrets[].name` — references the `kubernetes_secret_v1` name
  - `spec.template.spec.security_context` — pod-level security (non-root, fsGroup, seccomp)
  - `spec.template.spec.container.security_context` — container-level (drop ALL, no privilege escalation, ROFS)
  - `spec.template.spec.container.resources` — requests + limits (Map of String)
  - `spec.template.spec.container.liveness_probe` / `readiness_probe` / `startup_probe` — health checks
  - `spec.selector.match_labels` — immutable pod selector

- **Key Outputs**:
  - `kubernetes_service_v1.app.metadata[0].name` (`string`) — service name for Ingress backend
  - `kubernetes_deployment_v1.app.metadata[0].uid` (`string`) — deployment UID
  - `kubernetes_secret_v1.icr_pull_secret.metadata[0].name` (`string`) — secret name for pod spec

- **Security Considerations**:
  - Pull secret: use `data_wo` (write-only) to keep ICR API key out of state; mark variable `sensitive = true`
  - Pod: `run_as_non_root = true`, `read_only_root_filesystem = true`, `drop = ["ALL"]`, `allow_privilege_escalation = false`
  - Service: default to `ClusterIP`; never expose `LoadBalancer` publicly without ALBC annotations + `scheme = internal`
  - Probes: separate liveness/readiness endpoints; liveness must not call external services

---

### Alternatives Considered

| Alternative | Why Not |
|---|---|
| `kubernetes_secret` (legacy, non-`_v1`) | Deprecated alias; use canonical `_v1` resource names in all new modules |
| `binary_data` for pull secret | `data` accepts string values; `binary_data` is for non-UTF-8 byte sequences; `.dockerconfigjson` is UTF-8 JSON |
| `type = "LoadBalancer"` Service | Provisions a separate AWS ELB per service — costly, no HTTP routing, no TLS termination; replace with ClusterIP + Ingress |
| `type = "NodePort"` Service | Exposes a port on every node; bypasses security groups; only appropriate for very specific edge cases |
| Single shared label for pod selector | `app: myapp` without `app.kubernetes.io/` prefix works but violates upstream conventions and collides across multi-tenancy |
| Liveness probe checking a database | External dependency check in liveness causes restart storms when the DB is slow — use readiness for dependency checks only |
| Setting `cpu` limit equal to `cpu` request | Creates `Guaranteed` QoS which is correct for latency-sensitive workloads; for batch/background use `Burstable` (limit > request) |

---

### Rationale

1. **Pull secret encoding**: The Kubernetes API requires the `.dockerconfigjson` key to contain a valid JSON-encoded docker config. Using `jsonencode()` in Terraform produces a correctly escaped string without double-encoding. The `auth` field inside the JSON payload is the only value that needs `base64encode()` — this mirrors what `kubectl create secret docker-registry` produces. The write-only `data_wo` field (provider v3.x + Terraform 1.11+) prevents the API key from appearing in `terraform state show` output, which is the preferred mitigation for secret exposure in state.

2. **Security context**: NSA/CISA Kubernetes Hardening Guide (August 2022), CIS Kubernetes Benchmark v1.8.0, and AWS EKS Best Practices Guide all require `run_as_non_root`, `read_only_root_filesystem`, `drop ALL capabilities`, and `allow_privilege_escalation = false` as the baseline for untrusted workloads. `seccomp RuntimeDefault` blocks ~40% of Linux syscalls by default and is available on all EKS 1.19+ node AMIs.

3. **ClusterIP + Ingress over LoadBalancer**: AWS documentation for EKS explicitly recommends the AWS Load Balancer Controller with Ingress over the in-tree `LoadBalancer` service type for HTTP workloads. Each raw `LoadBalancer` Service creates an ELB/NLB object — at scale this becomes expensive. ALBC with a single ALB handles multiple services via path-based routing rules, supports ACM certificate management, WAF integration, and access logs automatically.

4. **Separate probe endpoints**: Kubernetes documentation and the Google SRE book both recommend dedicated health endpoints. The liveness probe must reflect only the container's internal health (is the process alive and not deadlocked), while the readiness probe may reflect upstream dependency health (is this replica ready to serve traffic). Mixing the two causes restart cascades.

5. **Label conventions**: The `app.kubernetes.io/` prefix is the Kubernetes upstream standard (documented at kubernetes.io/docs/concepts/overview/working-with-objects/common-labels). Using a single `locals` block as the source of truth for labels prevents label drift between the Deployment selector, pod template, and Service selector — which would silently break pod-to-service routing.

---

### Sources

- hashicorp/kubernetes provider v3.2.1 docs — `kubernetes_secret_v1` (12692229), `kubernetes_deployment_v1` (12692181), `kubernetes_service_v1` (12692234)
- Kubernetes API reference — Secrets: https://kubernetes.io/docs/concepts/configuration/secret/#docker-config-secrets
- Kubernetes API reference — Security Context: https://kubernetes.io/docs/tasks/configure-pod-container/security-context/
- Kubernetes API reference — Probes: https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#container-probes
- Kubernetes well-known labels: https://kubernetes.io/docs/concepts/overview/working-with-objects/common-labels/
- AWS EKS Best Practices Guide — Security: https://aws.github.io/aws-eks-best-practices/security/docs/pods/
- AWS Load Balancer Controller docs: https://kubernetes-sigs.github.io/aws-load-balancer-controller/
- NSA/CISA Kubernetes Hardening Guide (August 2022): https://media.defense.gov/2022/Aug/29/2003066362/-1/-1/0/CTR_KUBERNETES_HARDENING_GUIDANCE_1.2_20220829.PDF
- CIS Kubernetes Benchmark v1.8.0: https://www.cisecurity.org/benchmark/kubernetes
- IBM Container Registry authentication: https://cloud.ibm.com/docs/Registry?topic=Registry-registry_access
