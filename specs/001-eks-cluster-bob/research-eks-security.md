## Research: AWS EKS security best practices — IAM, endpoint, encryption, logging, security groups

### Decision

Apply all security controls as configurable variables with secure defaults:
- Endpoint: private access default ON, public access default OFF (Security Hub EKS.1 — High severity)
- Secrets encryption: KMS envelope encryption default ON via `kms_key_enabled=true` (Security Hub EKS.3)
- Control plane logging: all 5 log types ON by default (Security Hub EKS.8)
- Node IAM: minimum required managed policies only
- IRSA: enabled by default for workload identity

### Security Controls

#### 1. Cluster Endpoint Access (Security Hub EKS.1 — High Severity)

- **Secure default**: `endpoint_private_access = true`, `endpoint_public_access = false`
- CIS finding: EKS endpoint should NOT be publicly accessible
- Config rule: `eks-endpoint-no-public-access`
- NIST controls: AC-3, AC-6, SC-7, SC-7(11), SC-7(16), PCI DSS v4.0.1/1.4.4
- **Module variables**:
  - `cluster_endpoint_private_access` (bool, default true in squareops module)
  - `cluster_endpoint_public_access` (bool, default true in squareops module — override to false)
  - `cluster_endpoint_public_access_cidrs` (list) — restrict if public access enabled

#### 2. Secrets Encryption (Security Hub EKS.3 — Medium Severity)

- **Secure default**: KMS envelope encryption enabled via `encryption_config` block
- `resources = ["secrets"]` — encrypts Kubernetes secrets stored in etcd
- In addition to default EBS volume encryption
- Note: K8s ≥ 1.28 has default envelope encryption, but explicit customer-managed key is best practice
- Config rule: `eks-cluster-secrets-encrypted`
- NIST controls: SC-8, SC-12, SC-13, SC-28, PCI DSS v4.0.1/8.3.2
- **squareops module**: `kms_key_enabled = true` creates and attaches KMS key automatically
- Alternatively: `kms_key_arn = aws_kms_key.eks.arn` for bring-your-own KMS

#### 3. KMS Key Policy for EKS Envelope Encryption

Required key policy allows:
- Root account `kms:*` (full admin)
- `eks.amazonaws.com` service principal: `kms:CreateGrant`, `kms:DescribeKey`, `kms:Decrypt`, `kms:GenerateDataKey`
- `enable_key_rotation = true` — rotate annually (compliance requirement)
- `deletion_window_in_days = 7` minimum, 30 default

#### 4. Control Plane Logging (Security Hub EKS.8)

- `enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]`
- All 5 types recommended: api (API server), audit (audit log), authenticator (auth attempts), controllerManager, scheduler
- CloudWatch log group: `/aws/eks/${cluster_name}/cluster`
- Retention: 90 days minimum recommended
- **squareops module**: `cluster_log_types` list + `cluster_log_retention_in_days`

#### 5. Node IAM Role (Least Privilege)

Required managed policies for managed node groups:
```
AmazonEKSWorkerNodePolicy       — register/deregister with cluster
AmazonEKS_CNI_Policy            — VPC CNI networking
AmazonEC2ContainerRegistryReadOnly  — pull images from ECR
```

Assume role policy: `ec2.amazonaws.com` → `sts:AssumeRole`

**squareops module**: Creates node IAM role automatically. `worker_iam_role_arn` and `worker_iam_role_name` outputs for external attachment.

#### 6. Cluster IAM Role

Required managed policy: `AmazonEKSClusterPolicy`
Assume role policy: `eks.amazonaws.com` → `sts:AssumeRole` + `sts:TagSession`

**squareops module**: Creates cluster IAM role automatically.

#### 7. IRSA (IAM Roles for Service Accounts)

- Enable OIDC provider: `irsa_enabled = true` (squareops default true)
- Allows workloads to assume IAM roles without node-level permissions
- Output: `cluster_oidc_issuer_url` for external IRSA configuration

#### 8. Authentication Mode

- `authentication_mode = "API_AND_CONFIG_MAP"` (squareops default) — supports both EKS access entries (API) and aws-auth ConfigMap
- `API` mode recommended for new clusters — fully managed access entries

#### 9. Security Groups

- EKS automatically creates a cluster security group for control plane ↔ node communication
- `cluster_security_group_id` (computed output) — controls inbound to API server
- Additional rules can be added via `cluster_security_group_additional_rules`
- Worker nodes use the cluster security group automatically (managed node groups)

### CIS AWS EKS Benchmark Summary

| Control | Setting | Default in this module |
|---------|---------|------------------------|
| EKS.1 | No public endpoint | `cluster_endpoint_public_access = false` |
| EKS.3 | Encrypted secrets | `kms_key_enabled = true` |
| EKS.8 | Control plane logging | `cluster_log_types = [all 5 types]` |
| General | Node least privilege | Minimum IAM policies only |
| General | IRSA enabled | `irsa_enabled = true` |

### Sources

- AWS Security Hub EKS controls: https://docs.aws.amazon.com/securityhub/latest/userguide/eks-controls.html
- AWS EKS envelope encryption: https://docs.aws.amazon.com/eks/latest/userguide/envelope-encryption.html
- squareops/eks module v5.4.4 interface
- hashicorp/aws provider aws_eks_cluster resource docs
