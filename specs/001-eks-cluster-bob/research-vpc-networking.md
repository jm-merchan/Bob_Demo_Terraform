## Research: VPC networking resources and EKS subnet requirements

### Decision

For the "create VPC" path, use `squareops/vpc/aws` v3.4.1 which handles subnets, NAT gateways, and route tables. For the "bring-your-own VPC" path, accept `vpc_id`, `private_subnet_ids`, and `public_subnet_ids` as inputs. The conditional is gated by `create_vpc` bool variable (default true).

### Resources Identified (squareops/vpc module wraps these)

- **Primary Resource**: `aws_vpc` — VPC with CIDR block
  - `enable_dns_support = true` (Required for EKS — nodes need DNS resolution)
  - `enable_dns_hostnames = true` (Required for EKS — nodes need DNS hostnames)
  - Schema: all flat attributes, no nested blocks requiring `one()` 
  - Computed: `id`, `arn`, `default_security_group_id`

- **Supporting Resources** (squareops module creates these):
  - `aws_subnet` (public + private) — per AZ, CIDR from cidrsubnet()
  - `aws_internet_gateway` — for public subnets outbound
  - `aws_eip` + `aws_nat_gateway` — per AZ (one_nat_gateway_per_az=true) or single
  - `aws_route_table` + `aws_route_table_association` — public (via IGW) + private (via NAT)
  - `aws_availability_zones` data source — dynamic AZ selection

### EKS Subnet Tagging Requirements (from AWS docs)

For the **AWS Load Balancer Controller** to discover subnets automatically:

| Subnet Type | Required Tag Key | Required Tag Value |
|-------------|-----------------|-------------------|
| Public (external ALB/NLB) | `kubernetes.io/role/elb` | `1` |
| Private (internal ALB/NLB) | `kubernetes.io/role/internal-elb` | `1` |
| Either (cluster ownership) | `kubernetes.io/cluster/<cluster_name>` | `shared` or `owned` |

**Note**: `kubernetes.io/cluster/<cluster_name>` tagging is **optional** for controller v2.1.2+, but recommended when multiple clusters share a VPC. The squareops/vpc module does NOT automatically add these tags — they must be applied via the `tags` input or passed through after cluster name is known.

**Challenge**: Subnet tags reference the cluster name, which creates a circular dependency if the cluster name is unknown at VPC creation time. Resolution: pass cluster name as a variable and apply all subnet tags via the `tags` input of the VPC module.

### squareops/vpc Module Interface (Key Inputs for EKS)

```hcl
module "vpc" {
  source  = "squareops/vpc/aws"
  version = "~> 3.4"

  name                   = var.cluster_name
  environment            = var.environment
  vpc_cidr               = var.vpc_cidr          # default "10.0.0.0/16"
  availability_zones     = var.availability_zones # e.g. ["us-east-1a","us-east-1b"]
  public_subnet_enabled  = true
  public_subnet_cidrs    = var.public_subnet_cidrs
  private_subnet_enabled = true
  private_subnet_cidrs   = var.private_subnet_cidrs
  one_nat_gateway_per_az = var.one_nat_gateway_per_az  # default false (cost-saving)
  flow_log_enabled       = var.enable_vpc_flow_logs    # default false
}
```

### Conditional VPC Pattern

```hcl
# When create_vpc = true: use module outputs
# When create_vpc = false: use var.vpc_id, var.private_subnet_ids, var.public_subnet_ids

locals {
  vpc_id             = var.create_vpc ? module.vpc[0].vpc_id : var.vpc_id
  private_subnet_ids = var.create_vpc ? module.vpc[0].private_subnets : var.private_subnet_ids
  public_subnet_ids  = var.create_vpc ? module.vpc[0].public_subnets : var.public_subnet_ids
}
```

Module called with `count = var.create_vpc ? 1 : 0`.

### Minimum Subnet Recommendations for EKS

- Minimum 2 AZs required for EKS cluster (`subnet_ids` must span ≥ 2 AZs)
- Each subnet should have at least 8 available IPs for Load Balancer Controller
- Recommended: /20 or larger for private subnets (node + pod IP allocation)
- Public subnets /24 typically sufficient for load balancer ENIs
- Do NOT use the same subnet CIDR as the Kubernetes service CIDR (default 10.100.0.0/16 or 172.20.0.0/16)

### Sources

- hashicorp/aws provider v6.54.0: aws_vpc (12783039)
- Terraform registry: squareops/vpc/aws v3.4.1
- AWS docs EKS ALB prerequisites: https://docs.aws.amazon.com/eks/latest/userguide/alb-ingress.html
- AWS docs EKS VPC requirements: https://docs.aws.amazon.com/eks/latest/userguide/network-reqs.html
