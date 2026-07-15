# Deployment Report: 006-kubernetes-app Consumer

| Field           | Value                                                    |
| --------------- | -------------------------------------------------------- |
| Branch          | 006-kubernetes                                           |
| Date            | 2026-07-15                                               |
| Provider        | hashicorp/kubernetes ~> 3.2 · hashicorp/aws ~> 6.0      |
| Terraform       | 1.15.8 (HCP executor)                                    |
| HCP Workspace   | `k8s-app-demo-bob` (`ws-g5V4jbf1EyPrcy1P`)              |
| HCP Project     | Default Project (`prj-PmbVsprg8DoogHW7`)                 |
| Module version  | `app.terraform.io/jose-merchan/app-deploy/kubernetes` `~> 0.4` |

---

## Modules Composed

| Module       | Registry Source                                       | Version  | Status   |
| ------------ | ----------------------------------------------------- | -------- | -------- |
| `app_deploy` | `app.terraform.io/jose-merchan/app-deploy/kubernetes` | `~> 0.4` | ✅ PASS  |

**Summary**: 1 module composed. Single-module topology. One glue resource (`kubernetes_namespace_v1.app`) justified by constitution deviation — no Kubernetes namespace PMR module exists in the org. Module handles pull secret, deployment, and service internally.

---

## terraform validate

**Result**: ✅ CLEAN

`terraform validate` exits 0 with no errors or warnings. All module input/output type references resolve correctly.

---

## terraform fmt -check

**Result**: ✅ FORMATTED

All `.tf` files in `consumers/006-kubernetes-app/` pass `terraform fmt -check -recursive` with exit code 0.

---

## tflint

**Result**: ✅ CLEAN

`tflint --chdir=consumers/006-kubernetes-app` reports zero findings. No deprecated resource usage, no missing required attributes, no unused variables detected.

---

## trivy config

| Metric                       | Count |
| ---------------------------- | ----- |
| Total (consumer root module) | 0     |
| Defects                      | 0     |
| Accepted                     | 0     |

### Defects (block deployment)

*None. The consumer root module (`consumers/006-kubernetes-app`, terraform) returned 0 misconfigurations.*

> **Note on sensitive vars**: Trivy warns that `registry_password`, `registry_server`, and `registry_username` were not found in env/tfvars during static scan — this is expected. The variables are sensitive and are provided via HCP Terraform workspace variables at runtime. The scan correctly reports 0 misconfigurations despite the warning.

---

## Design Checklist Coverage (Items A–E)

| Item | Description | Status | Evidence |
| ---- | ----------- | ------ | -------- |
| **A** | Scaffold — 8-file consumer: `versions.tf`, `backend.tf`, `providers.tf`, `variables.tf`, `outputs.tf`, `locals.tf`, `data.tf`, `README.md` + `terraform.auto.tfvars.example` | ✅ PASS | All required files present in `consumers/006-kubernetes-app/`. |
| **B** | Core module — `module "app_deploy"` from private registry, all required inputs wired including NLB `service_annotations`, `service_type = "LoadBalancer"` override documented with `[SECURITY OVERRIDE]` comment | ✅ PASS | [`consumers/006-kubernetes-app/main.tf:25-73`](../../../consumers/006-kubernetes-app/main.tf) — correct source `app.terraform.io/jose-merchan/app-deploy/kubernetes`, version `~> 0.4`, all inputs wired. |
| **C** | Workspace — `k8s-app-demo-bob` in `Default Project`, VCS-driven (branch `006-kubernetes`, working-dir `consumers/006-kubernetes-app/`), 4 workspace variables set, remote state consumer of `eks-infra-vcs` | ✅ PASS | Workspace confirmed live: VCS-driven, `global-remote-state = false` with explicit consumer grant, `aws-dynamic-provider-credentials` varset attached. |
| **D** | Security — startup probe enabled (150s window), `read_only_root_filesystem = true`, `run_as_non_root = true`, `allowPrivilegeEscalation = false`, capabilities dropped, `registry_password` via `data_wo` (never in state), `prevent_destroy` on pull secret | ✅ PASS | All security controls confirmed in module `v0.4.0` source (`main.tf`) and consumer wiring. |
| **E** | Validate — `terraform validate` passes, all 6 outputs in remote state, `service_load_balancer_hostname` output resolves to live NLB FQDN, app verified reachable | ✅ PASS | State API confirmed 6 outputs. NLB hostname: `ac887b1cec35d45a584f3794ac044a86-0a6ba48580e6981d.elb.eu-central-1.amazonaws.com`. App deployed and verified by user. |

