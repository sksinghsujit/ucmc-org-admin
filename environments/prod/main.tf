output "prod_test" {
	value = "Prod Execution verified on Agent"
}

# # This is added to test the auto-trigger
# variable "db_username" {
#   type        = string
#   description = "Database username for Prod environment"
#   default     = "prod_user"
# }

# variable "db_password" {
#   type        = string
#   description = "Database password for Prod environment"
#   sensitive   = true
# }

# output "prod_test" {
#   value = "Prod execution verified on agent"
# }

# terraform {
#   required_version = ">= 1.5.0"
#   required_providers {
#     vault = {
#       source  = "hashicorp/vault"
#       version = "~> 4.0"
#     }
#   }
# }

# provider "vault" {
#   address = "http://vault1.ucmcswg.com:8200"
# }

# data "vault_auth_backend" "kubernetes" {
#   path = "kubernetes"
# }

# data "vault_mount" "kvv2" {
#   path = "secret"
# }

# # Prod Policy
# resource "vault_policy" "prod_policy" {
#   name = "prod-app-policy"

#   policy = <<EOT
# path "${data.vault_mount.kvv2.path}/data/prod/*" {
#   capabilities = ["read", "list"]
# }
# EOT
# }

# # Prod Kubernetes Auth Role
# resource "vault_kubernetes_auth_backend_role" "prod_role" {
#   backend                          = data.vault_auth_backend.kubernetes.path
#   role_name                        = "prod-app-role"
#   bound_service_account_names      = ["default", "my-app-sa"]
#   bound_service_account_namespaces = ["app-prod"]
#   token_policies                   = [vault_policy.prod_policy.name]
#   token_ttl                        = 3600
# }

# # Prod Secret in Vault (Populated via HCP Terraform Variables)
# resource "vault_kv_secret_v2" "prod_db_secret" {
#   mount               = data.vault_mount.kvv2.path
#   name                = "prod/database"
#   cas                 = 1
#   delete_all_versions = true

#   data_json = jsonencode({
#     username = var.db_username
#     password = var.db_password
#   })
# }