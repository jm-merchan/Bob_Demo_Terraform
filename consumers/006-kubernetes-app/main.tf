# [CONSTITUTION DEVIATION] kubernetes_namespace_v1 is not in the enumerated glue resource list
# (random_id, random_string, null_resource, terraform_data, time_sleep). Deviation justified:
# (1) Zero Kubernetes-provider modules exist in the jose-merchan PMR (confirmed 2025-07-15).
# (2) The app-deploy module's scope boundary explicitly excludes namespace creation.
# (3) Pre-creating the namespace out-of-band (kubectl) violates IaC lifecycle management.
# (4) A kubernetes_namespace is a thin metadata boundary — spirit of the glue exception applies.
# Risk: Low (P3). See consumer-design.md §6 [CONSTITUTION DEVIATION] for full justification.
# Review trigger: if a kubernetes-namespace PMR module is published, replace this resource.
# Using _v1 canonical form per provider convention (kubernetes_namespace is deprecated).
resource "kubernetes_namespace_v1" "app" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "environment"                  = var.environment
    }
  }
}

# Deploy the backend application via the app-deploy PMR module.
# Source: app.terraform.io/jose-merchan/app-deploy/kubernetes (v0.1.0, ingested 2025-07-15)
# namespace is wired from kubernetes_namespace.app.metadata[0].name to create
# an implicit depends_on — the namespace must exist before the module can create
# the pull secret, deployment, and service inside it.
module "app_deploy" {
  source  = "app.terraform.io/jose-merchan/app-deploy/kubernetes"
  version = "~> 0.2"

  app_name  = var.app_name
  namespace = kubernetes_namespace_v1.app.metadata[0].name
  image     = var.image
  replicas  = var.replicas

  # [SECURITY OVERRIDE] service_type = "LoadBalancer" overrides the module's secure default
  # of "ClusterIP". This provisions an AWS NLB with a public endpoint. Justification:
  # explicit consumer requirement — NLB provides a stable public FQDN for the demo.
  # OPERATORS MUST add WAF/TLS termination before production use.
  # See consumer-design.md §4 Security Controls (Public access row).
  service_type = "LoadBalancer"

  # NLB annotation — requests an AWS Network Load Balancer instead of a Classic ELB.
  # NLB provides a stable public DNS hostname (*.elb.amazonaws.com) and lower latency.
  service_annotations = {
    "service.beta.kubernetes.io/aws-load-balancer-type" = "nlb"
  }

  registry_server   = var.registry_server
  registry_username = var.registry_username
  registry_password = var.registry_password
}