**All 5 checklist items (A–E) implemented and verified.**

---

## Quality Score

### Scoring Detail

#### D1 — Module Usage (weight: 25%)

- ✅ Single module sourced exclusively from private registry `app.terraform.io/jose-merchan/app-deploy/kubernetes`
- ✅ Pessimistic version constraint `~> 0.4` applied
- ✅ One glue resource (`kubernetes_namespace_v1.app`) with full constitution deviation comment — justified (no Kubernetes PMR module exists in org)
- ✅ Module source selection justified by `research-module-registry.md`
- ✅ `[CONSTITUTION DEVIATION]` comment includes 4 justification points + review trigger

**Score: 9.5/10**

#### D2 — Security & Compliance (weight: 30%)

- ✅ `read_only_root_filesystem = true` — filesystem write-protected; `/tmp` served by emptyDir volume
- ✅ `run_as_non_root = true`, `run_as_user = 1000`, `fs_group = 2000`
- ✅ `allow_privilege_escalation = false`, `privileged = false`, `capabilities drop ALL`
- ✅ Registry pull secret written via `data_wo` — credentials never stored in Terraform state
- ✅ `prevent_destroy = true` on `kubernetes_secret_v1.registry` — prevents accidental pull-secret deletion
- ✅ Dynamic AWS credentials via OIDC (`aws-dynamic-provider-credentials` varset) — no static keys
- ✅ Startup probe enabled — prevents CrashLoopBackOff on slow JVM startup (150s window)
- ✅ `[SECURITY OVERRIDE]` comment on `service_type = "LoadBalancer"` with justification and WAF/TLS guidance
- ⚠️ NLB endpoint is publicly accessible with no WAF, TLS termination, or CIDR restriction — intentional demo sandbox; documented in design §4 and `main.tf` comment

**Score: 9.0/10**

#### D3 — Code Quality (weight: 15%)

- ✅ `terraform fmt -check` exits 0
- ✅ File organisation matches constitution §2.1 exactly
- ✅ Inline comments on every security decision in `main.tf`
- ✅ `kubernetes_namespace_v1.app` uses `_v1` canonical provider form (deprecated alias avoided)
- ✅ `locals.tf` cleanly separates provider wire-up from module call
- ✅ No file exceeds 150 lines

**Score: 9.5/10**

#### D4 — Variables & Outputs (weight: 10%)

- ✅ All 12 variables declared with `type` and `description`
- ✅ Validation blocks on string variables (`app_name`, `namespace`, `image`, `environment`)
- ✅ All 6 outputs declared with `description`
- ✅ `terraform.auto.tfvars.example` documents all consumer variables
- ✅ Sensitive variables (`registry_server`, `registry_username`, `registry_password`) declared with `sensitive = true` in module

**Score: 9.5/10**

#### D5 — Wiring & Integration (weight: 10%)

- ✅ All remote state outputs (`cluster_endpoint`, `cluster_certificate_authority_data`, `cluster_name`, `aws_region`) wired via `data.tf` → `locals.tf` → `providers.tf`
- ✅ Namespace creation wired via `kubernetes_namespace_v1.app.metadata[0].name` → module `namespace` input (implicit `depends_on`)
- ✅ All probe paths wired to Spring Boot Actuator endpoints (`/actuator/health/liveness`, `/actuator/health/readiness`)
- ✅ `service_load_balancer_hostname` output surfaced from module → consumer outputs

