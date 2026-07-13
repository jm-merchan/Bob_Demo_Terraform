## Research: What PMR modules are available for EKS cluster provisioning on AWS?

### Decision

Use `squareops/eks/aws` (v5.4.4) for EKS cluster + managed node group, and `squareops/vpc/aws` (v3.4.1) for VPC networking. Both are high-download public registry modules with compatible interfaces and are the same pair used together in the official squareops complete example.

### Modules Identified

- **Primary EKS Module**: `squareops/eks/aws` v5.4.4
  - **Purpose**: Provisions EKS cluster, IAM roles, KMS encryption, managed node groups, IRSA, VPC-CNI addon
  - **Key Inputs**:
    - `cluster_name` (string) — name of EKS cluster
    - `cluster_version` (string) — Kubernetes version e.g. "1.32"
    - `vpc_id` (string) — VPC ID
    - `vpc_subnet_ids` (list(string)) — all subnet IDs for control plane
    - `vpc_private_subnet_ids` (list(string)) — private subnets for worker nodes
    - `cluster_endpoint_private_access` (bool, default true) — enable private endpoint
    - `cluster_endpoint_public_access` (bool, default true) — enable public endpoint
    - `cluster_endpoint_public_access_cidrs` (list(string)) — restrict public access CIDRs
    - `kms_key_enabled` (bool, default false) — create and use KMS key for secrets encryption
    - `kms_key_arn` (string) — bring-your-own KMS key ARN (alternative to kms_key_enabled)
    - `cluster_log_types` (list(string)) — control plane log types to enable
    - `cluster_log_retention_in_days` (number, default 90) — CloudWatch log retention
    - `authentication_mode` (string, default "API_AND_CONFIG_MAP") — auth mode
    - `enable_cluster_creator_admin_permissions` (bool, default false)
    - `irsa_enabled` (bool, default true) — OIDC provider for IRSA
    - `enable_vpc_cni_addon` (bool, default true)
    - `default_addon_enabled` (bool, default false) — vpc-cni + ebs-csi addons
    - `tags` (any) — resource tags
    - `environment` (string) — environment label
    - `name` (string) — name prefix
  - **Key Outputs**:
    - `cluster_name` — cluster name
    - `cluster_endpoint` — API server endpoint URL
    - `cluster_arn` — cluster ARN
    - `cluster_certificate_authority_data` — base64 CA data
    - `cluster_oidc_issuer_url` — OIDC issuer for IRSA
    - `cluster_security_group_id` — cluster SG ID
    - `worker_iam_role_arn` / `worker_iam_role_name` — node IAM role
    - `kms_policy_arn` — KMS policy ARN (when kms_key_enabled=true)
  - **Note**: Managed node group is a **separate submodule** `squareops/eks/aws//modules/managed-nodegroup` — the cluster module does NOT create node groups itself
  - **Provider deps**: hashicorp/aws >= 5.0.0, helm >= 2.10.0, kubernetes >= 2.20.0, time >= 0.9.2, tls >= 4.0.0

- **VPC Module**: `squareops/vpc/aws` v3.4.1
  - **Purpose**: VPC with public and private subnets across multiple AZs, NAT gateways, flow logs, optional VPN
  - **Key Inputs**:
    - `name` (string) — VPC name prefix
    - `vpc_cidr` (string, default "10.0.0.0/16") — VPC CIDR
    - `availability_zones` (list(any)) — AZs to use
    - `public_subnet_enabled` (bool, default false) — create public subnets
    - `public_subnet_cidrs` (list(any)) — public subnet CIDRs
    - `private_subnet_enabled` (bool, default false) — create private subnets
    - `private_subnet_cidrs` (list(any)) — private subnet CIDRs
    - `one_nat_gateway_per_az` (bool, default false) — HA NAT gateways
    - `flow_log_enabled` (bool, default false) — enable VPC flow logs
    - `environment` (string) — environment label
  - **Key Outputs**:
    - `vpc_id` — VPC ID
    - `public_subnets` — list of public subnet IDs
    - `private_subnets` — list of private subnet IDs
    - `vpc_cidr_block` — VPC CIDR
  - **Provider deps**: hashicorp/aws >= 4.23

### Wiring Considerations

- `squareops/vpc.vpc_id` → `squareops/eks.vpc_id`
- `squareops/vpc.public_subnets + private_subnets` (combined) → `squareops/eks.vpc_subnet_ids`
- `squareops/vpc.private_subnets` → `squareops/eks.vpc_private_subnet_ids`
- Managed node groups use `vpc_private_subnet_ids` (nodes stay in private subnets)
- **Note**: squareops/vpc does NOT automatically apply `kubernetes.io/cluster/*` or `kubernetes.io/role/elb` tags — these must be added via `tags` input or the raw resources layer

### Sources

- Terraform registry: squareops/eks/aws v5.4.4
- Terraform registry: squareops/vpc/aws v3.4.1
