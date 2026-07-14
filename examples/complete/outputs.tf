output "deployment_name" {
  description = "Name of the Kubernetes Deployment resource."
  value       = module.backend.deployment_name
}

output "service_name" {
  description = "Name of the Kubernetes Service resource."
  value       = module.backend.service_name
}

output "service_cluster_ip" {
  description = "ClusterIP assigned to the service (plan-unknown until apply)."
  value       = module.backend.service_cluster_ip
}

output "secret_name" {
  description = "Name of the image pull secret."
  value       = module.backend.secret_name
}
