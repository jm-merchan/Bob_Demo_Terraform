locals {
  pod_selector_labels = {
    "app.kubernetes.io/name" = var.app_name
  }

  common_labels = merge(local.pod_selector_labels, {
    "app.kubernetes.io/managed-by" = "terraform"
  })
}
