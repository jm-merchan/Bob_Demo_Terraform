# Module Design: terraform-aws-eks-cluster-bob

**Branch**: feat/001-eks-cluster-bob
**Date**: 2025-07-14
**Status**: Draft
**Provider**: hashicorp/aws >= 5.0
**Terraform**: >= 1.7

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

This module provisions a production-ready Amazon EKS cluster by composing approved public-registry modules (`squareops/eks/aws` and `squareops/vpc/aws`). It supports a single managed node group that hosts both public-facing and stateful workloads — workload isolation is achieved at the Kubernetes layer via taints, tolerations, and node selectors rather than separate node pools. The module operates in two VPC modes: it creates a new VPC with public and private subnets when no existing VPC is provided, or accepts an existing VPC's IDs when supplied. All security controls are exposed as variables with secure defaults so consumers get a hardened cluster out of the box and can loosen controls explicitly.

**Scope boundary**: Helm chart or Kubernetes workload deployment; IAM roles for service accounts (IRSA consumers); ECR repository management; Cluster Autoscaler or Karpenter installation; multi-cluster or cross-account federation; Fargate profiles; service mesh configuration.

### Requirements

**Functional requirements**:

- The module MUST provision an EKS cluster with a configurable Kubernetes version.
- The module MUST provision a single managed node group with configurable instance types and autoscaling bounds.
- The module MUST create a new VPC with public and private subnets when `vpc_id` is not supplied.
- The module MUST accept an existing `vpc_id`, `private_subnet_ids`, and `public_subnet_ids` when supplied, and skip VPC creation entirely.
- The module MUST enable KMS envelope encryption for Kubernetes secrets by default.
- The module MUST emit cluster endpoint, certificate authority data, and OIDC issuer URL as outputs.
- The module MUST expose all security controls (endpoint access, encryption, logging, flow logs) as variables with secure defaults.
- Worker nodes MUST be placed in private subnets.
- Subnets MUST be tagged with `kubernetes.io/role/elb` and `kubernetes.io/role/internal-elb` to enable the AWS Load Balancer Controller.

**Non-functional requirements**:

- Provider floor: hashicorp/aws >= 5.0 (squareops/eks requirement).
- Cluster and VPC modules MUST be pinned with pessimistic version constraints (`~> X.Y`).
- The module MUST NOT include `provider {}` blocks — provider configuration is the consumer's responsibility.
- All taggable resources MUST accept a `tags` variable merged with module-required tags.
- Minimum two availability zones required for EKS multi-AZ resiliency.
- Security Hub controls EKS.1 (private endpoint), EKS.3 (encrypted secrets), EKS.8 (control plane logging) MUST have secure defaults.

---

## 2. Resources & Architecture

### Architectural Decisions

**PMR module composition over raw resources**: The module calls `squareops/eks/aws` and `squareops/vpc/aws` rather than authoring raw `aws_eks_cluster` / `aws_vpc` resources. *Rationale*: User explicitly requested "approved modules available in PMR"; both squareops modules are high-download (532k+ / 822k+ downloads), actively maintained, and provide complete, tested implementations. *Source*: research-pmr-modules.md, squareops/eks v5.4.4, squareops/vpc v3.4.1. *Rejected*: terraform-aws-modules/eks and terraform-aws-modules/vpc (also popular but user preference for squareops set). *[CONSTITUTION DEVIATION — see §7]*.

**Separate managed-nodegroup submodule**: EKS cluster creation and node group creation use separate module calls (`squareops/eks/aws` for cluster, `squareops/eks/aws//modules/managed-nodegroup` for node group). *Rationale*: squareops/eks cluster module does NOT create node groups itself — the nodegroup is a separate submodule per the squareops architecture (confirmed in research-pmr-modules.md). *Rejected*: single module call (not supported by squareops module design).

**Auto-derived `create_vpc` local**: The VPC module is toggled via `local.create_vpc = var.vpc_id == null || var.vpc_id == ""` rather than exposing `create_vpc` as a separate input. *Rationale*: Prevents the consumer from passing inconsistent `vpc_id + create_vpc=true` combinations. If `vpc_id` is empty/null, a VPC is created; if non-empty, the existing VPC is used. *Rejected*: separate boolean variable (allows conflicting state).

