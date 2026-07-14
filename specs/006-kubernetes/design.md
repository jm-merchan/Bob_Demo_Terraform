# Module Design: terraform-kubernetes-app-deploy

**Branch**: feat/006-kubernetes
**Date**: 2025-01-31
**Status**: Draft
**Provider**: hashicorp/kubernetes >= 2.36
**Terraform**: >= 1.14

---

## Table of Contents

1. [Purpose & Requirements](#1-purpose--requirements)
2. [Resources & Architecture](#2-resources--architecture)
3. [Interface Contract](#3-interface-contract)
4. [Security Controls](#4-security-controls)
5. [Test Scenarios](#5-test-scenarios)
6. [Implementation Checklist](#6-implementation-checklist)
7. [Open Questions](#7-open-questions)

---

## 1. Purpose & Requirements

`terraform-kubernetes-app-deploy` is a reusable Terraform module that deploys a single containerised application workload into an existing Kubernetes namespace. It is consumed by platform and application teams that need a repeatable, security-hardened deployment unit without writing raw Kubernetes manifests. The module provisions the three primitives every HTTP application needs — a pull-secret for accessing a private container registry, a replicated pod controller that enforces non-root execution and read-only root filesystem, and a network-accessible service endpoint — while keeping registry credentials out of Terraform state via the provider's write-only secret API.

**Scope boundary**: This module does NOT provision EKS clusters, Kubernetes namespaces, Ingress resources, TLS certificates, IAM roles, Horizontal Pod Autoscalers, ConfigMaps, PersistentVolumes, or any AWS-native cloud resource. Provider configuration (cluster endpoint, CA certificate, authentication token) is the consumer's responsibility and MUST be wired externally before calling this module.

### Requirements

**Functional requirements** — what the module must do (from Phase 1 clarification):

- The module MUST create a private-registry pull secret in the target namespace using credentials supplied via sensitive variables, such that pods can pull images from a private container registry without additional consumer configuration.
- The module MUST deploy a replicated pod controller targeting the supplied container image with a configurable replica count (1–100) and configurable resource requests and limits per container.
- The module MUST expose the deployed pods via a Kubernetes service whose type is configurable (`ClusterIP`, `NodePort`, or `LoadBalancer`) and defaults to `ClusterIP` (no external exposure by default).
- Container port, liveness probe path, and readiness probe path MUST be independently configurable with safe defaults; probes MUST be independently toggleable.
- Registry credentials MUST NOT appear in Terraform state after apply; the module MUST use a write-only secret attribute and require the consumer to supply a revision counter to signal credential rotation.
- The pull secret MUST be protected against accidental deletion via a lifecycle guard.
- All Kubernetes resource names and pod-selector labels MUST be derived from a single `app_name` input to prevent label drift across the deployment, service, and secret.
- The pod selector MUST use `app.kubernetes.io/` prefixed labels aligned with upstream Kubernetes labelling conventions.

**Non-functional requirements** — constraints that bound the design:

- Provider version MUST be `>= 2.36` to guarantee availability of the `data_wo` / `data_wo_revision` write-only secret API (added in 2.36, bug-fixed in 3.2.1; pin lower bound accordingly).
- Terraform version MUST be `>= 1.14` (write-only variable support requires >= 1.11; 1.14 is the project-wide minimum per constitution §4.1).
- The module MUST be provider-agnostic: it MUST NOT contain a `provider {}` block; all cluster credentials come from the consumer (constitution §2.1).
- Pod security context MUST enforce non-root execution and capability dropping aligned with the NSA/CISA Kubernetes Hardening Guide and CIS Kubernetes Benchmark v1.8.0.
- Input validation MUST enforce RFC 1123 DNS label format for namespace and replica bounds of 1–100; these guardrails MUST be surfaced as clear Terraform validation error messages.
- All resources MUST carry `app.kubernetes.io/managed-by = "terraform"` labels for operational discoverability.

---

## 2. Resources & Architecture

### Architectural Decisions

**Canonical `_v1` resource names**: `kubernetes_secret_v1`, `kubernetes_deployment_v1`, and `kubernetes_service_v1` are used throughout. *Rationale*: The `_v1` suffixed names are the preferred canonical form in the provider (confirmed from `docs/resources/deployment_v1.md` at tag v2.38.0) and map to stable Kubernetes API versions (`apps/v1`, `core/v1`). The unversioned aliases (`kubernetes_deployment`, etc.) are identical in schema but risk deprecation. *Source*: research-provider-schema.md §Alternatives Considered; provider registry docs at https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs. *Rejected*: `kubernetes_manifest` (generic) — no schema validation, no plan-time type checking, cannot be mocked in unit tests with `mock_provider`.

**Write-only registry secret via `data_wo` + `data_wo_revision`**: The `kubernetes_secret_v1` resource's `data_wo` attribute (provider >= 2.36) stores the `.dockerconfigjson` payload without ever writing it to Terraform state. The consumer increments `data_wo_revision` to signal a credential rotation. *Rationale*: Using `data` stores the Docker registry password as base64-encoded plaintext in the `.tfstate` file even with `sensitive = true`. `data_wo` eliminates the exposure entirely (research-provider-schema.md §4 `data_wo` write-only pattern; research-edge-cases.md §2 `data_wo` vs `data`; CHANGELOG v2.36.0 addition, v3.2.1 bug fix — pin `>= 3.2.1` for production use). *Source*: research-edge-cases.md §5 Issue 6. *Rejected*: `data` (Map of String, Sensitive) — plaintext in state; `binary_data` — requires pre-base64 encoding, not idiomatic for UTF-8 JSON payload.

**`jsonencode()` + `base64encode()` for dockerconfigjson payload**: The `.dockerconfigjson` value is constructed with `jsonencode()` and an inline `base64encode()` for the `auth` field. *Rationale*: This is the canonical approach from the official provider documentation example (`example_3.tf`), equivalent to `kubectl create secret docker-registry`. It handles special characters in passwords correctly via JSON escaping; raw string interpolation breaks on passwords containing quotes (research-registry-patterns.md §4 Approach B). *Source*: research-registry-patterns.md §Rationale point 1. *Rejected*: File-based approach (`file(...)`) — not usable in a reusable module accepting credentials as variables; kiwicom inline-string anti-pattern — breaks on special characters.

**`prevent_destroy = true` lifecycle on registry secret, no `create_before_destroy`**: The pull secret carries `lifecycle { prevent_destroy = true }`. *Rationale*: Accidental deletion causes `ImagePullBackOff` for all pods pulling from the private registry. `create_before_destroy` CANNOT be combined with a fixed `metadata.name` — Kubernetes enforces name uniqueness within a namespace and returns HTTP 409 Conflict on a duplicate create (research-edge-cases.md §3). The `ignore_changes = [metadata[0].resource_version]` guard prevents perpetual drift from Kubernetes controller mutations. *Source*: research-edge-cases.md §3 Correct Lifecycle Block. *Rejected*: `create_before_destroy` — fails with fixed name; `immutable = true` — blocks credential rotation.

**Single `app_name` label coupling**: A single `locals.pod_selector_labels` map `{ "app.kubernetes.io/name" = var.app_name }` is the source of truth for the deployment's `spec.selector.match_labels`, the pod template's `metadata.labels`, and the service's `spec.selector`. *Rationale*: All surveyed registry modules (StayWell/jenkins, 4ops/clickhouse) use a single app-name variable for label coupling. `spec.selector.match_labels` is `ForceNew` in the provider — changing it destroys and recreates the Deployment. Using `app.kubernetes.io/` prefixed labels follows the upstream Kubernetes labelling convention (research-k8s-best-practices.md §5). *Source*: research-registry-patterns.md §2 Label coupling. *Rejected*: bare `app` label key — violates upstream conventions and collides in multi-tenant clusters; per-resource label sets — creates selector drift risk.

**`ClusterIP` default for service type**: The module defaults `service_type = "ClusterIP"`. *Rationale*: On EKS, `type = "LoadBalancer"` provisions a separate AWS ELB per service — costly, lacks HTTP routing, no TLS termination. The recommended EKS pattern is ClusterIP + Ingress via the AWS Load Balancer Controller. `NodePort` exposes a port on every node, bypassing security groups. ClusterIP ensures zero external exposure by default (research-k8s-best-practices.md §3). *Source*: research-k8s-best-practices.md §3 Recommendation. *Rejected*: `LoadBalancer` as default — creates public endpoints without WAF/TLS; `NodePort` as default — bypasses security groups.

**`replicas` string coercion**: The variable `replicas` is typed `number` in the module interface for ergonomics but MUST be coerced to string when passed to the provider via `tostring(var.replicas)`. *Rationale*: The `kubernetes_deployment_v1.spec.replicas` attribute is `TypeString` in the provider schema — it allows distinguishing explicit `"0"` from unset (Computed). Passing a number directly causes a type error (research-provider-schema.md §`spec` block table note; research-edge-cases.md §4 Replica Count Bounds). *Source*: research-provider-schema.md §6 `replicas` string quirk detail.

**Two-state boundary — consumer wires the kubernetes provider**: The module accepts `cluster_endpoint`, `cluster_ca_cert`, and `cluster_name` as pass-through informational inputs for documentation purposes; the consumer is solely responsible for the `provider "kubernetes" {}` block. *Rationale*: The official provider documentation contains an explicit WARNING against configuring the kubernetes provider from computed resource values in the same module — this causes provider initialisation failures on first apply (research-edge-cases.md §1 Same-Module Anti-Pattern). *Source*: research-edge-cases.md §5 Issue 1. *Rejected*: including a `provider {}` block — violates constitution §2.1 and the official provider guidance.

**HTTP health probes with independent enable toggles**: Liveness and readiness probes default to enabled with paths `/health/live` and `/health/ready`. Both are independently toggleable via `enable_liveness_probe` and `enable_readiness_probe` booleans. *Rationale*: Separate probe endpoints are the Kubernetes best practice — liveness must never check external dependencies (triggers restart storms), readiness may (research-k8s-best-practices.md §4). Toggles allow consumers to disable probes during initial deployment or when a legacy image has no health endpoints. *Source*: research-k8s-best-practices.md §4 Key best practices table. *Rejected*: single toggle for both probes — loses the ability to test readiness independently; always-on probes — blocks consumers with legacy images.

**Provider version pinned at `>= 3.2.1`**: *Rationale*: Provider 2.36 introduced `data_wo`; 2.38.0 fixed the toleration perpetual diff (research-edge-cases.md §5 Issue 6); 3.2.1 fixed `Missing Resource Identity After Create` when using `data_wo` (research-edge-cases.md §2 Known bug). The 2.x vs 3.x line is relevant because KUBE_CONFIG_PATH env var behavior changed in 3.0.0 (research-edge-cases.md §5 Issue 8). Using `>= 3.2.1` covers all known issues. *Source*: research-edge-cases.md §5; provider CHANGELOG. *Rejected*: `>= 2.36` — exposes the `data_wo` bug on creates; `~>` constraint — violates constitution §4.1.

### Resource Inventory

| Resource Type | Logical Name | Conditional | Depends On | Key Configuration | Schema Notes |
|---|---|---|---|---|---|
| `kubernetes_secret_v1` | `registry` | always | -- | `type = "kubernetes.io/dockerconfigjson"`, `data_wo` with `jsonencode()` + `base64encode()` payload, `data_wo_revision = var.registry_secret_revision`, `lifecycle { prevent_destroy = true, ignore_changes = [metadata[0].resource_version] }` | `metadata` is TypeList Min:1 Max:1 — access as `.metadata.0.name`; `data_wo` is write-only — never in state or assertions; `type` is ForceNew |
| `kubernetes_deployment_v1` | `this` | always | `kubernetes_secret_v1.registry` | `spec.replicas = tostring(var.replicas)`, `spec.selector.match_labels` = `local.pod_selector_labels` (ForceNew), pod security context (`run_as_non_root`, `run_as_user = "1000"`, `fs_group = "2000"`), container security context (`allow_privilege_escalation = false`, `privileged = false`, `read_only_root_filesystem = true`, `capabilities { drop = ["ALL"] }`), `wait_for_rollout = false`, `lifecycle { ignore_changes = [spec[0].template[0].metadata[0].annotations] }` | `spec` is TypeList Max:1 — index as `.spec.0`; `replicas` is TypeString — assert as string `"3"`; `spec.selector` is TypeList block (not TypeMap); `spec.template.spec.container` is TypeList (unbounded) — index as `.container.0`; `port` is TypeList — index as `.port.0`; `resources` is TypeList Max:1 — use `one()` safe; `security_context` is TypeList Max:1 — use `one()` safe; `liveness_probe` is TypeList Max:1 — use `one()` safe; `readiness_probe` is TypeList Max:1 — use `one()` safe; `image_pull_secrets` is TypeList Computed — index as `.image_pull_secrets.0.name` (do NOT use `one()`) |
| `kubernetes_service_v1` | `this` | always | `kubernetes_deployment_v1.this` | `spec.type = var.service_type`, `spec.selector = local.pod_selector_labels` (TypeMap — flat inline map, NOT a block), `spec.port[0].port = 80`, `spec.port[0].target_port = tostring(var.container_port)` (TypeString) | `spec` is TypeList Max:1 — index as `.spec.0`; `spec.selector` is TypeMap (flat map attribute, NOT a nested block — write as `selector = { ... }`); `spec.port` is TypeList MinItems:1 — index as `.spec.0.port.0`; `target_port` is TypeString — pass as string; `status` is Read-Only TypeList — `.status.0.load_balancer.0.ingress.0.hostname` is plan-unknown |

---

## 3. Interface Contract

### Inputs

| Variable | Type | Required | Default | Validation | Sensitive | Description |
|---|---|---|---|---|---|---|
| `app_name` | `string` | Yes | -- | `length >= 1 && length <= 63 && can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.app_name))` | No | Application name. Used as the base for all resource names, pod-selector labels, and the `app.kubernetes.io/name` label. Must be a valid RFC 1123 DNS label. |
| `namespace` | `string` | Yes | -- | `can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.namespace))` | No | Target Kubernetes namespace. Must exist before apply. Must be a valid RFC 1123 DNS label (lowercase alphanumeric and hyphens, max 63 chars, start and end with alphanumeric). |
| `image` | `string` | Yes | -- | `length(var.image) > 0` | No | Full OCI image reference including registry and tag (e.g., `de.icr.io/san-clients/backend:latest`). Must not be empty. |
| `replicas` | `number` | Yes | -- | `var.replicas >= 1 && var.replicas <= 100` | No | Number of pod replicas to run. Must be between 1 and 100 inclusive. Passed to the provider as a string via `tostring()`. |
| `registry_server` | `string` | Yes | -- | `length(var.registry_server) > 0` | Yes | Hostname of the private container registry (e.g., `de.icr.io`). Used to construct the `.dockerconfigjson` auth payload. |
| `registry_username` | `string` | Yes | -- | `length(var.registry_username) > 0` | Yes | Username for registry authentication (e.g., `iamapikey` for IBM ICR). |
| `registry_password` | `string` | Yes | -- | `length(var.registry_password) > 0` | Yes | Password or API key for registry authentication. Written via `data_wo` — never stored in state. |
| `registry_secret_revision` | `number` | No | `1` | `var.registry_secret_revision >= 1` | No | Revision counter for the registry pull secret. Increment this value to trigger a credential rotation (replaces `data_wo` payload in-place). |
| `container_port` | `number` | No | `8080` | `var.container_port >= 1 && var.container_port <= 65535` | No | Container port the application listens on. Used for the pod port declaration and health probe HTTP GET target. |
| `service_type` | `string` | No | `"ClusterIP"` | `contains(["ClusterIP", "NodePort", "LoadBalancer"], var.service_type)` | No | Kubernetes service type. Defaults to `ClusterIP` (no external exposure). Use `LoadBalancer` only with appropriate cloud annotations. |
| `cpu_request` | `string` | No | `"250m"` | `can(regex("^[0-9]+(m\|[.][0-9]+)?$", var.cpu_request))` | No | CPU resource request per container pod. Kubernetes quantity string (e.g., `"250m"`, `"0.25"`). |
| `memory_request` | `string` | No | `"256Mi"` | `can(regex("^[0-9]+(Mi\|Gi\|M\|G\|Ki\|K\|Ti\|T)?$", var.memory_request))` | No | Memory resource request per container pod. Kubernetes quantity string (e.g., `"256Mi"`, `"512M"`). |
| `cpu_limit` | `string` | No | `"500m"` | `can(regex("^[0-9]+(m\|[.][0-9]+)?$", var.cpu_limit))` | No | CPU resource limit per container pod. Must be >= `cpu_request`. Kubernetes quantity string. |
| `memory_limit` | `string` | No | `"512Mi"` | `can(regex("^[0-9]+(Mi\|Gi\|M\|G\|Ki\|K\|Ti\|T)?$", var.memory_limit))` | No | Memory resource limit per container pod. Must be >= `memory_request`. Kubernetes quantity string. |
| `liveness_path` | `string` | No | `"/health/live"` | `can(regex("^/", var.liveness_path))` | No | HTTP GET path for the liveness probe. Must start with `/`. Liveness checks MUST NOT call external dependencies. |
| `readiness_path` | `string` | No | `"/health/ready"` | `can(regex("^/", var.readiness_path))` | No | HTTP GET path for the readiness probe. Must start with `/`. May check upstream dependency health. |
| `enable_liveness_probe` | `bool` | No | `true` | -- | No | Enable or disable the container liveness probe. When `false`, the liveness probe block is omitted entirely. |
| `enable_readiness_probe` | `bool` | No | `true` | -- | No | Enable or disable the container readiness probe. When `false`, the readiness probe block is omitted entirely. |

### Outputs

| Output | Type | Conditional On | Description |
|---|---|---|---|
| `deployment_name` | `string` | always | Name of the `kubernetes_deployment_v1` resource. Used by CI/CD pipelines for `kubectl rollout status` commands. |
| `service_name` | `string` | always | Name of the `kubernetes_service_v1` resource. Used by Ingress resources and other services that reference this workload. |
| `service_cluster_ip` | `string` | always | ClusterIP address assigned to the service. Empty string for headless services. Value is plan-unknown until apply. |
| `secret_name` | `string` | always | Name of the `kubernetes_secret_v1` pull-secret resource. Allows consumers to reference the pull secret in additional deployments in the same namespace. |

---

## 4. Security Controls

| Control | Enforcement | Configurable? | Reference |
|---|---|---|---|
| Credentials kept out of state (data protection) | Registry credentials written exclusively via `data_wo` (write-only attribute, provider >= 2.36). The `.dockerconfigjson` payload is never stored in the Terraform state file. `registry_password` and `registry_username` and `registry_server` are `sensitive = true`. | No — hardcoded to use `data_wo`. Using `data` instead would defeat the protection and is architecturally excluded. | CIS Kubernetes Benchmark v1.8.0 §5.4.1 "Prefer using secrets as files over secrets as environment variables"; NSA/CISA Kubernetes Hardening Guide §Sensitive information in container environments |
| Non-root pod execution (pod security context) | `spec.template.spec.security_context.run_as_non_root = true`, `run_as_user = "1000"`, `fs_group = "2000"`. Hardcoded at pod level — applies to all containers in the pod. | No — hardcoded. Running as root is a critical security risk in shared clusters; configuring this per-consumer defeats the security guarantee. | CIS Kubernetes Benchmark v1.8.0 §5.2.6 "Do not admit root containers"; AWS EKS Best Practices Guide — Pod Security §Non-root containers |
| Drop all Linux capabilities (container security context) | `spec.template.spec.container.security_context.capabilities.drop = ["ALL"]`. Removes every Linux capability from the container. `add` list is empty. | No — hardcoded. Any capability add is a container escape surface; the module's scope (HTTP backend on port >= 1024) requires zero capabilities. | CIS Kubernetes Benchmark v1.8.0 §5.2.7 "Do not admit containers with added capabilities"; NSA/CISA Kubernetes Hardening Guide §Least privilege |
| No privilege escalation (container security context) | `allow_privilege_escalation = false` and `privileged = false` hardcoded in container security context. | No — hardcoded. Privilege escalation is the primary path from container compromise to node compromise in Kubernetes. | CIS Kubernetes Benchmark v1.8.0 §5.2.5 "Do not admit containers that allow privilege escalation"; AWS Well-Architected Framework — Security Pillar SEC07 |
| Read-only root filesystem (container security context) | `read_only_root_filesystem = true` hardcoded in container security context. Applications that require writable paths must mount explicit `emptyDir` volumes. | No — hardcoded. A writable root filesystem allows malware to persist after container restart; read-only rootfs is the NSA/CISA hardening baseline. | CIS Kubernetes Benchmark v1.8.0 §5.2.4 "Do not admit containers with a writable root file system"; NSA/CISA Kubernetes Hardening Guide §Immutable container file systems |
| Restricted external exposure (public access) | Service type defaults to `"ClusterIP"`. No external IP or load balancer is provisioned unless the consumer explicitly sets `service_type = "LoadBalancer"` or `"NodePort"`. | Yes — `service_type` variable, default `"ClusterIP"` (secure). Consumer must opt out of the private-by-default stance. | CIS Kubernetes Benchmark v1.8.0 §5.4.2 "Ensure that the cluster is not accessible from the public internet unless required"; AWS EKS Best Practices Guide — Network Security §Limit exposure |
| Resource limits enforced (denial-of-service prevention) | Both `resources.requests` (CPU, memory) and `resources.limits` (CPU, memory) are set on every container. Defaults prevent unbounded resource consumption that could evict neighbouring pods. | Yes — four variables (`cpu_request`, `memory_request`, `cpu_limit`, `memory_limit`) with safe non-zero defaults. | CIS Kubernetes Benchmark v1.8.0 §5.2.1 "Ensure that resource request/limits are set"; AWS EKS Best Practices Guide — Resource Management §Set resource requests and limits |
| Kubernetes labels for operational governance (tagging) | All three resources carry `local.common_labels` including `app.kubernetes.io/name = var.app_name` and `app.kubernetes.io/managed-by = "terraform"`. Pod selector uses stable `local.pod_selector_labels`. | Yes — labels are extended via the app name; `app.kubernetes.io/managed-by` is hardcoded to `"terraform"`. | Constitution §3.3 Tagging; Kubernetes upstream label convention https://kubernetes.io/docs/concepts/overview/working-with-objects/common-labels/ |
| Pull-secret deletion prevention (availability) | `lifecycle { prevent_destroy = true }` on `kubernetes_secret_v1.registry` prevents accidental teardown. Deletion would cause `ImagePullBackOff` for all pods in the namespace. | No — hardcoded. An accidentally deleted pull secret causes immediate workload failure; operator must explicitly `terraform state rm` to override. | AWS Well-Architected Framework — Reliability Pillar REL06 "Deploy changes with automation"; NSA/CISA Kubernetes Hardening Guide §Availability |

---

## 5. Test Scenarios

### Test Strategy

- **Module source**: Tests run against the **root module directly** — do NOT use `module {}` blocks in `run` blocks. Assert on `kubernetes_deployment_v1.this.attribute`, not `module.app.kubernetes_deployment_v1.this.attribute`.
- **Unit tests**: Use `mock_provider "kubernetes" {}` blocks with `command = plan`. No `mock_data` blocks are needed — this module has no `data` sources. Fast and deterministic; run during every CI build. File: `tests/unit_basic.tftest.hcl`, `tests/unit_complete.tftest.hcl`, `tests/unit_edge_cases.tftest.hcl`, `tests/unit_validation.tftest.hcl`.
- **Acceptance tests**: Use a real `kubernetes` provider with `command = plan`. Validates plan output against a real cluster API without creating resources. Requires a reachable cluster and credentials. File: `tests/acceptance.tftest.hcl`.
- **Integration tests**: Use a real `kubernetes` provider with `command = apply`. Creates and destroys real resources in a sandbox cluster namespace. Requires credentials. File: `tests/integration.tftest.hcl`.
- **Plan-time limitations (unit tests)**: `command = plan` with `mock_provider` means all provider-computed attributes are unknown at plan time. This includes: resource `id` fields, `metadata[0].resource_version`, `metadata[0].uid`, `status.*` (ClusterIP, LB hostname), and cross-resource references such as `kubernetes_secret_v1.registry.metadata[0].name` when referenced by the deployment's `image_pull_secrets`. Mark these with `[plan-unknown]`. The mock provider also cannot evaluate `data_wo` — assert secret existence, not payload content.

### Unit Tests

#### Scenario: Secure Defaults (basic)

**Purpose**: Verify the module plans successfully with only required inputs, and that all security controls are active by default.
**Command**: `plan` (mock providers)

**Inputs**:
```hcl
app_name          = "backend"
namespace         = "app-production"
image             = "de.icr.io/san-clients/backend:latest"
replicas          = 3
registry_server   = "de.icr.io"
registry_username = "iamapikey"
registry_password = "test-api-key"
```

**Assertions**:
- Deployment is planned — `kubernetes_deployment_v1.this.metadata.0.name == "backend"`
- Deployment namespace is set — `kubernetes_deployment_v1.this.metadata.0.namespace == "app-production"`
- Deployment label `app.kubernetes.io/name` is set — `kubernetes_deployment_v1.this.metadata.0.labels["app.kubernetes.io/name"] == "backend"`
- Deployment label `managed-by` is terraform — `kubernetes_deployment_v1.this.metadata.0.labels["app.kubernetes.io/managed-by"] == "terraform"`
- Replica count is coerced to string — `kubernetes_deployment_v1.this.spec.0.replicas == "3"`
- Pod selector label is stable — `kubernetes_deployment_v1.this.spec.0.selector.0.match_labels["app.kubernetes.io/name"] == "backend"`
- Pod template carries matching label — `kubernetes_deployment_v1.this.spec.0.template.0.metadata.0.labels["app.kubernetes.io/name"] == "backend"`
- Container image is set — `kubernetes_deployment_v1.this.spec.0.template.0.spec.0.container.0.image == "de.icr.io/san-clients/backend:latest"`
- Container port defaults to 8080 — `kubernetes_deployment_v1.this.spec.0.template.0.spec.0.container.0.port.0.container_port == 8080`
- CPU request default is set — `kubernetes_deployment_v1.this.spec.0.template.0.spec.0.container.0.resources.0.requests["cpu"] == "250m"`
- Memory request default is set — `kubernetes_deployment_v1.this.spec.0.template.0.spec.0.container.0.resources.0.requests["memory"] == "256Mi"`
- CPU limit default is set — `kubernetes_deployment_v1.this.spec.0.template.0.spec.0.container.0.resources.0.limits["cpu"] == "500m"`
- Memory limit default is set — `kubernetes_deployment_v1.this.spec.0.template.0.spec.0.container.0.resources.0.limits["memory"] == "512Mi"`
- Pod security context non-root enforced — `kubernetes_deployment_v1.this.spec.0.template.0.spec.0.security_context.0.run_as_non_root == true`
- Pod security context run-as-user — `kubernetes_deployment_v1.this.spec.0.template.0.spec.0.security_context.0.run_as_user == "1000"`
- Pod security context fs-group — `kubernetes_deployment_v1.this.spec.0.template.0.spec.0.security_context.0.fs_group == "2000"`
- Container no privilege escalation — `kubernetes_deployment_v1.this.spec.0.template.0.spec.0.container.0.security_context.0.allow_privilege_escalation == false`
- Container not privileged — `kubernetes_deployment_v1.this.spec.0.template.0.spec.0.container.0.security_context.0.privileged == false`
- Container read-only root filesystem — `kubernetes_deployment_v1.this.spec.0.template.0.spec.0.container.0.security_context.0.read_only_root_filesystem == true`
- Container drops ALL capabilities — `kubernetes_deployment_v1.this.spec.0.template.0.spec.0.container.0.security_context.0.capabilities.0.drop` contains `"ALL"`
- Liveness probe path defaults — `kubernetes_deployment_v1.this.spec.0.template.0.spec.0.container.0.liveness_probe.0.http_get.0.path == "/health/live"`
- Readiness probe path defaults — `kubernetes_deployment_v1.this.spec.0.template.0.spec.0.container.0.readiness_probe.0.http_get.0.path == "/health/ready"`
- Image pull secret reference is present — `kubernetes_deployment_v1.this.spec.0.template.0.spec.0.image_pull_secrets.0.name` `[plan-unknown]`
- Service is planned — `kubernetes_service_v1.this.metadata.0.name == "backend"`
- Service type defaults to ClusterIP — `kubernetes_service_v1.this.spec.0.type == "ClusterIP"`
- Service selector matches deployment labels — `kubernetes_service_v1.this.spec.0.selector["app.kubernetes.io/name"] == "backend"`
- Service target port matches container port — `kubernetes_service_v1.this.spec.0.port.0.target_port == "8080"`
- Secret is planned with correct type — `kubernetes_secret_v1.registry.type == "kubernetes.io/dockerconfigjson"`
- Secret namespace matches — `kubernetes_secret_v1.registry.metadata.0.namespace == "app-production"`
- Secret cluster IP — `kubernetes_service_v1.this.spec.0.cluster_ip` `[plan-unknown]`

#### Scenario: Full Features (complete)

**Purpose**: Verify all optional inputs are honoured, all features are active, and security controls are maintained with non-default values.
**Command**: `plan` (mock providers)

**Inputs**:
```hcl
app_name                  = "api-gateway"
namespace                 = "platform"
image                     = "de.icr.io/san-clients/api-gateway:v2.1.0"
replicas                  = 5
registry_server           = "de.icr.io"
registry_username         = "iamapikey"
registry_password         = "rotate-me"
registry_secret_revision  = 2
container_port            = 9090
service_type              = "NodePort"
cpu_request               = "100m"
memory_request            = "128Mi"
cpu_limit                 = "1000m"
memory_limit              = "1Gi"
liveness_path             = "/actuator/health/liveness"
readiness_path            = "/actuator/health/readiness"
enable_liveness_probe     = true
enable_readiness_probe    = true
```

**Assertions**:
- Custom replica count is coerced — `kubernetes_deployment_v1.this.spec.0.replicas == "5"`
- Custom container port is applied — `kubernetes_deployment_v1.this.spec.0.template.0.spec.0.container.0.port.0.container_port == 9090`
- Custom CPU request is applied — `kubernetes_deployment_v1.this.spec.0.template.0.spec.0.container.0.resources.0.requests["cpu"] == "100m"`
- Custom memory limit is applied — `kubernetes_deployment_v1.this.spec.0.template.0.spec.0.container.0.resources.0.limits["memory"] == "1Gi"`
- Service type is NodePort — `kubernetes_service_v1.this.spec.0.type == "NodePort"`
- Service target port matches custom container port — `kubernetes_service_v1.this.spec.0.port.0.target_port == "9090"`
- Custom liveness path — `kubernetes_deployment_v1.this.spec.0.template.0.spec.0.container.0.liveness_probe.0.http_get.0.path == "/actuator/health/liveness"`
- Custom readiness path — `kubernetes_deployment_v1.this.spec.0.template.0.spec.0.container.0.readiness_probe.0.http_get.0.path == "/actuator/health/readiness"`
- Liveness probe targets custom port — `kubernetes_deployment_v1.this.spec.0.template.0.spec.0.container.0.liveness_probe.0.http_get.0.port == "9090"`
- Readiness probe targets custom port — `kubernetes_deployment_v1.this.spec.0.template.0.spec.0.container.0.readiness_probe.0.http_get.0.port == "9090"`
- Security controls still active at full features — `kubernetes_deployment_v1.this.spec.0.template.0.spec.0.security_context.0.run_as_non_root == true`
- Capabilities still dropped — `kubernetes_deployment_v1.this.spec.0.template.0.spec.0.container.0.security_context.0.capabilities.0.drop` contains `"ALL"`
- Read-only rootfs still enforced — `kubernetes_deployment_v1.this.spec.0.template.0.spec.0.container.0.security_context.0.read_only_root_filesystem == true`
- Secret revision is applied — `kubernetes_secret_v1.registry.data_wo_revision == 2`
- Deployment image matches — `kubernetes_deployment_v1.this.spec.0.template.0.spec.0.container.0.image == "de.icr.io/san-clients/api-gateway:v2.1.0"`

#### Scenario: Feature Interactions (edge cases)

**Purpose**: Verify that probe toggles independently suppress or include their respective probe blocks, and that `service_type = "LoadBalancer"` does not change security context defaults.
**Command**: `plan` (mock providers)

**Sub-scenario A: Liveness probe disabled, readiness probe enabled**

**Inputs**:
```hcl
app_name               = "backend"
namespace              = "staging"
image                  = "de.icr.io/san-clients/backend:latest"
replicas               = 1
registry_server        = "de.icr.io"
registry_username      = "iamapikey"
registry_password      = "key"
enable_liveness_probe  = false
enable_readiness_probe = true
```
**Assertions**:
- Liveness probe block is absent — `length(kubernetes_deployment_v1.this.spec.0.template.0.spec.0.container.0.liveness_probe) == 0`
- Readiness probe block is present — `length(kubernetes_deployment_v1.this.spec.0.template.0.spec.0.container.0.readiness_probe) == 1`
- Readiness probe uses default path — `kubernetes_deployment_v1.this.spec.0.template.0.spec.0.container.0.readiness_probe.0.http_get.0.path == "/health/ready"`

**Sub-scenario B: Readiness probe disabled, liveness probe enabled**

**Inputs**:
```hcl
app_name               = "backend"
namespace              = "staging"
image                  = "de.icr.io/san-clients/backend:latest"
replicas               = 1
registry_server        = "de.icr.io"
registry_username      = "iamapikey"
registry_password      = "key"
enable_liveness_probe  = true
enable_readiness_probe = false
```
**Assertions**:
- Readiness probe block is absent — `length(kubernetes_deployment_v1.this.spec.0.template.0.spec.0.container.0.readiness_probe) == 0`
- Liveness probe block is present — `length(kubernetes_deployment_v1.this.spec.0.template.0.spec.0.container.0.liveness_probe) == 1`
- Liveness probe uses default path — `kubernetes_deployment_v1.this.spec.0.template.0.spec.0.container.0.liveness_probe.0.http_get.0.path == "/health/live"`

**Sub-scenario C: Both probes disabled**

**Inputs**:
```hcl
app_name               = "backend"
namespace              = "staging"
image                  = "de.icr.io/san-clients/backend:latest"
replicas               = 1
registry_server        = "de.icr.io"
registry_username      = "iamapikey"
registry_password      = "key"
enable_liveness_probe  = false
enable_readiness_probe = false
```
**Assertions**:
- Liveness probe block is absent — `length(kubernetes_deployment_v1.this.spec.0.template.0.spec.0.container.0.liveness_probe) == 0`
- Readiness probe block is absent — `length(kubernetes_deployment_v1.this.spec.0.template.0.spec.0.container.0.readiness_probe) == 0`
- Security context is unaffected — `kubernetes_deployment_v1.this.spec.0.template.0.spec.0.security_context.0.run_as_non_root == true`

**Sub-scenario D: LoadBalancer service type does not weaken security context**

**Inputs**:
```hcl
app_name          = "backend"
namespace         = "staging"
image             = "de.icr.io/san-clients/backend:latest"
replicas          = 2
registry_server   = "de.icr.io"
registry_username = "iamapikey"
registry_password = "key"
service_type      = "LoadBalancer"
```
**Assertions**:
- Service type is LoadBalancer — `kubernetes_service_v1.this.spec.0.type == "LoadBalancer"`
- Pod non-root enforcement unchanged — `kubernetes_deployment_v1.this.spec.0.template.0.spec.0.security_context.0.run_as_non_root == true`
- Capabilities still dropped — `kubernetes_deployment_v1.this.spec.0.template.0.spec.0.container.0.security_context.0.capabilities.0.drop` contains `"ALL"`
- Privilege escalation still blocked — `kubernetes_deployment_v1.this.spec.0.template.0.spec.0.container.0.security_context.0.allow_privilege_escalation == false`

**Sub-scenario E: Minimum viable replica count (1)**

**Inputs**:
```hcl
app_name          = "backend"
namespace          = "test"
image             = "de.icr.io/san-clients/backend:latest"
replicas          = 1
registry_server   = "de.icr.io"
registry_username = "iamapikey"
registry_password = "key"
```
**Assertions**:
- Replica count is 1 as string — `kubernetes_deployment_v1.this.spec.0.replicas == "1"`
- Service selector label matches app name — `kubernetes_service_v1.this.spec.0.selector["app.kubernetes.io/name"] == "backend"`

#### Scenario: Validation Boundaries (accept)

**Purpose**: Verify that validation rules accept values exactly at their valid boundaries.
**Command**: `plan` (mock providers)

**Boundary-pass cases** (each is a separate `run` block asserting the deployment is planned):

- `replicas = 1`: minimum valid replica count; deployment plans successfully with `spec.0.replicas == "1"`
- `replicas = 100`: maximum valid replica count; deployment plans successfully with `spec.0.replicas == "100"`
- `namespace = "a"`: single-character namespace passes RFC 1123 — regex `^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$` allows single alphanumeric; secret namespace set to `"a"`
- `namespace = "my-app-namespace-that-is-exactly-sixty-three-characters-long1"`: 63-character namespace passes max-length boundary; metadata namespace is set
- `app_name = "x"`: single-character app name passes minimum length; deployment name is `"x"`
- `container_port = 1`: minimum valid port (1); service target port is `"1"`
- `container_port = 65535`: maximum valid port (65535); service target port is `"65535"`
- `registry_secret_revision = 1`: minimum valid revision; `kubernetes_secret_v1.registry.data_wo_revision == 1`
- `liveness_path = "/"`: single-slash path passes `^/` regex; liveness probe path is `"/"`
- `readiness_path = "/health"`: standard path passes; readiness probe path is `"/health"`

#### Scenario: Validation Errors (reject)

**Purpose**: Verify input validation rejects invalid values with clear error messages.
**Command**: `plan` (mock providers) using `expect_failures`

**Expect-error cases** (each is a separate `run` block with `expect_failures = [var.<name>]`):

- `replicas = 0`: rejected — "Replica count must be between 1 and 100"
- `replicas = 101`: rejected — "Replica count must be between 1 and 100"
- `namespace = "MyNamespace"`: rejected — "Namespace must be a valid RFC 1123 DNS label" (uppercase letter)
- `namespace = "-invalid"`: rejected — "Namespace must be a valid RFC 1123 DNS label" (leading hyphen)
- `namespace = "invalid-"`: rejected — "Namespace must be a valid RFC 1123 DNS label" (trailing hyphen)
- `namespace = ""`: rejected — "Namespace must be a valid RFC 1123 DNS label" (empty string)
- `image = ""`: rejected — "Image must not be empty"
- `app_name = "UPPER"`: rejected — "must be a valid RFC 1123 DNS label" (uppercase)
- `app_name = "-starts-with-hyphen"`: rejected — "must be a valid RFC 1123 DNS label"
- `service_type = "ExternalName"`: rejected — `contains(["ClusterIP", "NodePort", "LoadBalancer"], ...)` — "Service type must be one of: ClusterIP, NodePort, LoadBalancer"
- `container_port = 0`: rejected — "must be between 1 and 65535"
- `container_port = 65536`: rejected — "must be between 1 and 65535"
- `registry_secret_revision = 0`: rejected — "must be >= 1"
- `registry_password = ""`: rejected — "must not be empty"
- `liveness_path = "no-leading-slash"`: rejected — "must start with /"
- `readiness_path = "health/ready"`: rejected — "must start with /"

### Acceptance Tests

#### Scenario: Plan Verification

**Purpose**: Verify plan output against a real Kubernetes cluster API — resolves cross-resource references and provider-computed attributes that are `[plan-unknown]` in unit tests.
**Command**: `plan` (real provider — requires cluster credentials)

**Inputs**:
```hcl
app_name          = "backend-acceptance"
namespace         = "acceptance-test"
image             = "de.icr.io/san-clients/backend:latest"
replicas          = 1
registry_server   = "de.icr.io"
registry_username = "iamapikey"
registry_password = var.icr_api_key   # supplied via .tfvars
```

**Assertions**:
- Pull secret name is deterministic — `kubernetes_secret_v1.registry.metadata.0.name == "backend-acceptance-registry-secret"` (or the module's naming pattern)
- Image pull secret reference resolves — `kubernetes_deployment_v1.this.spec.0.template.0.spec.0.image_pull_secrets.0.name == kubernetes_secret_v1.registry.metadata.0.name`
- Service ClusterIP is assigned (real API resolves this) — `kubernetes_service_v1.this.spec.0.cluster_ip != ""`
- Deployment UID is assigned — `kubernetes_deployment_v1.this.metadata.0.uid != ""`

### Integration Tests

#### Scenario: End-to-End

**Purpose**: Verify all three resources are created and functional; pods reach `Running` state and the service is reachable from within the cluster.
**Command**: `apply` (real provider — requires cluster credentials and sandbox namespace pre-created)

**Inputs**:
```hcl
app_name          = "backend-integration"
namespace         = "integration-test"
image             = "de.icr.io/san-clients/backend:latest"
replicas          = 1
registry_server   = "de.icr.io"
registry_username = "iamapikey"
registry_password = var.icr_api_key
```

**Assertions** (post-apply):
- Secret exists with correct type — `kubernetes_secret_v1.registry.type == "kubernetes.io/dockerconfigjson"`
- Secret name is set — `kubernetes_secret_v1.registry.metadata.0.name != ""`
- Deployment replica count matches — `kubernetes_deployment_v1.this.spec.0.replicas == "1"`
- Deployment is in the correct namespace — `kubernetes_deployment_v1.this.metadata.0.namespace == "integration-test"`
- Service ClusterIP is assigned by the API — `kubernetes_service_v1.this.spec.0.cluster_ip != ""`
- Service name output matches — `output.service_name == kubernetes_service_v1.this.metadata.0.name`
- Deployment name output matches — `output.deployment_name == kubernetes_deployment_v1.this.metadata.0.name`
- Secret name output matches — `output.secret_name == kubernetes_secret_v1.registry.metadata.0.name`

---

## 6. Implementation Checklist

- [ ] **A: Scaffold** — Create `versions.tf` (provider `hashicorp/kubernetes >= 3.2.1`, Terraform `>= 1.14`), `variables.tf` (all 18 inputs with types, descriptions, validation blocks, sensitive flags), `locals.tf` (`pod_selector_labels` and `common_labels` maps), `outputs.tf` (four outputs: `deployment_name`, `service_name`, `service_cluster_ip`, `secret_name`). No resource code yet.

- [ ] **B: Registry secret** — Implement `kubernetes_secret_v1.registry` in `main.tf` with `type = "kubernetes.io/dockerconfigjson"`, `data_wo` + `data_wo_revision`, `jsonencode()` + `base64encode()` payload, and `lifecycle { prevent_destroy = true, ignore_changes = [metadata[0].resource_version] }`. Verify `terraform validate` passes.

- [ ] **C: Deployment** — Implement `kubernetes_deployment_v1.this` in `main.tf`: pod selector using `local.pod_selector_labels`, `replicas = tostring(var.replicas)`, full pod and container security contexts (non-root, drop ALL, no privilege escalation, read-only rootfs), resource requests/limits, `image_pull_secrets` reference, and conditional `liveness_probe` / `readiness_probe` dynamic blocks. Wire `wait_for_rollout = false` and `lifecycle { ignore_changes = [spec[0].template[0].metadata[0].annotations] }`.

- [ ] **D: Service** — Implement `kubernetes_service_v1.this` in `main.tf`: `spec.type = var.service_type`, `spec.selector = local.pod_selector_labels` (flat TypeMap, not a block), service port 80 → `tostring(var.container_port)` target port. Verify label coupling between deployment selector and service selector is identical.

- [ ] **E: Examples** — Create `examples/basic/` with minimal required inputs and an inline `provider "kubernetes" {}` block using `exec` (EKS pattern, `api_version = "client.authentication.k8s.io/v1"`). Create `examples/complete/` with all optional inputs set, `service_type = "LoadBalancer"`, custom probe paths, and comments explaining each group of settings.

- [ ] **F: Tests** — Write `tests/unit_basic.tftest.hcl` (secure defaults, mock provider), `tests/unit_complete.tftest.hcl` (full features, mock provider), `tests/unit_edge_cases.tftest.hcl` (five probe and service-type sub-scenarios, mock provider), `tests/unit_validation.tftest.hcl` (all boundary-pass and expect-failure cases, mock provider), `tests/acceptance.tftest.hcl` (plan with real provider, marked `# acceptance`), `tests/integration.tftest.hcl` (apply with real provider, marked `# integration`). Run `terraform test` against the unit files to confirm all pass.

- [ ] **G: Polish** — Run `terraform fmt -recursive`, `terraform validate`, `tflint`, `trivy config .` (zero Critical/High), generate `README.md` via `terraform-docs`, write `CHANGELOG.md` v0.1.0 entry. Confirm no variable names or resource names appear more than once across the codebase.

---

## 7. Open Questions

No unresolved questions remain from Phase 1 clarification.

> **Implementation note**: When consumers deploy into EKS, they MUST configure the `kubernetes` provider with the `exec` block using `api_version = "client.authentication.k8s.io/v1"` (not `v1beta1`, which was removed in Kubernetes 1.29 / EKS 1.32). This is documented in `examples/basic/` and `examples/complete/` provider blocks but is the consumer's responsibility per constitution §2.1 and the official provider same-module anti-pattern warning.
