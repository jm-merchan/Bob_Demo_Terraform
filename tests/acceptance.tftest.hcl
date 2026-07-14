# acceptance — requires real cluster credentials, not run during this workflow

# This file is a stub. Acceptance tests run against a real Kubernetes API server
# with command = plan (no resources created). They require a reachable cluster
# and valid credentials wired through the consumer's provider configuration.
#
# Uncomment and populate the run block below when running acceptance tests locally
# or in a pipeline that has cluster access.

# run "test_plan_verification" {
#   command = plan
#
#   variables {
#     app_name          = "backend-acceptance"
#     namespace         = "acceptance-test"
#     image             = "de.icr.io/san-clients/backend:latest"
#     replicas          = 1
#     registry_server   = "de.icr.io"
#     registry_username = "iamapikey"
#     registry_password = var.icr_api_key
#   }
#
#   assert {
#     condition     = kubernetes_secret_v1.registry.metadata[0].name != ""
#     error_message = "Pull secret name must be set and deterministic after plan against real API"
#   }
#
#   assert {
#     condition     = kubernetes_service_v1.this.spec[0].cluster_ip != ""
#     error_message = "Service ClusterIP must be assigned by the real Kubernetes API"
#   }
# }
