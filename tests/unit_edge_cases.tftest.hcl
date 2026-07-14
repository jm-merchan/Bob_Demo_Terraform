# Generated from specs/006-kubernetes/design.md Section 5

mock_provider "kubernetes" {}

# Scenario: "Feature Interactions - Sub-scenario A: Liveness probe disabled, readiness probe enabled"
run "test_liveness_disabled_readiness_enabled" {
  command = plan

  variables {
    app_name               = "backend"
    namespace              = "staging"
    image                  = "de.icr.io/san-clients/backend:latest"
    replicas               = 1
    registry_server        = "de.icr.io"
    registry_username      = "iamapikey"
    registry_password      = "key"
    enable_liveness_probe  = false
    enable_readiness_probe = true
  }

  # Liveness probe block is absent
  assert {
    condition     = length(kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].liveness_probe) == 0
    error_message = "Liveness probe block must be absent when enable_liveness_probe = false"
  }

  # Readiness probe block is present
  assert {
    condition     = length(kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].readiness_probe) == 1
    error_message = "Readiness probe block must be present when enable_readiness_probe = true"
  }

  # Readiness probe uses default path
  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].readiness_probe[0].http_get[0].path == "/health/ready"
    error_message = "Readiness probe path must default to '/health/ready'"
  }
}

# Scenario: "Feature Interactions - Sub-scenario B: Readiness probe disabled, liveness probe enabled"
run "test_readiness_disabled_liveness_enabled" {
  command = plan

  variables {
    app_name               = "backend"
    namespace              = "staging"
    image                  = "de.icr.io/san-clients/backend:latest"
    replicas               = 1
    registry_server        = "de.icr.io"
    registry_username      = "iamapikey"
    registry_password      = "key"
    enable_liveness_probe  = true
    enable_readiness_probe = false
  }

  # Readiness probe block is absent
  assert {
    condition     = length(kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].readiness_probe) == 0
    error_message = "Readiness probe block must be absent when enable_readiness_probe = false"
  }

  # Liveness probe block is present
  assert {
    condition     = length(kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].liveness_probe) == 1
    error_message = "Liveness probe block must be present when enable_liveness_probe = true"
  }

  # Liveness probe uses default path
  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].liveness_probe[0].http_get[0].path == "/health/live"
    error_message = "Liveness probe path must default to '/health/live'"
  }
}

# Scenario: "Feature Interactions - Sub-scenario C: Both probes disabled"
run "test_both_probes_disabled" {
  command = plan

  variables {
    app_name               = "backend"
    namespace              = "staging"
    image                  = "de.icr.io/san-clients/backend:latest"
    replicas               = 1
    registry_server        = "de.icr.io"
    registry_username      = "iamapikey"
    registry_password      = "key"
    enable_liveness_probe  = false
    enable_readiness_probe = false
  }

  # Liveness probe block is absent
  assert {
    condition     = length(kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].liveness_probe) == 0
    error_message = "Liveness probe block must be absent when enable_liveness_probe = false"
  }

  # Readiness probe block is absent
  assert {
    condition     = length(kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].readiness_probe) == 0
    error_message = "Readiness probe block must be absent when enable_readiness_probe = false"
  }

  # Security context is unaffected by disabling probes
  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].template[0].spec[0].security_context[0].run_as_non_root == true
    error_message = "Pod security context run_as_non_root must remain true when both probes are disabled"
  }
}

# Scenario: "Feature Interactions - Sub-scenario D: LoadBalancer service type does not weaken security context"
run "test_loadbalancer_does_not_weaken_security" {
  command = plan

  variables {
    app_name          = "backend"
    namespace         = "staging"
    image             = "de.icr.io/san-clients/backend:latest"
    replicas          = 2
    registry_server   = "de.icr.io"
    registry_username = "iamapikey"
    registry_password = "key"
    service_type      = "LoadBalancer"
  }

  # Service type is LoadBalancer
  assert {
    condition     = kubernetes_service_v1.this.spec[0].type == "LoadBalancer"
    error_message = "Service type must be 'LoadBalancer' when service_type = 'LoadBalancer'"
  }

  # Pod non-root enforcement unchanged
  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].template[0].spec[0].security_context[0].run_as_non_root == true
    error_message = "Pod security context run_as_non_root must remain true when service_type = 'LoadBalancer'"
  }

  # Capabilities still dropped
  assert {
    condition     = contains(kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].security_context[0].capabilities[0].drop, "ALL")
    error_message = "Container must still drop ALL Linux capabilities when service_type = 'LoadBalancer'"
  }

  # Privilege escalation still blocked
  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].security_context[0].allow_privilege_escalation == false
    error_message = "allow_privilege_escalation must remain false when service_type = 'LoadBalancer'"
  }
}

# Scenario: "Feature Interactions - Sub-scenario E: Minimum viable replica count (1)"
run "test_minimum_viable_replica_count" {
  command = plan

  variables {
    app_name          = "backend"
    namespace         = "test"
    image             = "de.icr.io/san-clients/backend:latest"
    replicas          = 1
    registry_server   = "de.icr.io"
    registry_username = "iamapikey"
    registry_password = "key"
  }

  # Replica count is 1 as string
  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].replicas == "1"
    error_message = "Deployment replicas must equal '1' when replicas = 1"
  }

  # Service selector label matches app name
  assert {
    condition     = kubernetes_service_v1.this.spec[0].selector["app.kubernetes.io/name"] == "backend"
    error_message = "Service selector must include app.kubernetes.io/name == 'backend'"
  }
}
