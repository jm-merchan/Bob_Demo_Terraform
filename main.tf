# Registry pull secret — write-only credentials via data_wo
resource "kubernetes_secret_v1" "registry" {
  metadata {
    name      = "${var.app_name}-registry-secret"
    namespace = var.namespace
    labels    = local.common_labels
  }

  type = "kubernetes.io/dockerconfigjson"

  data_wo = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        (var.registry_server) = {
          auth = base64encode("${var.registry_username}:${var.registry_password}")
        }
      }
    })
  }

  data_wo_revision = var.registry_secret_revision

  lifecycle {
    prevent_destroy = true
  }
}

# Deployment
resource "kubernetes_deployment_v1" "this" {
  metadata {
    name      = var.app_name
    namespace = var.namespace
    labels    = local.common_labels
  }

  spec {
    replicas = tostring(var.replicas)

    selector {
      match_labels = local.pod_selector_labels
    }

    template {
      metadata {
        labels = local.common_labels
      }

      spec {
        security_context {
          run_as_non_root = true
          run_as_user     = "1000"
          fs_group        = "2000"
        }

        image_pull_secrets {
          name = kubernetes_secret_v1.registry.metadata[0].name
        }

        container {
          name  = var.app_name
          image = var.image

          port {
            container_port = var.container_port
          }

          resources {
            requests = {
              cpu    = var.cpu_request
              memory = var.memory_request
            }
            limits = {
              cpu    = var.cpu_limit
              memory = var.memory_limit
            }
          }

          security_context {
            allow_privilege_escalation = false
            privileged                 = false
            read_only_root_filesystem  = true

            capabilities {
              drop = ["ALL"]
            }
          }

          # emptyDir volume mount for /tmp — required when read_only_root_filesystem = true.
          # The app writes temporary files to /tmp; the read-only rootfs blocks all other writes.
          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
          }

          dynamic "startup_probe" {
            for_each = var.enable_startup_probe ? [1] : []
            content {
              http_get {
                path = var.startup_path
                port = tostring(var.container_port)
              }
              period_seconds    = var.startup_period_seconds
              timeout_seconds   = var.startup_timeout_seconds
              failure_threshold = var.startup_failure_threshold
            }
          }

          dynamic "liveness_probe" {
            for_each = var.enable_liveness_probe ? [1] : []
            content {
              http_get {
                path = var.liveness_path
                port = tostring(var.container_port)
              }
              period_seconds    = var.liveness_period_seconds
              timeout_seconds   = var.liveness_timeout_seconds
              failure_threshold = var.liveness_failure_threshold
            }
          }

          dynamic "readiness_probe" {
            for_each = var.enable_readiness_probe ? [1] : []
            content {
              http_get {
                path = var.readiness_path
                port = tostring(var.container_port)
              }
              period_seconds    = var.readiness_period_seconds
              timeout_seconds   = var.readiness_timeout_seconds
              failure_threshold = var.readiness_failure_threshold
            }
          }
        }

        # emptyDir volume backing the /tmp mount above.
        # emptyDir is ephemeral (cleared on pod restart) and lives entirely in memory
        # by default, which is acceptable for temporary files.
        volume {
          name = "tmp"
          empty_dir {}
        }
      }
    }
  }

  wait_for_rollout = false

  lifecycle {
    ignore_changes = [spec[0].template[0].metadata[0].annotations]
  }

  depends_on = [kubernetes_secret_v1.registry]
}

# Service
resource "kubernetes_service_v1" "this" {
  metadata {
    name        = var.app_name
    namespace   = var.namespace
    labels      = local.common_labels
    annotations = var.service_annotations
  }

  spec {
    type     = var.service_type
    selector = local.pod_selector_labels

    port {
      port        = 80
      target_port = tostring(var.container_port)
    }
  }

  depends_on = [kubernetes_deployment_v1.this]
}
