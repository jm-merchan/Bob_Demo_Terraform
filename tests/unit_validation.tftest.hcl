# Generated from specs/006-kubernetes/design.md Section 5

mock_provider "kubernetes" {}

# ============================================================
# Validation Errors (reject) — expect_failures cases
# ============================================================

# Scenario: "Validation Errors - replicas = 0 rejected"
run "test_replicas_zero_rejected" {
  command = plan

  variables {
    app_name          = "backend"
    namespace         = "staging"
    image             = "de.icr.io/san-clients/backend:latest"
    replicas          = 0
    registry_server   = "de.icr.io"
    registry_username = "iamapikey"
    registry_password = "key"
  }

  expect_failures = [var.replicas]
}

# Scenario: "Validation Errors - replicas = 101 rejected"
run "test_replicas_101_rejected" {
  command = plan

  variables {
    app_name          = "backend"
    namespace         = "staging"
    image             = "de.icr.io/san-clients/backend:latest"
    replicas          = 101
    registry_server   = "de.icr.io"
    registry_username = "iamapikey"
    registry_password = "key"
  }

  expect_failures = [var.replicas]
}

# Scenario: "Validation Errors - namespace uppercase rejected"
run "test_namespace_uppercase_rejected" {
  command = plan

  variables {
    app_name          = "backend"
    namespace         = "MyNamespace"
    image             = "de.icr.io/san-clients/backend:latest"
    replicas          = 1
    registry_server   = "de.icr.io"
    registry_username = "iamapikey"
    registry_password = "key"
  }

  expect_failures = [var.namespace]
}

# Scenario: "Validation Errors - namespace leading hyphen rejected"
run "test_namespace_leading_hyphen_rejected" {
  command = plan

  variables {
    app_name          = "backend"
    namespace         = "-invalid"
    image             = "de.icr.io/san-clients/backend:latest"
    replicas          = 1
    registry_server   = "de.icr.io"
    registry_username = "iamapikey"
    registry_password = "key"
  }

  expect_failures = [var.namespace]
}

# Scenario: "Validation Errors - namespace trailing hyphen rejected"
run "test_namespace_trailing_hyphen_rejected" {
  command = plan

  variables {
    app_name          = "backend"
    namespace         = "invalid-"
    image             = "de.icr.io/san-clients/backend:latest"
    replicas          = 1
    registry_server   = "de.icr.io"
    registry_username = "iamapikey"
    registry_password = "key"
  }

  expect_failures = [var.namespace]
}

# Scenario: "Validation Errors - namespace empty rejected"
run "test_namespace_empty_rejected" {
  command = plan

  variables {
    app_name          = "backend"
    namespace         = ""
    image             = "de.icr.io/san-clients/backend:latest"
    replicas          = 1
    registry_server   = "de.icr.io"
    registry_username = "iamapikey"
    registry_password = "key"
  }

  expect_failures = [var.namespace]
}

# Scenario: "Validation Errors - image empty rejected"
run "test_image_empty_rejected" {
  command = plan

  variables {
    app_name          = "backend"
    namespace         = "staging"
    image             = ""
    replicas          = 1
    registry_server   = "de.icr.io"
    registry_username = "iamapikey"
    registry_password = "key"
  }

  expect_failures = [var.image]
}

# Scenario: "Validation Errors - app_name uppercase rejected"
run "test_app_name_uppercase_rejected" {
  command = plan

  variables {
    app_name          = "UPPER"
    namespace         = "staging"
    image             = "de.icr.io/san-clients/backend:latest"
    replicas          = 1
    registry_server   = "de.icr.io"
    registry_username = "iamapikey"
    registry_password = "key"
  }

  expect_failures = [var.app_name]
}

# Scenario: "Validation Errors - app_name leading hyphen rejected"
run "test_app_name_leading_hyphen_rejected" {
  command = plan

  variables {
    app_name          = "-starts-with-hyphen"
    namespace         = "staging"
    image             = "de.icr.io/san-clients/backend:latest"
    replicas          = 1
    registry_server   = "de.icr.io"
    registry_username = "iamapikey"
    registry_password = "key"
  }

  expect_failures = [var.app_name]
}

# Scenario: "Validation Errors - service_type ExternalName rejected"
run "test_service_type_external_name_rejected" {
  command = plan

  variables {
    app_name          = "backend"
    namespace         = "staging"
    image             = "de.icr.io/san-clients/backend:latest"
    replicas          = 1
    registry_server   = "de.icr.io"
    registry_username = "iamapikey"
    registry_password = "key"
    service_type      = "ExternalName"
  }

  expect_failures = [var.service_type]
}

