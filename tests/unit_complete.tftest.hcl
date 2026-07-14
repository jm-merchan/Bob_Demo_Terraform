# Generated from specs/006-kubernetes/design.md Section 5

mock_provider "kubernetes" {}

# Scenario: "Full Features (complete)"
run "test_full_features" {
  command = plan

  variables {
    app_name                 = "api-gateway"
    namespace                = "platform"
    image                    = "de.icr.io/san-clients/api-gateway:v2.1.0"
    replicas                 = 5
    registry_server          = "de.icr.io"
    registry_username        = "iamapikey"
    registry_password        = "rotate-me"
    registry_secret_revision = 2
    container_port           = 9090
    service_type             = "NodePort"
    cpu_request              = "100m"
    memory_request           = "128Mi"
    cpu_limit                = "1000m"
    memory_limit             = "1Gi"
    liveness_path            = "/actuator/health/liveness"
    readiness_path           = "/actuator/health/readiness"
    enable_liveness_probe    = true
    enable_readiness_probe   = true
  }

  # Custom replica count is coerced to string
  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].replicas == "5"
    error_message = "Deployment replicas must be coerced to the string '5'"
  }

  # Custom container port is applied
  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].port[0].container_port == 9090
    error_message = "Container port must be set to 9090 when container_port = 9090"
  }

  # Custom CPU request is applied
  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].resources[0].requests["cpu"] == "100m"
    error_message = "CPU request must equal '100m' when cpu_request = '100m'"
  }

  # Custom memory limit is applied
  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].resources[0].limits["memory"] == "1Gi"
    error_message = "Memory limit must equal '1Gi' when memory_limit = '1Gi'"
  }

  # Service type is NodePort
  assert {
    condition     = kubernetes_service_v1.this.spec[0].type == "NodePort"
    error_message = "Service type must be 'NodePort' when service_type = 'NodePort'"
  }

  # Service target port matches custom container port
  assert {
    condition     = kubernetes_service_v1.this.spec[0].port[0].target_port == "9090"
    error_message = "Service target_port must equal '9090' when container_port = 9090"
  }

  # Custom liveness path
  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].liveness_probe[0].http_get[0].path == "/actuator/health/liveness"
    error_message = "Liveness probe path must equal '/actuator/health/liveness' when liveness_path = '/actuator/health/liveness'"
  }

  # Custom readiness path
  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].readiness_probe[0].http_get[0].path == "/actuator/health/readiness"
    error_message = "Readiness probe path must equal '/actuator/health/readiness' when readiness_path = '/actuator/health/readiness'"
  }

  # Liveness probe targets custom port
  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].liveness_probe[0].http_get[0].port == "9090"
    error_message = "Liveness probe port must equal '9090' when container_port = 9090"
  }

  # Readiness probe targets custom port
  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].readiness_probe[0].http_get[0].port == "9090"
    error_message = "Readiness probe port must equal '9090' when container_port = 9090"
  }

  # Security controls still active at full features
  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].template[0].spec[0].security_context[0].run_as_non_root == true
    error_message = "Pod security context must enforce run_as_non_root = true even with all features enabled"
  }

  # Capabilities still dropped
  assert {
    condition     = contains(kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].security_context[0].capabilities[0].drop, "ALL")
    error_message = "Container must still drop ALL Linux capabilities when all features are enabled"
  }

  # Read-only rootfs still enforced
  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].security_context[0].read_only_root_filesystem == true
    error_message = "Container read_only_root_filesystem must remain true even with all features enabled"
  }

  # Secret revision is applied
  assert {
    condition     = kubernetes_secret_v1.registry.data_wo_revision == 2
    error_message = "Registry secret data_wo_revision must equal 2 when registry_secret_revision = 2"
  }

  # Deployment image matches
  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].image == "de.icr.io/san-clients/api-gateway:v2.1.0"
    error_message = "Container image must equal 'de.icr.io/san-clients/api-gateway:v2.1.0'"
  }
}
