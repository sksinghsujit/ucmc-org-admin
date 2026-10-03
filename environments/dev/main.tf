variable "VAULT_ADDR" {}
variable "VAULT_TOKEN" {}
variable "KUBE_HOST" {}
variable "KUBE_TOKEN" {}
variable "KUBE_CLUSTER_CA_CERT_DATA" {}


terraform {
  required_version = ">= 1.5.0"
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
  }
}

provider "vault" {}

# Define mount path locally instead of invalid data source
locals {
  kv_mount_path = "secret"
}

data "vault_auth_backend" "kubernetes" {
  path = "kubernetes"
}

# Dev Policy
resource "vault_policy" "dev_policy" {
  name = "dev-app-policy"

  policy = <<EOT
path "${local.kv_mount_path}/data/dev/*" {
  capabilities = ["read", "list"]
}
EOT
}

# Dev Kubernetes Auth Role
resource "vault_kubernetes_auth_backend_role" "dev_role" {
  backend                          = data.vault_auth_backend.kubernetes.path
  role_name                        = "dev-app-role"
  bound_service_account_names      = ["default", "my-app-sa", "pipeline"]
  bound_service_account_namespaces = ["app-dev"]
  token_policies                   = [vault_policy.dev_policy.name]
  token_ttl                        = 3600
}


resource "vault_kubernetes_auth_backend_role" "with_vault_dev_role" {
  backend                          = data.vault_auth_backend.kubernetes.path
  role_name                        = "with-vault-dev-app-role"
  bound_service_account_names      = ["default", "my-app-sa", "pipeline"]
  bound_service_account_namespaces = ["with-vault-app-dev"]
  token_policies                   = [vault_policy.dev_policy.name]
  token_ttl                        = 3600
}

provider "kubernetes" {
  host = var.KUBE_HOST
  token = var.KUBE_TOKEN
  cluster_ca_certificate = var.KUBE_CLUSTER_CA_CERT_DATA
  # insecure = true
}

# Create Kubernetes Namespace
resource "kubernetes_namespace_v1" "app_dev" {
  metadata {
    name = "app-dev"

    labels = {
      environment = "dev"
      managed-by  = "terraform"
      "argocd.argoproj.io/managed-by" = "openshift-gitops"
    }
  }
}


# Create Kubernetes Namespace
resource "kubernetes_namespace_v1" "with-vault-app-dev" {
  metadata {
    name = "with-vault-app-dev"

    labels = {
      environment = "dev"
      managed-by  = "terraform"
      "argocd.argoproj.io/managed-by" = "openshift-gitops"
    }
  }
}
# Test an update
