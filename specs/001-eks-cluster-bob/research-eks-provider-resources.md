## Research: Provider resource schemas for aws_eks_cluster, aws_eks_node_group, aws_kms_key

### Decision

Use native `aws_eks_cluster` + `aws_eks_node_group` + `aws_kms_key` resources from hashicorp/aws >= 5.0 (latest 6.54.0). The squareops modules wrap these resources; understanding the underlying schema is critical for test assertions and for the dual-VPC conditional creation pattern.

### Resources Identified

#### aws_eks_cluster (providerDocID: 12782104)

- **Required arguments**: `name`, `role_arn`, `vpc_config` block
- **Optional arguments**:
  - `version` (string) — Kubernetes version e.g. "1.32"
  - `enabled_cluster_log_types` (list of strings) — valid values: `api`, `audit`, `authenticator`, `controllerManager`, `scheduler`
  - `encryption_config` block — `provider.key_arn` (required) + `resources = ["secrets"]`
  - `access_config` block — `authentication_mode` (CONFIG_MAP | API | API_AND_CONFIG_MAP), `bootstrap_cluster_creator_admin_permissions`
  - `kubernetes_network_config` block — `service_ipv4_cidr`, `ip_family`
  - `deletion_protection` (bool, default false)
  - `tags` (map(string))
- **vpc_config block** (all required/computed):
  - `subnet_ids` (Required, list) — must span ≥ 2 AZs
  - `endpoint_private_access` (Optional, bool, default false)
  - `endpoint_public_access` (Optional, bool, default true)
  - `public_access_cidrs` (Optional, list(string))
  - `security_group_ids` (Optional, list)
  - `vpc_id` (Computed)
  - `cluster_security_group_id` (Computed) — auto-created by EKS
- **encryption_config block**:
  - `provider` block (required): `key_arn` (required string)
  - `resources` (required, list): must be `["secrets"]`
- **Schema notes**: `encryption_config` is a SINGLE block (list-typed in schema, max 1). `vpc_config` is a SINGLE block. `access_config` is a SINGLE block.
- **Computed outputs**: `arn`, `endpoint`, `certificate_authority[0].data`, `identity[0].oidc[0].issuer`, `status`, `platform_version`, `cluster_id`
- **Plan-time unknown**: `arn`, `endpoint`, `certificate_authority`, `identity`, `vpc_config.vpc_id`, `vpc_config.cluster_security_group_id`
- **Timeouts**: create 30m, update 60m, delete 15m
- **Import**: `terraform import aws_eks_cluster.example example-name`

#### aws_eks_node_group (providerDocID: 12782107)

- **Required arguments**: `cluster_name`, `node_role_arn`, `scaling_config` block, `subnet_ids`
- **Optional arguments**:
  - `node_group_name` / `node_group_name_prefix` (string)
  - `instance_types` (list(string), default ["t3.medium"])
  - `ami_type` (string) — AL2_x86_64, AL2023_x86_64_STANDARD, BOTTLEROCKET_x86_64, etc.
  - `capacity_type` (string) — ON_DEMAND | SPOT
  - `disk_size` (number, default 20 GiB)
  - `labels` (map(string)) — K8s node labels
  - `taint` block — `key`, `value`, `effect` (NO_SCHEDULE | NO_EXECUTE | PREFER_NO_SCHEDULE)
  - `update_config` block — `max_unavailable` or `max_unavailable_percentage`
  - `version` (string) — K8s version, defaults to cluster version
  - `tags` (map(string))
  - `launch_template` block — `id`, `name`, `version`
  - `node_repair_config` block — enable node auto-repair
- **scaling_config block** (all Required):
  - `desired_size` (Required)
  - `max_size` (Required)
  - `min_size` (Required)
- **Schema notes**: `scaling_config` is a SINGLE block (list in schema, use `[0]` or `one()` for assertions). `update_config` is SINGLE block. `taint` is a SET of blocks.
- **Computed outputs**: `arn`, `id` (cluster_name:node_group_name), `status`, `resources[0].autoscaling_groups[*].name`
- **Plan-time unknown**: `arn`, `id`, `status`, `resources`
- **lifecycle best practice**: `ignore_changes = [scaling_config[0].desired_size]` for external autoscalers
- **Timeouts**: create 60m, update 60m, delete 60m
- **Import**: `cluster_name:node_group_name`

#### aws_kms_key (providerDocID: 12782334)

- **Required**: none (all optional)
- **Optional**:
  - `description` (string)
  - `key_usage` (string, default ENCRYPT_DECRYPT)
  - `customer_master_key_spec` (string, default SYMMETRIC_DEFAULT)
  - `enable_key_rotation` (bool, default false) — **set true for compliance**
  - `deletion_window_in_days` (number, default 30, range 7-30)
  - `policy` (string) — JSON key policy
  - `multi_region` (bool, default false)
  - `tags` (map(string))
- **Computed outputs**: `arn`, `key_id`, `tags_all`
- **Schema notes**: No nested blocks; all flat attributes. `policy` must grant EKS service principal `kms:CreateGrant` for envelope encryption.
- **EKS KMS key policy requirement**: Key policy must allow `eks.amazonaws.com` to call `kms:CreateGrant`, `kms:DescribeKey`, `kms:Decrypt`, `kms:GenerateDataKey`. Use `data.aws_iam_policy_document` with explicit allow for `eks.amazonaws.com` principal.
- **Import**: key ID (UUID format)

### Node IAM Role Required Policies

```
AmazonEKSWorkerNodePolicy
AmazonEKS_CNI_Policy
AmazonEC2ContainerRegistryReadOnly
```

Assume role policy: `ec2.amazonaws.com` principal with `sts:AssumeRole`.

### Cluster IAM Role Required Policy

```
AmazonEKSClusterPolicy
```

Assume role policy: `eks.amazonaws.com` principal with `sts:AssumeRole` AND `sts:TagSession`.

### CloudWatch Log Group

- Resource: `aws_cloudwatch_log_group`
- `name = "/aws/eks/${var.cluster_name}/cluster"`
- `retention_in_days` — configurable (default 90 recommended by Security Hub)
- Must be created BEFORE the cluster to avoid race condition

### Sources

- hashicorp/aws provider v6.54.0 docs — aws_eks_cluster (12782104), aws_eks_node_group (12782107), aws_kms_key (12782334)
- AWS Security Hub EKS controls: https://docs.aws.amazon.com/securityhub/latest/userguide/eks-controls.html
