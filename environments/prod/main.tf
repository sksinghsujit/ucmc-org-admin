variable "db_username" {
  type = string
}

variable "db_password" {
  type      = string
  sensitive = true
}

output "debug_db_username" {
  value = var.db_username
}

output "debug_db_password" {
  value     = var.db_password
  sensitive = true
}


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

# Prod Policy
resource "vault_policy" "prod_policy" {
  name = "prod-app-policy"

  policy = <<EOT
path "${local.kv_mount_path}/data/prod/*" {
  capabilities = ["read", "list"]
}
EOT
}

# Dev Kubernetes Auth Role
resource "vault_kubernetes_auth_backend_role" "prod_role" {
  backend                          = data.vault_auth_backend.kubernetes.path
  role_name                        = "prod-app-role"
  bound_service_account_names      = ["default", "my-app-sa", "pipeline"]
  bound_service_account_namespaces = ["app-prod"]
  token_policies                   = [vault_policy.prod_policy.name]
  token_ttl                        = 3600
}

# Dev Secret in Vault
resource "vault_kv_secret_v2" "prod_db_secret" {
  mount               = local.kv_mount_path
  name                = "prod/database"
  cas                 = 1
  delete_all_versions = true

  data_json = jsonencode({
    username = var.db_username
    password = var.db_password
  })
}


provider "kubernetes" {
  host = var.KUBE_HOST
  token = var.KUBE_TOKEN
  cluster_ca_certificate = var.KUBE_CLUSTER_CA_CERT_DATA
  # insecure = true
}


resource "kubernetes_service_account_v1" "pipeline" {
  metadata {
    name      = "pipeline"
    namespace = "app-prod"
  }
}


# Create Kubernetes Namespace
resource "kubernetes_namespace_v1" "app_prod" {
  metadata {
    name = "app-prod"

    labels = {
      environment = "prod"
      managed-by  = "terraform"
      "argocd.argoproj.io/managed-by" = "openshift-gitops"
    }
  }
}


# more test