**Score: 10.0/10**

#### D6 — Constitution Alignment (weight: 10%)

- ✅ `backend.tf` uses `cloud {}` block with correct org/project/workspace
- ✅ Module sourced exclusively from private registry
- ✅ `~>` pessimistic constraint used
- ✅ `[SECURITY OVERRIDE]` comment on LoadBalancer override with justification (constitution §8.2)
- ✅ `[CONSTITUTION DEVIATION]` comment with 4 justification points and review trigger (constitution §8.3)
- ✅ Dynamic credentials, no static keys
- ✅ `README.md` present with deployment instructions
- ✅ No `.tftest.hcl` files — consumers validate via sandbox deployment

**Score: 10.0/10**

### Summary Table

| #   | Dimension              | Score | Issues                              |
| --- | ---------------------- | ----- | ----------------------------------- |
| 1   | Module Usage           | 9.5   | 0 P0, 0 P1, 0 P2                    |
| 2   | Security & Compliance  | 9.0   | 0 P0, 0 P1, 1 P2 (public NLB)      |
| 3   | Code Quality           | 9.5   | 0 P0, 0 P1, 0 P2                    |
| 4   | Variables & Outputs    | 9.5   | 0 P0, 0 P1, 0 P2                    |
| 5   | Wiring & Integration   | 10.0  | 0 P0, 0 P1, 0 P2                    |
| 6   | Constitution Alignment | 10.0  | 0 P0, 0 P1, 0 P2                    |

**Overall Score**: `(9.5×0.25) + (9.0×0.30) + (9.5×0.15) + (9.5×0.10) + (10.0×0.10) + (10.0×0.10)`
= `2.375 + 2.70 + 1.425 + 0.95 + 1.00 + 1.00` = **9.45/10.0 — Excellent**

**Production Readiness**: ✅ Ready for sandbox (D2 Security = 9.0 ≥ 5.0; no P0 issues; WAF/TLS required before production promotion)

### Top Issues

| #   | Severity | Dimension             | File:Line                                   | Issue                                                                                       | Remediation                                                                             |
| --- | -------- | --------------------- | ------------------------------------------- | ------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| 1   | P2       | Security & Compliance | `consumers/006-kubernetes-app/main.tf:36-45` | `service_type = "LoadBalancer"` exposes NLB publicly with no WAF, TLS, or CIDR restriction | Add AWS WAF + ACM TLS termination before any production promotion. Documented in design §4 and `main.tf` `[SECURITY OVERRIDE]` comment. |

---

## Security Notes

### [SECURITY OVERRIDE] — Public LoadBalancer (NLB)

The Kubernetes service is of type `LoadBalancer` with an AWS NLB, making the app reachable from the public internet. This is an explicit, user-approved override of the module's secure default `ClusterIP`, documented in:

