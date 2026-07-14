# Generated from specs/006-kubernetes/design.md Section 5

mock_provider "kubernetes" {}

# Scenario: "Secure Defaults (basic)"
run "test_secure_defaults" {
  command = plan

  variables {
    app_name          = "backend"
    namespace         = "app-production"
    image             = "de.icr.io/san-clients/backend:latest"
    replicas          = 3
    registry_server   = "de.icr.io"
    registry_username = "iamapikey"
    registry_password = "test-api-key"
  }

  # Deployment is planned — name matches app_name
  assert {
    condition     = kubernetes_deployment_v1.this.metadata[0].name == "backend"
    error_message = "Deployment name must equal app_name 'backend'"
  }

  # Deployment namespace is set
  assert {
    condition     = kubernetes_deployment_v1.this.metadata[0].namespace == "app-production"
    error_message = "Deployment must be placed in the 'app-production' namespace"
  }

  # Deployment label app.kubernetes.io/name is set
  assert {
    condition     = kubernetes_deployment_v1.this.metadata[0].labels["app.kubernetes.io/name"] == "backend"
    error_message = "Deployment must carry label app.kubernetes.io/name == 'backend'"
  }

  # Deployment label managed-by is terraform
  assert {
    condition     = kubernetes_deployment_v1.this.metadata[0].labels["app.kubernetes.io/managed-by"] == "terraform"
    error_message = "Deployment must carry label app.kubernetes.io/managed-by == 'terraform'"
  }

  # Replica count is coerced to string
  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].replicas == "3"
    error_message = "Deployment replicas must be coerced to the string '3'"
  }

  # Pod selector label is stable
  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].selector[0].match_labels["app.kubernetes.io/name"] == "backend"
    error_message = "Pod selector match_labels must include app.kubernetes.io/name == 'backend'"
  }

  # Pod template carries matching label
  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].template[0].metadata[0].labels["app.kubernetes.io/name"] == "backend"
    error_message = "Pod template labels must include app.kubernetes.io/name == 'backend'"
  }

  # Container image is set
  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].image == "de.icr.io/san-clients/backend:latest"
    error_message = "Container image must equal the supplied image variable"
  }

  # Container port defaults to 8080
  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].port[0].container_port == 8080
    error_message = "Container port must default to 8080"
  }

  # CPU request default is set
  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].resources[0].requests["cpu"] == "250m"
    error_message = "CPU request must default to '250m'"
  }

  # Memory request default is set
  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].resources[0].requests["memory"] == "256Mi"
    error_message = "Memory request must default to '256Mi'"
  }

  # CPU limit default is set
  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].resources[0].limits["cpu"] == "500m"
    error_message = "CPU limit must default to '500m'"
  }

  # Memory limit default is set
  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].resources[0].limits["memory"] == "512Mi"
    error_message = "Memory limit must default to '512Mi'"
  }

  # Pod security context non-root enforced
  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].template[0].spec[0].security_context[0].run_as_non_root == true
    error_message = "Pod security context must enforce run_as_non_root = true"
  }

  # Pod security context run-as-user
  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].template[0].spec[0].security_context[0].run_as_user == "1000"
    error_message = "Pod security context must set run_as_user = '1000'"
  }

  # Pod security context fs-group
  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].template[0].spec[0].security_context[0].fs_group == "2000"
    error_message = "Pod security context must set fs_group = '2000'"
  }

  # Container no privilege escalation
  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].security_context[0].allow_privilege_escalation == false
    error_message = "Container security context must set allow_privilege_escalation = false"
  }

  # Container not privileged
  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].security_context[0].privileged == false
    error_message = "Container security context must set privileged = false"
  }

  # Container read-only root filesystem
  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].security_context[0].read_only_root_filesystem == true
    error_message = "Container security context must enforce read_only_root_filesystem = true"
  }

  # Container drops ALL capabilities
  assert {
    condition     = contains(kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].security_context[0].capabilities[0].drop, "ALL")
    error_message = "Container must drop ALL Linux capabilities"
  }

  # Liveness probe path defaults
  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].liveness_probe[0].http_get[0].path == "/health/live"
    error_message = "Liveness probe path must default to '/health/live'"
  }

  # Readiness probe path defaults
  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].readiness_probe[0].http_get[0].path == "/health/ready"
    error_message = "Readiness probe path must default to '/health/ready'"
  }

  # Image pull secret reference is present — [plan-unknown] value, existence check only
  assert {
    condition     = length(kubernetes_deployment_v1.this.spec[0].template[0].spec[0].image_pull_secrets) >= 1
    error_message = "Deployment must reference at least one image pull secret"
  }

  # Service is planned — name matches app_name
  assert {
    condition     = kubernetes_service_v1.this.metadata[0].name == "backend"
    error_message = "Service name must equal app_name 'backend'"
  }

  # Service type defaults to ClusterIP
  assert {
    condition     = kubernetes_service_v1.this.spec[0].type == "ClusterIP"
    error_message = "Service type must default to 'ClusterIP' (no external exposure)"
  }

  # Service selector matches deployment labels
  assert {
    condition     = kubernetes_service_v1.this.spec[0].selector["app.kubernetes.io/name"] == "backend"
    error_message = "Service selector must include app.kubernetes.io/name == 'backend'"
  }

  # Service target port matches container port
  assert {
    condition     = kubernetes_service_v1.this.spec[0].port[0].target_port == "8080"
    error_message = "Service target_port must equal '8080' (coerced to string from container_port default)"
  }

  # Secret is planned with correct type
  assert {
    condition     = kubernetes_secret_v1.registry.type == "kubernetes.io/dockerconfigjson"
    error_message = "Registry secret must have type 'kubernetes.io/dockerconfigjson'"
  }

  # Secret namespace matches
  assert {
    condition     = kubernetes_secret_v1.registry.metadata[0].namespace == "app-production"
    error_message = "Registry secret must be placed in the 'app-production' namespace"
  }

  # Secret cluster IP — [plan-unknown] during mock plan, existence check only
  assert {
    condition     = kubernetes_service_v1.this.spec[0] != null
    error_message = "Service spec must be present (cluster_ip is plan-unknown with mock provider)"
  }
}
