# Read EKS cluster connection details from the eks-infra-vcs workspace remote state.
# The new workspace (k8s-app-demo-bob) has been registered as a remote-state consumer
# of eks-infra-vcs (confirmed via API 2025-07-15). Uses "remote" backend pointing at
# the HCP Terraform organization.
data "terraform_remote_state" "eks_infra" {
  backend = "remote"

  config = {
    organization = "jose-merchan"
    workspaces = {
      name = var.infra_workspace
    }
  }
}