**Private endpoint default, public optional**: `cluster_endpoint_public_access` defaults to `false`, `cluster_endpoint_private_access` defaults to `true`. *Rationale*: Security Hub EKS.1 (High severity) requires private-only endpoint. Public endpoint is exposed as a variable for development scenarios where VPN/bastion is unavailable. *Source*: research-eks-security.md, AWS Security Hub EKS.1.

**KMS secrets encryption ON by default**: `kms_key_enabled = true` is the default. *Rationale*: Security Hub EKS.3 requires encrypted Kubernetes secrets. squareops module creates and manages the KMS key when `kms_key_enabled=true`. *Source*: research-eks-security.md.

**All 5 control plane log types ON by default**: `cluster_log_types = ["api","audit","authenticator","controllerManager","scheduler"]` is the default. *Rationale*: Security Hub EKS.8. Audit logs in particular are required for security investigations. *Source*: research-eks-security.md.

**EKS subnet tags via VPC module `tags` input**: Public subnets receive `kubernetes.io/role/elb = "1"` and private subnets receive `kubernetes.io/role/internal-elb = "1"` via the squareops/vpc `tags` input. *Rationale*: Avoids circular dependency between VPC and cluster. The cluster name is known at plan time because it comes from `var.cluster_name`. *Source*: research-vpc-networking.md, AWS EKS ALB prerequisites.

**Single NAT gateway by default**: `one_nat_gateway_per_az = false` (single NAT) is the default for cost efficiency. *Rationale*: Multi-AZ NAT is a production HA recommendation but adds ~$32/month per additional AZ. Exposed as a variable for consumers who need HA. *Source*: squareops/vpc module interface.

### Resource Inventory

| Resource Type | Logical Name | Conditional | Depends On | Key Configuration | Schema Notes |
|---------------|-------------|-------------|------------|-------------------|--------------|
| `module squareops/vpc/aws` | `vpc` | `local.create_vpc == true` (count) | -- | vpc_cidr, availability_zones, public/private subnet CIDRs, EKS subnet tags | Module outputs: vpc_id, public_subnets, private_subnets |
| `module squareops/eks/aws` | `eks` | always | module.vpc (conditional) | cluster_name, cluster_version, vpc_id, subnet_ids, private_subnet_ids, kms_key_enabled, cluster_log_types, endpoint access bools, irsa_enabled | Module outputs: cluster_name, cluster_endpoint, cluster_arn, cluster_certificate_authority_data, cluster_oidc_issuer_url, cluster_security_group_id, worker_iam_role_arn |
| `module squareops/eks/aws//modules/managed-nodegroup` | `node_group` | always | module.eks | cluster_name, node_role_arn, subnet_ids, instance_types, min/max/desired, capacity_type, disk_size | Schema varies by submodule; outputs: node_group_arn, min/max/desired_node, instance_types |
| `data aws_availability_zones` | `available` | `local.create_vpc == true` | -- | state = "available" | No nested blocks |

---

## 3. Interface Contract

### Inputs

