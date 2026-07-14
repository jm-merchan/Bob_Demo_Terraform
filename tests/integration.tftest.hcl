# integration — requires real cluster credentials, not run during this workflow

# This file is a stub. Integration tests run against a real Kubernetes cluster
# with command = apply (resources are created and destroyed). They require a
# reachable sandbox cluster, valid credentials, and a pre-created namespace.
#
# Uncomment and populate the run block below when running integration tests locally
# or in a pipeline that has cluster access and a sandbox namespace.

# run "test_end_to_end" {
#   command = apply
#
#   variables {
#     app_name          = "backend-integration"
#     namespace         = "integration-test"
#     image             = "de.icr.io/san-clients/backend:latest"
#     replicas          = 1
#     registry_server   = "de.icr.io"
#     registry_username = "iamapikey"
#     registry_password = var.icr_api_key
#   }
#
#   assert {
#     condition     = kubernetes_secret_v1.registry.type == "kubernetes.io/dockerconfigjson"
#     error_message = "Registry secret must have type 'kubernetes.io/dockerconfigjson' after apply"
#   }
#
#   assert {
#     condition     = kubernetes_deployment_v1.this.spec[0].replicas == "1"
#     error_message = "Deployment replica count must equal '1' after apply"
#   }
#
#   assert {
#     condition     = kubernetes_service_v1.this.spec[0].cluster_ip != ""
#     error_message = "Service ClusterIP must be assigned by the Kubernetes API after apply"
#   }
# }