# Scenario: "Validation Errors - container_port = 0 rejected"
run "test_container_port_zero_rejected" {
  command = plan

  variables {
    app_name          = "backend"
    namespace         = "staging"
    image             = "de.icr.io/san-clients/backend:latest"
    replicas          = 1
    registry_server   = "de.icr.io"
    registry_username = "iamapikey"
    registry_password = "key"
    container_port    = 0
  }

  expect_failures = [var.container_port]
}

# Scenario: "Validation Errors - container_port = 65536 rejected"
run "test_container_port_65536_rejected" {
  command = plan

  variables {
    app_name          = "backend"
    namespace         = "staging"
    image             = "de.icr.io/san-clients/backend:latest"
    replicas          = 1
    registry_server   = "de.icr.io"
    registry_username = "iamapikey"
    registry_password = "key"
    container_port    = 65536
  }

  expect_failures = [var.container_port]
}

# Scenario: "Validation Errors - registry_secret_revision = 0 rejected"
run "test_registry_secret_revision_zero_rejected" {
  command = plan

  variables {
    app_name                 = "backend"
    namespace                = "staging"
    image                    = "de.icr.io/san-clients/backend:latest"
    replicas                 = 1
    registry_server          = "de.icr.io"
    registry_username        = "iamapikey"
    registry_password        = "key"
    registry_secret_revision = 0
  }

  expect_failures = [var.registry_secret_revision]
}

# Scenario: "Validation Errors - registry_password empty rejected"
run "test_registry_password_empty_rejected" {
  command = plan

  variables {
    app_name          = "backend"
    namespace         = "staging"
    image             = "de.icr.io/san-clients/backend:latest"
    replicas          = 1
    registry_server   = "de.icr.io"
    registry_username = "iamapikey"
    registry_password = ""
  }

  expect_failures = [var.registry_password]
}

# Scenario: "Validation Errors - liveness_path no leading slash rejected"
run "test_liveness_path_no_leading_slash_rejected" {
  command = plan

  variables {
    app_name          = "backend"
    namespace         = "staging"
    image             = "de.icr.io/san-clients/backend:latest"
    replicas          = 1
    registry_server   = "de.icr.io"
    registry_username = "iamapikey"
    registry_password = "key"
    liveness_path     = "no-leading-slash"
  }

  expect_failures = [var.liveness_path]
}

# Scenario: "Validation Errors - readiness_path no leading slash rejected"
run "test_readiness_path_no_leading_slash_rejected" {
  command = plan

  variables {
    app_name          = "backend"
    namespace         = "staging"
    image             = "de.icr.io/san-clients/backend:latest"
    replicas          = 1
    registry_server   = "de.icr.io"
    registry_username = "iamapikey"
    registry_password = "key"
    readiness_path    = "health/ready"
  }

  expect_failures = [var.readiness_path]
}

# ============================================================
# Boundary-pass cases (validation accepts)
# ============================================================

# Scenario: "Validation Boundary - replicas = 1 (minimum valid)"
run "test_replicas_minimum_boundary" {
  command = plan

  variables {
    app_name          = "backend"
    namespace         = "staging"
    image             = "de.icr.io/san-clients/backend:latest"
    replicas          = 1
    registry_server   = "de.icr.io"
    registry_username = "iamapikey"
    registry_password = "key"
  }

  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].replicas == "1"
    error_message = "Minimum valid replicas (1) must be accepted and coerced to string '1'"
  }
}

# Scenario: "Validation Boundary - replicas = 100 (maximum valid)"
run "test_replicas_maximum_boundary" {
  command = plan

  variables {
    app_name          = "backend"
    namespace         = "staging"
    image             = "de.icr.io/san-clients/backend:latest"
    replicas          = 100
    registry_server   = "de.icr.io"
    registry_username = "iamapikey"
    registry_password = "key"
  }

  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].replicas == "100"
    error_message = "Maximum valid replicas (100) must be accepted and coerced to string '100'"
  }
}

# Scenario: "Validation Boundary - namespace single character"
run "test_namespace_single_character" {
  command = plan

  variables {
    app_name          = "backend"
    namespace         = "a"
    image             = "de.icr.io/san-clients/backend:latest"
    replicas          = 1
    registry_server   = "de.icr.io"
    registry_username = "iamapikey"
    registry_password = "key"
  }

  assert {
    condition     = kubernetes_secret_v1.registry.metadata[0].namespace == "a"
    error_message = "Single-character namespace 'a' must be accepted; secret namespace must be set to 'a'"
  }
}

