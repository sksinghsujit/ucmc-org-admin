variable "db_username" {
  type        = string
  description = "Database username for Dev environment"
  default     = "dev_user"
}

variable "db_password" {
  type        = string
  description = "Database password for Dev environment"
  sensitive   = true
}

output "dev_test" {
  value = "Dev execution verified on agent"
}

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
  }
}

provider "vault" {
  address = "http://vault1.ucmcswg.com:8200"
}

data "vault_auth_backend" "kubernetes" {
  path = "kubernetes"
}

data "vault_mount" "kvv2" {
  path = "secret"
}

# Dev Policy
resource "vault_policy" "dev_policy" {
  name = "dev-app-policy"

  policy = <<EOT
path "${data.vault_mount.kvv2.path}/data/dev/*" {
  capabilities = ["read", "list"]
}
EOT
}

# Dev Kubernetes Auth Role
resource "vault_kubernetes_auth_backend_role" "dev_role" {
  backend                          = data.vault_auth_backend.kubernetes.path
  role_name                        = "dev-app-role"
  bound_service_account_names      = ["default", "my-app-sa"]
  bound_service_account_namespaces = ["app-dev"]
  token_policies                   = [vault_policy.dev_policy.name]
  token_ttl                        = 3600
}

# Dev Secret in Vault (Populated via HCP Terraform Variables)
resource "vault_kv_secret_v2" "dev_db_secret" {
  mount               = data.vault_mount.kvv2.path
  name                = "dev/database"
  cas                 = 1
  delete_all_versions = true

  data_json = jsonencode({
    username = var.db_username
    password = var.db_password
  })
}