output "deployment_name" {
  description = "Name of the kubernetes_deployment_v1 resource. Used by CI/CD pipelines for kubectl rollout status commands."
  value       = kubernetes_deployment_v1.this.metadata[0].name
}

output "service_name" {
  description = "Name of the kubernetes_service_v1 resource. Used by Ingress resources and other services that reference this workload."
  value       = kubernetes_service_v1.this.metadata[0].name
}

output "service_cluster_ip" {
  description = "ClusterIP address assigned to the service. Empty string for headless services. Value is plan-unknown until apply."
  value       = kubernetes_service_v1.this.spec[0].cluster_ip
}

output "secret_name" {
  description = "Name of the kubernetes_secret_v1 pull-secret resource. Allows consumers to reference the pull secret in additional deployments in the same namespace."
  value       = kubernetes_secret_v1.registry.metadata[0].name
}

output "service_load_balancer_hostname" {
  description = "Public DNS hostname assigned by the cloud load balancer (NLB/CLB). Empty string when service_type is ClusterIP or NodePort. Value is plan-unknown until apply — AWS NLBs take 1-3 minutes to provision."
  value       = try(kubernetes_service_v1.this.status[0].load_balancer[0].ingress[0].hostname, "")
}
