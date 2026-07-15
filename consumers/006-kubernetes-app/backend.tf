terraform {
  cloud {
    organization = "jose-merchan"
    hostname     = "app.terraform.io"

    workspaces {
      project = "Default Project"
      name    = "k8s-app-demo-bob"
    }
  }
}