# Scenario: "Validation Boundary - namespace 63 characters (maximum)"
run "test_namespace_63_characters" {
  command = plan

  variables {
    app_name          = "backend"
    namespace         = "my-app-namespace-that-is-exactly-sixty-three-characters-long1"
    image             = "de.icr.io/san-clients/backend:latest"
    replicas          = 1
    registry_server   = "de.icr.io"
    registry_username = "iamapikey"
    registry_password = "key"
  }

  assert {
    condition     = kubernetes_secret_v1.registry.metadata[0].namespace == "my-app-namespace-that-is-exactly-sixty-three-characters-long1"
    error_message = "63-character namespace must be accepted; metadata namespace must be set correctly"
  }
}

# Scenario: "Validation Boundary - app_name single character"
run "test_app_name_single_character" {
  command = plan

  variables {
    app_name          = "x"
    namespace         = "staging"
    image             = "de.icr.io/san-clients/backend:latest"
    replicas          = 1
    registry_server   = "de.icr.io"
    registry_username = "iamapikey"
    registry_password = "key"
  }

  assert {
    condition     = kubernetes_deployment_v1.this.metadata[0].name == "x"
    error_message = "Single-character app_name 'x' must be accepted; deployment name must be 'x'"
  }
}

# Scenario: "Validation Boundary - container_port = 1 (minimum valid)"
run "test_container_port_minimum_boundary" {
  command = plan

  variables {
    app_name          = "backend"
    namespace         = "staging"
    image             = "de.icr.io/san-clients/backend:latest"
    replicas          = 1
    registry_server   = "de.icr.io"
    registry_username = "iamapikey"
    registry_password = "key"
    container_port    = 1
  }

  assert {
    condition     = kubernetes_service_v1.this.spec[0].port[0].target_port == "1"
    error_message = "Minimum valid container_port (1) must be accepted; service target_port must be '1'"
  }
}

# Scenario: "Validation Boundary - container_port = 65535 (maximum valid)"
run "test_container_port_maximum_boundary" {
  command = plan

  variables {
    app_name          = "backend"
    namespace         = "staging"
    image             = "de.icr.io/san-clients/backend:latest"
    replicas          = 1
    registry_server   = "de.icr.io"
    registry_username = "iamapikey"
    registry_password = "key"
    container_port    = 65535
  }

  assert {
    condition     = kubernetes_service_v1.this.spec[0].port[0].target_port == "65535"
    error_message = "Maximum valid container_port (65535) must be accepted; service target_port must be '65535'"
  }
}

# Scenario: "Validation Boundary - registry_secret_revision = 1 (minimum valid)"
run "test_registry_secret_revision_minimum_boundary" {
  command = plan

  variables {
    app_name                 = "backend"
    namespace                = "staging"
    image                    = "de.icr.io/san-clients/backend:latest"
    replicas                 = 1
    registry_server          = "de.icr.io"
    registry_username        = "iamapikey"
    registry_password        = "key"
    registry_secret_revision = 1
  }

  assert {
    condition     = kubernetes_secret_v1.registry.data_wo_revision == 1
    error_message = "Minimum valid registry_secret_revision (1) must be accepted; data_wo_revision must equal 1"
  }
}

# Scenario: "Validation Boundary - liveness_path = '/' (single slash)"
run "test_liveness_path_single_slash" {
  command = plan

  variables {
    app_name          = "backend"
    namespace         = "staging"
    image             = "de.icr.io/san-clients/backend:latest"
    replicas          = 1
    registry_server   = "de.icr.io"
    registry_username = "iamapikey"
    registry_password = "key"
    liveness_path     = "/"
  }

  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].liveness_probe[0].http_get[0].path == "/"
    error_message = "Single-slash liveness_path '/' must be accepted; probe path must be '/'"
  }
}

# Scenario: "Validation Boundary - readiness_path = '/health' (standard path)"
run "test_readiness_path_standard" {
  command = plan

  variables {
    app_name          = "backend"
    namespace         = "staging"
    image             = "de.icr.io/san-clients/backend:latest"
    replicas          = 1
    registry_server   = "de.icr.io"
    registry_username = "iamapikey"
    registry_password = "key"
    readiness_path    = "/health"
  }

  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].readiness_probe[0].http_get[0].path == "/health"
    error_message = "Standard readiness_path '/health' must be accepted; probe path must be '/health'"
  }
}