| Variable | Type | Required | Default | Validation | Sensitive | Description |
|----------|------|----------|---------|------------|-----------|-------------|
| `cluster_name` | `string` | Yes | -- | `length >= 1 && length <= 100`, alphanumeric + `-_` | No | Name of the EKS cluster |
| `kubernetes_version` | `string` | Yes | -- | `can(regex("^[0-9]+\\.[0-9]+$", var.kubernetes_version))` | No | Kubernetes version (e.g. "1.32") |
| `environment` | `string` | Yes | -- | `one of ["dev","staging","prod","sandbox"]` | No | Environment identifier for tagging |
| `node_instance_types` | `list(string)` | Yes | -- | `length >= 1` | No | EC2 instance types for the managed node group (e.g. ["t3.medium"]) |
| `node_min_size` | `number` | Yes | -- | `>= 1` | No | Minimum number of worker nodes |
| `node_max_size` | `number` | Yes | -- | `>= 1` | No | Maximum number of worker nodes |
| `node_desired_size` | `number` | Yes | -- | `>= 1` | No | Desired number of worker nodes |
| `vpc_id` | `string` | No | `null` | -- | No | Existing VPC ID. If null or empty, a new VPC is created |
| `private_subnet_ids` | `list(string)` | No | `[]` | -- | No | Existing private subnet IDs (required when vpc_id is provided) |
| `public_subnet_ids` | `list(string)` | No | `[]` | -- | No | Existing public subnet IDs (required when vpc_id is provided) |
| `vpc_cidr` | `string` | No | `"10.0.0.0/16"` | `can(cidrnetmask(var.vpc_cidr))` | No | CIDR block for the new VPC (only used when creating VPC) |
| `availability_zones` | `list(string)` | No | `[]` | `length == 0 \|\| length >= 2` | No | AZs for subnet creation. Auto-discovered if empty |
| `public_subnet_cidrs` | `list(string)` | No | `["10.0.101.0/24","10.0.102.0/24"]` | -- | No | Public subnet CIDRs (used when creating VPC) |
| `private_subnet_cidrs` | `list(string)` | No | `["10.0.1.0/24","10.0.2.0/24"]` | -- | No | Private subnet CIDRs (used when creating VPC) |
| `one_nat_gateway_per_az` | `bool` | No | `false` | -- | No | Create one NAT gateway per AZ for HA (increases cost) |
| `enable_vpc_flow_logs` | `bool` | No | `false` | -- | No | Enable VPC flow logs to CloudWatch |
| `cluster_endpoint_public_access` | `bool` | No | `false` | -- | No | Allow public access to the EKS API server endpoint |
| `cluster_endpoint_public_access_cidrs` | `list(string)` | No | `["0.0.0.0/0"]` | -- | No | CIDRs allowed to access the public endpoint (only applies when public access enabled) |
| `kms_key_enabled` | `bool` | No | `true` | -- | No | Create and use a KMS key for envelope encryption of Kubernetes secrets |
| `cluster_log_types` | `list(string)` | No | `["api","audit","authenticator","controllerManager","scheduler"]` | -- | No | Control plane log types to enable |
| `cluster_log_retention_in_days` | `number` | No | `90` | `contains([1,3,5,7,14,30,60,90,120,150,180,365,400,545,731,1827,3653], var.cluster_log_retention_in_days)` | No | CloudWatch log group retention in days |
| `enable_irsa` | `bool` | No | `true` | -- | No | Enable OIDC provider for IAM Roles for Service Accounts |
| `authentication_mode` | `string` | No | `"API_AND_CONFIG_MAP"` | `one of ["CONFIG_MAP","API","API_AND_CONFIG_MAP"]` | No | EKS cluster authentication mode |
| `node_capacity_type` | `string` | No | `"ON_DEMAND"` | `one of ["ON_DEMAND","SPOT"]` | No | Node group capacity type |
| `node_disk_size` | `number` | No | `20` | `>= 20` | No | Node EBS disk size in GiB |
| `tags` | `map(string)` | No | `{}` | -- | No | Additional tags to apply to all resources |

### Outputs

| Output | Type | Conditional On | Description |
|--------|------|----------------|-------------|
| `cluster_name` | `string` | always | EKS cluster name |
| `cluster_endpoint` | `string` | always | EKS API server endpoint URL `[plan-unknown]` |
| `cluster_arn` | `string` | always | EKS cluster ARN `[plan-unknown]` |
| `cluster_certificate_authority_data` | `string` | always | Base64-encoded cluster CA data (sensitive) `[plan-unknown]` |
| `cluster_oidc_issuer_url` | `string` | always | OIDC issuer URL for IRSA configuration `[plan-unknown]` |
| `cluster_security_group_id` | `string` | always | Cluster security group ID `[plan-unknown]` |
| `worker_iam_role_arn` | `string` | always | Node group IAM role ARN `[plan-unknown]` |
| `worker_iam_role_name` | `string` | always | Node group IAM role name `[plan-unknown]` |
| `kms_policy_arn` | `string` | `kms_key_enabled == true` | KMS key policy ARN `[plan-unknown]` |
| `vpc_id` | `string` | always | VPC ID (created or existing) `[plan-unknown]` |
| `private_subnet_ids` | `list(string)` | always | Private subnet IDs `[plan-unknown]` |
| `public_subnet_ids` | `list(string)` | always | Public subnet IDs `[plan-unknown]` |

---

## 4. Security Controls

