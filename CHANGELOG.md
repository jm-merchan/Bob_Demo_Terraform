# Changelog

All notable changes to this module are documented in this file.
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-07-14

### Added

- Initial release of `terraform-kubernetes-app-deploy` module.
- `kubernetes_secret_v1` resource — creates a `kubernetes.io/dockerconfigjson` image pull secret
  using the write-only `data_wo` attribute (provider ≥ 3.2.1) so registry credentials never appear
  in Terraform state. Lifecycle `prevent_destroy = true` protects against accidental deletion.
- `kubernetes_deployment_v1` resource — deploys a replicated pod controller with:
  - Full pod-level security context: `run_as_non_root = true`, `run_as_user = "1000"`, `fs_group = "2000"`
  - Full container-level security context: `allow_privilege_escalation = false`, `privileged = false`,
    `read_only_root_filesystem = true`, `capabilities.drop = ["ALL"]`
  - Configurable resource requests and limits (CPU and memory)
  - Conditional liveness and readiness probes (independently toggleable)
  - `wait_for_rollout = false` to avoid apply timeouts in CI
- `kubernetes_service_v1` resource — exposes the Deployment via a configurable service type
  (default: `ClusterIP`; supports `NodePort` and `LoadBalancer`).
- 18 input variables with full validation rules and sensitive flags for registry credentials.
- 4 outputs: `deployment_name`, `service_name`, `service_cluster_ip`, `secret_name`.
- `examples/basic/` — minimal ClusterIP deployment using EKS exec-based authentication.
- `examples/complete/` — all optional inputs enabled, `service_type = "LoadBalancer"`, custom
  probe paths, wired for the `eks-infra-dev` cluster (eu-central-1).
- Unit test suite (33 test cases, `mock_provider`, `command = plan`) covering:
  - Secure defaults, full features, feature interactions (5 sub-scenarios),
    validation boundaries, and 16 validation error rejection cases.
- Acceptance and integration test stubs for real-cluster validation.
