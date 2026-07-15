locals {
  # EKS API server URL — passed directly to provider "kubernetes" host argument.
  cluster_endpoint = data.terraform_remote_state.eks_infra.outputs.cluster_endpoint

  # base64decode() — provider expects raw PEM bytes, not the base64-encoded form
  # that EKS stores in its cluster object and exposes via remote state.
  cluster_ca_certificate = base64decode(data.terraform_remote_state.eks_infra.outputs.cluster_certificate_authority_data)

  # Cluster short name — used as --cluster-name arg in the aws eks get-token exec block.
  cluster_name = data.terraform_remote_state.eks_infra.outputs.cluster_name
  # NOTE: aws_region is NOT defined as a local — providers.tf uses var.aws_region directly.
  # Provider blocks are evaluated before data sources, so local.aws_region would cause
  # a provider initialisation failure if used in provider "aws" { region }.
}