| Control | Enforcement | Configurable? | Reference |
|---------|-------------|---------------|-----------|
| Encryption at rest (K8s secrets) | KMS envelope encryption via `squareops/eks kms_key_enabled=true` | Yes: `kms_key_enabled` variable, default `true` | Security Hub EKS.3 / NIST SC-28 |
| Encryption at rest (etcd EBS) | EKS default EBS volume encryption — platform-enforced | No: AWS-managed default | AWS EKS documentation |
| Encryption in transit | TLS enforced by EKS control plane and kubelet — platform-enforced | No: not configurable, always on | AWS EKS security baseline |
| Public API endpoint access | Blocked by default (`cluster_endpoint_public_access=false`) | Yes: `cluster_endpoint_public_access` variable, default `false` | Security Hub EKS.1 / NIST SC-7 / PCI DSS 1.4.4 |
| Node placement in private subnets | Worker nodes use `vpc_private_subnet_ids` — hardcoded to private subnets | No: private subnets are the only target for nodes | AWS EKS best practice |
| Cluster IAM role (least privilege) | `AmazonEKSClusterPolicy` only — managed by squareops/eks module | No: squareops module enforces minimum required policies | CIS AWS 5.1 / NIST AC-6 |
| Node IAM role (least privilege) | `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, `AmazonEC2ContainerRegistryReadOnly` only | No: squareops module enforces minimum required policies | CIS AWS 5.1 / NIST AC-6 |
| IAM Roles for Service Accounts (IRSA) | OIDC provider enabled by default (`enable_irsa=true`) | Yes: `enable_irsa` variable, default `true` | AWS Well-Architected Security Pillar SEC-2 |
| Control plane logging | All 5 log types enabled by default | Yes: `cluster_log_types` list variable | Security Hub EKS.8 / NIST AU-2 |
| VPC flow logs | Disabled by default (cost trade-off for dev) | Yes: `enable_vpc_flow_logs` variable, default `false` | CIS AWS 3.9 — P2 finding when disabled |
| Tagging | `ManagedBy=terraform`, `Environment`, `Name` applied to all resources | Yes: `tags` variable merged | AWS Well-Architected OPS-3 |

---

## 5. Test Scenarios

### Test Strategy

- Tests run against the **root module directly** — run blocks use `var.*` and assert on `module.eks[0].cluster_name`, `module.vpc[0].vpc_id` style paths (module call outputs), not raw resource attributes like `aws_eks_cluster.this.name`.
- **Mock providers**: squareops/eks requires 5 providers. All 5 must be mocked: `mock_provider "aws" {}`, `mock_provider "helm" {}`, `mock_provider "kubernetes" {}`, `mock_provider "time" {}`, `mock_provider "tls" {}`.
- **command = plan** for all unit tests (mock providers). No credentials needed.
- **`[plan-unknown]`** marks assertions on provider-generated values (ARNs, endpoints, IDs). Substitute with resource-existence checks: `length(module.eks) == 1`.
- Acceptance and integration test files are created but NOT run during this workflow.

### Unit Tests

#### Scenario: Secure Defaults (basic)

**Purpose**: Verify the module works with minimum required inputs and all security defaults are enforced.
**Command**: `plan` (mock providers)

**Inputs**:
```hcl
cluster_name       = "test-basic"
kubernetes_version = "1.32"
environment        = "dev"
node_instance_types = ["t3.medium"]
node_min_size      = 1
node_max_size      = 3
node_desired_size  = 2
```

**Assertions**:
- VPC module is created — `length(module.vpc) == 1`
- EKS module is created — `length(module.eks) == 1`
- Node group module is created — `length(module.node_group) == 1`
- Cluster name matches — `module.eks[0].cluster_name == "test-basic"` `[plan-unknown]`
- Public endpoint OFF by default — variable check: `var.cluster_endpoint_public_access == false`
- KMS enabled by default — variable check: `var.kms_key_enabled == true`
- All 5 log types enabled — `length(var.cluster_log_types) == 5`
- IRSA enabled by default — `var.enable_irsa == true`

#### Scenario: Full Features (complete)

**Purpose**: Verify all features enabled, public endpoint on, BYO-KMS off (module creates KMS), flow logs on.
**Command**: `plan` (mock providers)

**Inputs**:
```hcl
cluster_name                         = "test-complete"
kubernetes_version                   = "1.32"
environment                          = "prod"
node_instance_types                  = ["m5.large"]
node_min_size                        = 2
node_max_size                        = 10
node_desired_size                    = 4
cluster_endpoint_public_access       = true
cluster_endpoint_public_access_cidrs = ["10.0.0.0/8"]
kms_key_enabled                      = true
cluster_log_types                    = ["api","audit","authenticator","controllerManager","scheduler"]
cluster_log_retention_in_days        = 365
enable_irsa                          = true
enable_vpc_flow_logs                 = true
one_nat_gateway_per_az               = true
authentication_mode                  = "API"
node_capacity_type                   = "ON_DEMAND"
node_disk_size                       = 50
tags                                 = { Owner = "platform-team", CostCenter = "eng" }
```

**Assertions**:
- VPC module created — `length(module.vpc) == 1`
- EKS module created — `length(module.eks) == 1`
- Node group module created — `length(module.node_group) == 1`
- Public access enabled — `var.cluster_endpoint_public_access == true`
- KMS enabled — `var.kms_key_enabled == true`
- Log retention set to 365 — `var.cluster_log_retention_in_days == 365`
- HA NAT enabled — `var.one_nat_gateway_per_az == true`

#### Scenario: Feature Interactions (edge cases)

**Sub-scenario: BYO-VPC suppresses VPC module**
**Inputs**:
```hcl
cluster_name        = "test-byovpc"
kubernetes_version  = "1.32"
environment         = "staging"
node_instance_types = ["t3.medium"]
node_min_size       = 1
node_max_size       = 3
node_desired_size   = 2
vpc_id              = "vpc-0123456789abcdef0"
private_subnet_ids  = ["subnet-aaa","subnet-bbb"]
public_subnet_ids   = ["subnet-ccc","subnet-ddd"]
```
**Assertions**:
- VPC module NOT created — `length(module.vpc) == 0`
- EKS module created — `length(module.eks) == 1`

**Sub-scenario: KMS disabled suppresses kms_policy_arn output**
**Inputs**:
```hcl
cluster_name        = "test-nokms"
kubernetes_version  = "1.32"
environment         = "dev"
node_instance_types = ["t3.medium"]
node_min_size       = 1
node_max_size       = 3
node_desired_size   = 2
kms_key_enabled     = false
```
**Assertions**:
- EKS module still created — `length(module.eks) == 1`

**Sub-scenario: Public endpoint with CIDR restriction**
**Inputs**:
```hcl
cluster_name                         = "test-pubcidr"
kubernetes_version                   = "1.32"
environment                          = "dev"
node_instance_types                  = ["t3.medium"]
node_min_size                        = 1
node_max_size                        = 3
node_desired_size                    = 2
cluster_endpoint_public_access       = true
cluster_endpoint_public_access_cidrs = ["192.168.1.0/24"]
```
**Assertions**:
- `var.cluster_endpoint_public_access == true`
- `var.cluster_endpoint_public_access_cidrs == ["192.168.1.0/24"]`

**Sub-scenario: SPOT capacity type**
**Inputs**:
```hcl
cluster_name        = "test-spot"
kubernetes_version  = "1.32"
environment         = "dev"
node_instance_types = ["t3.medium","t3.large"]
node_min_size       = 1
node_max_size       = 5
node_desired_size   = 2
node_capacity_type  = "SPOT"
```
**Assertions**:
- `var.node_capacity_type == "SPOT"`
- `length(var.node_instance_types) == 2`

#### Scenario: Validation Boundaries (accept)

- `cluster_name`: `"a"` (1 char, min) → accepted
- `cluster_name`: 100-char string → accepted
- `kubernetes_version`: `"1.32"` → accepted
- `node_min_size`: `1` (min valid) → accepted
- `node_disk_size`: `20` (min valid) → accepted
- `vpc_cidr`: `"10.0.0.0/16"` → accepted
- `availability_zones`: `["us-east-1a","us-east-1b"]` (exactly 2) → accepted
- `cluster_log_retention_in_days`: `1` (min valid value) → accepted
- `cluster_log_retention_in_days`: `3653` (max valid value) → accepted

#### Scenario: Validation Errors (reject)

- `cluster_name`: `""` → expects validation failure
- `kubernetes_version`: `"v1.32"` (has `v` prefix) → expects validation failure
- `kubernetes_version`: `"latest"` → expects validation failure
- `environment`: `"production"` (not in enum) → expects validation failure
- `node_min_size`: `0` → expects validation failure
- `node_disk_size`: `19` (below minimum) → expects validation failure
- `vpc_cidr`: `"not-a-cidr"` → expects validation failure
- `availability_zones`: `["us-east-1a"]` (only 1 AZ) → expects validation failure
- `authentication_mode`: `"INVALID"` → expects validation failure
- `node_capacity_type`: `"RESERVED"` → expects validation failure

### Acceptance Tests

#### Scenario: Plan Verification

**Purpose**: Verify plan output with real AWS provider — resolves `[plan-unknown]` attributes.
**Command**: `plan` (real providers, requires credentials)

**Inputs**: Same as Secure Defaults scenario.

**Assertions** (resolves [plan-unknown]):
- `module.eks[0].cluster_endpoint` is a non-empty string (URL format)
- `module.eks[0].cluster_arn` matches `arn:aws:eks:*` pattern
- `module.eks[0].cluster_oidc_issuer_url` starts with `https://`

