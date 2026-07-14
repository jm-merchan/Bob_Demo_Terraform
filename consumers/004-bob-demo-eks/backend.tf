terraform {
  cloud {
    organization = "jose-merchan"
    hostname     = "app.terraform.io"

    workspaces {
      project = "sandbox"
      name    = "sandbox-bob-demo-eks"
    }
  }
}