- [`consumers/006-kubernetes-app/main.tf:34-45`](../../../consumers/006-kubernetes-app/main.tf) — `[SECURITY OVERRIDE]` comment with WAF/TLS guidance
- [`specs/006-kubernetes-consumer/consumer-design.md §4`](../consumer-design.md#4-security-controls) — Security controls table, accepted risk row

**Mitigations in place:**
- `read_only_root_filesystem = true` — container filesystem hardened
- All capabilities dropped, `run_as_non_root = true`
- Registry credentials never written to Terraform state (`data_wo`)
- NLB is sandbox-only; WAF + TLS termination required before production

### Honoured Module Defaults

| Control                              | Value                              | Compliance Reference            |
| ------------------------------------ | ---------------------------------- | ------------------------------- |
| `read_only_root_filesystem`          | `true`                             | CIS Kubernetes §5.2.4           |
| `run_as_non_root` / `run_as_user`    | `true` / UID 1000                  | CIS Kubernetes §5.2.6           |
| `allow_privilege_escalation = false` | `false`                            | CIS Kubernetes §5.2.5           |
| `capabilities drop ALL`              | `["ALL"]`                          | CIS Kubernetes §5.2.7           |
| Registry secret via `data_wo`        | Never in Terraform state           | Well-Architected SEC03-BP02     |
| Startup probe (150s window)          | `enable_startup_probe = true`      | Kubernetes reliability best practice |

### Dynamic Credentials

AWS authentication uses short-lived STS via OIDC `AssumeRoleWithWebIdentity` from the global `aws-dynamic-provider-credentials` varset. No static IAM access keys in consumer code or provider configuration.

---

## Sandbox Deployment

| Field                   | Value                                                                                  |
| ----------------------- | -------------------------------------------------------------------------------------- |
| Workspace               | `k8s-app-demo-bob` (`ws-g5V4jbf1EyPrcy1P`)                                            |
| Delivery run (v0.3.0)   | `run-VX3roDfK6EFsaFZg` — **applied** (has-changes: true)                              |
| Convergence run (v0.4.0)| `run-sHLk3NMsQLbzmTeX` — **planned_and_finished** (has-changes: false)                |
| Run URL                 | `https://app.terraform.io/app/jose-merchan/workspaces/k8s-app-demo-bob/runs/run-VX3roDfK6EFsaFZg` |
| Triggered by            | VCS push (GitHub `jm-merchan/Bob_Demo_Terraform`, branch `006-kubernetes`)             |
| Terraform version       | 1.15.8 (executor)                                                                      |
| Apply Status            | ✅ APPLIED                                                                              |
| Driver                  | VCS (working-dir `consumers/006-kubernetes-app/`, trigger-prefix same)                 |

### Confirmed Outputs in State

All 6 design-specified outputs confirmed present in remote state:

| Output                          | Sensitive | Value                                                                                     |
| ------------------------------- | --------- | ----------------------------------------------------------------------------------------- |
| `deployment_name`               | No        | `backend`                                                                                 |
| `namespace`                     | No        | `bob-demo-app`                                                                            |
| `secret_name`                   | No        | `backend-registry-secret`                                                                 |
| `service_cluster_ip`            | No        | `172.20.214.189`                                                                          |
| `service_load_balancer_hostname`| No        | `ac887b1cec35d45a584f3794ac044a86-0a6ba48580e6981d.elb.eu-central-1.amazonaws.com`       |
| `service_name`                  | No        | `backend`                                                                                 |

### Application Verification

Application deployed and verified reachable by user at the NLB endpoint. Spring Boot Actuator health probes (`/actuator/health/liveness`, `/actuator/health/readiness`) passing. Pods in `Running` state in namespace `bob-demo-app` on EKS cluster `eks-infra-vcs`.

---

## Overall Status

**✅ PASS**

All validation gates satisfied:

- ✅ `terraform validate` — clean
- ✅ `terraform fmt -check` — clean
- ✅ `tflint` — 0 findings
- ✅ `trivy config` — 0 misconfigurations in consumer root module
- ✅ Design checklist — all 5 items (A–E) implemented and verified
- ✅ Sandbox deployment — applied, all 6 outputs in remote state
- ✅ Application verified reachable at NLB endpoint
- ✅ Quality score 9.45/10 ≥ required 7.0 threshold
- ✅ Security & Compliance score 9.0/10 ≥ required 5.0 (no "Not Production Ready" gate triggered)
- ✅ LoadBalancer override user-approved and documented

### Recommendations (non-blocking)

1. **Add WAF + TLS** — Before any production promotion, add AWS WAF v2 and ACM TLS certificate via an Ingress controller or NLB listener config.
2. **Restrict public access** — Add `service.beta.kubernetes.io/aws-load-balancer-security-groups` annotation to limit NLB inbound to known CIDR ranges.
3. **Add run tasks** — Configure Infracost or cost estimation as a post-plan run task on `k8s-app-demo-bob`.
4. **Image tag pinning** — Replace `:latest` tag with a specific digest or semver tag to guarantee deterministic deployments.
5. **Namespace module** — If a `kubernetes-namespace` PMR module is published to the org registry, replace the `kubernetes_namespace_v1.app` glue resource with it.
