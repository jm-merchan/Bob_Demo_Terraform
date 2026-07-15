output "namespace" {
  description = "Name of the created Kubernetes namespace."
  value       = kubernetes_namespace_v1.app.metadata[0].name
}

output "deployment_name" {
  description = "Name of the kubernetes_deployment_v1 resource. Used by CI/CD pipelines for kubectl rollout status."
  value       = module.app_deploy.deployment_name
}

output "service_name" {
  description = "Name of the kubernetes_service_v1 LoadBalancer service."
  value       = module.app_deploy.service_name
}

output "service_cluster_ip" {
  description = "ClusterIP address assigned to the service. Value is plan-unknown until apply."
  value       = module.app_deploy.service_cluster_ip
}

output "secret_name" {
  description = "Name of the registry pull secret. Allows reference in additional deployments in the same namespace."
  value       = module.app_deploy.secret_name
}
