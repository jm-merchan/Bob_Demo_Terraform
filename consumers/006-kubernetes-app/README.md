# 006-kubernetes-app — Backend App on EKS

## Overview

This deployment provisions the `backend` application workload into an existing Amazon EKS cluster managed by the `eks-infra-vcs` workspace. It uses the private registry module [`jose-merchan/app-deploy/kubernetes`](https://app.terraform.io/app/jose-merchan/registry/modules/private/jose-merchan/app-deploy/kubernetes) to create a dedicated Kubernetes namespace, a private-registry pull secret for IBM Container Registry (`de.icr.io`), a replicated pod controller (2 replicas), and a LoadBalancer service that exposes the application via a Classic ELB. Cluster credentials are read from the `eks-infra-vcs` remote state, keeping this deployment decoupled from the EKS provisioning lifecycle. No raw Kubernetes manifests are authored — the module encapsulates all workload resources.

Managed by: **HCP Terraform** — workspace `k8s-app-demo-bob` in project `Default Project`, org `jose-merchan`.

---

## Prerequisites

| Requirement | Detail |
|---|---|
| Terraform | `>= 1.14` (workspace executor pinned to `~> 1.15.0`) |
| HCP Terraform | Account in org `jose-merchan`; workspace `k8s-app-demo-bob` must exist in project `Default Project` (`prj-PmbVsprg8DoogHW7`) |
| Remote state | `eks-infra-vcs` workspace must have a successful apply with outputs `cluster_endpoint`, `cluster_certificate_authority_data`, `cluster_name`, `aws_region` available. `k8s-app-demo-bob` must be registered as a remote state consumer of `eks-infra-vcs` before the first plan. |
| Workspace variables | `registry_server`, `registry_username`, and `registry_password` (sensitive) must be set as `category=terraform` workspace variables in HCP Terraform UI. `infra_workspace` must be set to `"eks-infra-vcs"`. |
| AWS credentials | Dynamic provider credentials via OIDC — **no static IAM access keys needed**. The global varset `aws-dynamic-provider-credentials` injects `TFC_AWS_PROVIDER_AUTH` and `TFC_AWS_RUN_ROLE_ARN` automatically. |
| AWS CLI | AWS CLI must be installed and on `PATH` in the execution environment (HCP Terraform agent or local shell). Required for `aws eks get-token` in the Kubernetes provider `exec` block. |

---

## Quick Start

```bash
# 1. Authenticate to HCP Terraform (required once per machine)
terraform login app.terraform.io

# 2. Initialise — downloads the app-deploy module from app.terraform.io/jose-merchan
terraform init

# 3. Apply (runs remotely in HCP Terraform; auto_apply = true)
terraform apply
```

> **Note**: All runs execute remotely in HCP Terraform. Local AWS credentials are not required. Ensure `registry_password`, `registry_username`, `registry_server`, and `infra_workspace` are set as workspace variables before triggering a plan.

---

## Variables

All 12 consumer variables. Declared in [`variables.tf`](variables.tf).

| Variable | Type | Default | Required | Description |
|---|---|---|:---:|---|
| `aws_region` | `string` | `"eu-central-1"` | No | AWS region. Must match the region of the `eks-infra-vcs` workspace. Used in the `provider "aws"` block (cannot reference data sources in provider config). |
| `project_name` | `string` | `"k8s-app-demo"` | No | Project name applied to `default_tags` `Project` key and workspace labelling. |
| `environment` | `string` | `"sandbox"` | No | Deployment environment identifier applied to all resource tags. One of: `dev`, `staging`, `prod`, `sandbox`. |
| `owner` | `string` | `"platform-team"` | No | Owner value for `default_tags` `Owner` key; used for cost allocation reporting. |
| `infra_workspace` | `string` | `"eks-infra-vcs"` | No | Name of the HCP Terraform workspace that exposes EKS cluster outputs via remote state. Follows the `eks-vault-vcs` org pattern. Set as a workspace variable. |
| `namespace` | `string` | `"bob-demo-app"` | No | Kubernetes namespace to create and deploy the application into. Must be a valid RFC 1123 DNS label. |
| `app_name` | `string` | `"backend"` | No | Application name. Used as base for all Kubernetes resource names and pod-selector labels. RFC 1123 DNS label (1–63 chars). |
| `image` | `string` | `"de.icr.io/san-clients/backend:latest"` | No | Full OCI image reference including registry and tag. |
| `replicas` | `number` | `2` | No | Number of pod replicas. Must be 1–100. |
| `registry_server` | `string` | — | **Yes** | Hostname of the private container registry (e.g., `de.icr.io`). Set as workspace variable. |
| `registry_username` | `string` | — | **Yes** | Registry authentication username (e.g., `iamapikey` for IBM ICR). Set as workspace variable. |
| `registry_password` | `string` | — | **Yes** | Registry authentication password or API key. Written via module `data_wo` — never stored in state. Set as **sensitive** workspace variable. |

Copy [`terraform.auto.tfvars.example`](terraform.auto.tfvars.example) to `terraform.auto.tfvars` and adjust values for local runs. **Never commit registry credentials.**

---

## Outputs

All 5 consumer outputs. Declared in [`outputs.tf`](outputs.tf).

| Output | Type | Description |
|---|---|---|
| `namespace` | `string` | Name of the created Kubernetes namespace. |
| `deployment_name` | `string` | Name of the `kubernetes_deployment_v1` resource. Used by CI/CD pipelines for `kubectl rollout status`. |
| `service_name` | `string` | Name of the `kubernetes_service_v1` LoadBalancer service. |
| `service_cluster_ip` | `string` | ClusterIP address assigned to the service. Value is plan-unknown until apply. |
| `secret_name` | `string` | Name of the registry pull secret. Allows reference in additional deployments in the same namespace. |

---

## Security Notes

### [SECURITY OVERRIDE] — LoadBalancer Service Type

The module's secure default for `service_type` is `ClusterIP` — no external exposure. This consumer overrides that default with `service_type = "LoadBalancer"`, which provisions a Classic ELB with a **public endpoint and no WAF, TLS termination, or security group ingress restrictions**. This override is justified by an explicit sandbox demo requirement: operators need to reach the application from outside the VPC without a private network connection or Ingress controller.

**Operators MUST replace this with `ClusterIP` + `Ingress` + AWS Load Balancer Controller for production workloads.** Risk rating: **High (P1)** — fix before promotion to staging or production. The override is documented in [`consumer-design.md`](../../specs/006-kubernetes-consumer/consumer-design.md) Section 4 (Security Controls, Public access row) and annotated with an inline comment in [`main.tf`](main.tf).

### [CONSTITUTION DEVIATION] — `kubernetes_namespace_v1` Glue Resource

The Terraform constitution (§1.1) enumerates permitted glue resources as: `random_id`, `random_string`, `null_resource`, `terraform_data`, `time_sleep`. The `kubernetes_namespace_v1` resource used in [`main.tf`](main.tf) is not in that list and constitutes a tracked deviation.

**Justification**: Zero Kubernetes-provider modules exist in the `jose-merchan` PMR (16 modules confirmed, all AWS/Google provider). The `app-deploy` module's scope boundary explicitly excludes namespace creation. Pre-creating the namespace out-of-band (`kubectl`) violates IaC lifecycle management. A Kubernetes namespace is a thin metadata boundary with no compute, storage, or network resources — the spirit of the glue resource exception applies. Risk rating: **Low (P3)**.

**Review trigger**: If a `kubernetes-namespace` module is published to the `jose-merchan` PMR, this deviation MUST be resolved by replacing the raw resource with the PMR module call.

---

## Workspace Variables

The following variables must be set in the **HCP Terraform workspace UI** (`k8s-app-demo-bob`) before triggering a plan. Do NOT store real credentials in `.tfvars` files committed to version control.

| Variable | Category | Sensitive | Example Value | Description |
|---|---|:---:|---|---|
| `registry_server` | `terraform` | No | `de.icr.io` | Hostname of the IBM Container Registry. |
| `registry_username` | `terraform` | No | `iamapikey` | Registry authentication username for IBM ICR. |
| `registry_password` | `terraform` | **Yes** | `<your-icr-api-key>` | Registry API key. Written via `data_wo` — never stored in state. |
| `infra_workspace` | `terraform` | No | `eks-infra-vcs` | Name of the upstream HCP Terraform workspace that provides EKS cluster remote state. |

---

## HCP Terraform Workspace

| Setting | Value |
|---|---|
| Organization | `jose-merchan` |
| Project | `Default Project` (`prj-PmbVsprg8DoogHW7`) |
| Workspace | `k8s-app-demo-bob` (`ws-g5V4jbf1EyPrcy1P`) |
| Execution mode | `remote` |
| Terraform version | `~> 1.15.0` |
| Auto-apply | `true` |
| VCS connection | None (API-driven workflow) |
| Variable sets | `aws-dynamic-provider-credentials` (global, auto-applied) |
| Remote state dependency | `eks-infra-vcs` (`ws-fynCV5VvhkpRF7s3`) — registered as remote state consumer |

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.14 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | ~> 3.2 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | 3.2.1 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_app_deploy"></a> [app\_deploy](#module\_app\_deploy) | app.terraform.io/jose-merchan/app-deploy/kubernetes | ~> 0.1 |

## Resources

| Name | Type |
| ---- | ---- |
| [kubernetes_namespace_v1.app](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace_v1) | resource |
| [terraform_remote_state.eks_infra](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/data-sources/remote_state) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_app_name"></a> [app\_name](#input\_app\_name) | Application name. Used as base for all Kubernetes resource names and pod-selector labels. RFC 1123 DNS label. | `string` | `"backend"` | no |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS region to deploy into. Must match the region of the eks-infra-vcs workspace. Used in provider block (cannot reference data sources in provider config). | `string` | `"eu-central-1"` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Deployment environment identifier applied to all resource tags. | `string` | `"sandbox"` | no |
| <a name="input_image"></a> [image](#input\_image) | Full OCI image reference including registry and tag. | `string` | `"de.icr.io/san-clients/backend:latest"` | no |
| <a name="input_infra_workspace"></a> [infra\_workspace](#input\_infra\_workspace) | Name of the HCP Terraform workspace that exposes EKS cluster outputs via remote state. Follows the eks-vault-vcs org pattern. | `string` | `"eks-infra-vcs"` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Kubernetes namespace to create and deploy the application into. Must be a valid RFC 1123 DNS label. | `string` | `"bob-demo-app"` | no |
| <a name="input_owner"></a> [owner](#input\_owner) | Owner value for default\_tags Owner key; used for cost allocation reporting. | `string` | `"platform-team"` | no |
| <a name="input_project_name"></a> [project\_name](#input\_project\_name) | Project name applied to default\_tags Project key and used in workspace labelling. | `string` | `"k8s-app-demo"` | no |
| <a name="input_registry_password"></a> [registry\_password](#input\_registry\_password) | Registry authentication password or API key. Written via module data\_wo — never stored in state. Set as sensitive workspace variable. | `string` | n/a | yes |
| <a name="input_registry_server"></a> [registry\_server](#input\_registry\_server) | Hostname of the private container registry (e.g., de.icr.io). Set as workspace variable. | `string` | n/a | yes |
| <a name="input_registry_username"></a> [registry\_username](#input\_registry\_username) | Registry authentication username (e.g., iamapikey for IBM ICR). Set as workspace variable. | `string` | n/a | yes |
| <a name="input_replicas"></a> [replicas](#input\_replicas) | Number of pod replicas. Must be 1–100. | `number` | `2` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_deployment_name"></a> [deployment\_name](#output\_deployment\_name) | Name of the kubernetes\_deployment\_v1 resource. Used by CI/CD pipelines for kubectl rollout status. |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Name of the created Kubernetes namespace. |
| <a name="output_secret_name"></a> [secret\_name](#output\_secret\_name) | Name of the registry pull secret. Allows reference in additional deployments in the same namespace. |
| <a name="output_service_cluster_ip"></a> [service\_cluster\_ip](#output\_service\_cluster\_ip) | ClusterIP address assigned to the service. Value is plan-unknown until apply. |
| <a name="output_service_name"></a> [service\_name](#output\_service\_name) | Name of the kubernetes\_service\_v1 LoadBalancer service. |
<!-- END_TF_DOCS -->