### Integration Tests

#### Scenario: End-to-End Cluster Creation

**Purpose**: Verify EKS cluster, node group, and VPC are created and functional.
**Command**: `apply` (real providers, requires credentials, ~20 min)

**Inputs**: Minimal inputs with small node group (min=1, max=2, desired=1, t3.medium).

**Assertions**:
- Cluster status is ACTIVE
- Node group status is ACTIVE
- VPC, private subnets, public subnets exist
- `cluster_endpoint` is reachable

---

## 6. Implementation Checklist

- [ ] **A: Scaffold** — Create `versions.tf` (terraform + required_providers for aws >=5.0, helm, kubernetes, time, tls), `variables.tf` (all 27 variables with types/defaults/validations), `locals.tf` (`create_vpc` derived local + subnet/vpc wiring locals), `outputs.tf` (all 12 outputs with `try()` for conditional ones)
- [ ] **B: VPC module call** — Add `module "vpc"` call in `main.tf` with `count = local.create_vpc ? 1 : 0`, wiring all VPC inputs, EKS subnet tags via `tags` block
- [ ] **C: EKS + node group module calls** — Add `module "eks"` and `module "node_group"` calls in `main.tf`, wire `local.vpc_id`, `local.private_subnet_ids`, `local.all_subnet_ids`, all security variables
- [ ] **D: Examples** — Create `examples/basic/` (minimal required inputs, create_vpc=true) and `examples/complete/` (all features, BYO-VPC example in comments)
- [ ] **E: Tests** — Write `tests/unit_basic.tftest.hcl`, `tests/unit_complete.tftest.hcl`, `tests/unit_edge_cases.tftest.hcl`, `tests/unit_validation.tftest.hcl`, `tests/acceptance.tftest.hcl`, `tests/integration.tftest.hcl` from Section 5 scenarios
- [ ] **F: Polish** — `README.md` (terraform-docs), `CHANGELOG.md`, `terraform fmt`, `terraform validate`, `tflint`, `trivy config .`

---

## 7. Open Questions

**[CONSTITUTION DEVIATION] §1.1 — Module-first vs raw resources**: The module constitution §1.1 requires "native Terraform resources from official providers." This module instead calls `squareops/eks/aws` and `squareops/vpc/aws` (public registry modules) rather than authoring raw `aws_eks_cluster` / `aws_vpc` resources. *Justification*: The user explicitly requested "approved modules available in PMR." The squareops modules are publicly available, actively maintained (last published April 2025), pinned to specific versions with pessimistic constraints, and provide complete, production-tested implementations. Risk: squareops modules are not HashiCorp-verified; pin versions strictly to mitigate breaking changes.

**[DEFERRED] Managed-nodegroup submodule exact inputs**: The exact input variable names for `squareops/eks/aws//modules/managed-nodegroup` could not be retrieved via MCP (submodule path format not supported). The implementation agent should `terraform init` and inspect the submodule's `variables.tf` directly, or reference the squareops/eks GitHub repo.

**[DEFERRED] VPC flow log destination**: The `squareops/vpc/aws` module's `flow_log_enabled` creates flow logs but the destination (CloudWatch vs S3) and KMS encryption for log group are not confirmed. The implementation agent should validate via `terraform init && terraform providers schema`.
