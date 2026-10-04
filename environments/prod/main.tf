variable "VAULT_ADDR" {}
variable "VAULT_TOKEN" {}
variable "KUBE_HOST" {}
variable "KUBE_TOKEN" {}
variable "KUBE_CLUSTER_CA_CERT_DATA" {}
variable "CUSTOM_CA_CRT" {}

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
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

# Vault stores the k8s_host and k8s_ca_cert in its auth config endpoint
data "vault_generic_secret" "kubernetes_auth_config" {
  path = "auth/${data.vault_auth_backend.kubernetes.path}/config"
}

# 3. Configure the kubectl provider dynamically
provider "kubectl" {
  host                   = var.KUBE_HOST
  cluster_ca_certificate = var.KUBE_CLUSTER_CA_CERT_DATA
  token                  = var.KUBE_TOKEN
  load_config_file       = false
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


resource "vault_kubernetes_auth_backend_role" "with_vault_prod_role" {
  backend                          = data.vault_auth_backend.kubernetes.path
  role_name                        = "with-vault-prod-app-role"
  bound_service_account_names      = ["default", "my-app-sa", "pipeline"]
  bound_service_account_namespaces = ["with-vault-app-prod"]
  token_policies                   = [vault_policy.prod_policy.name]
  token_ttl                        = 3600
}

provider "kubernetes" {
  host = var.KUBE_HOST
  token = var.KUBE_TOKEN
  cluster_ca_certificate = var.KUBE_CLUSTER_CA_CERT_DATA
  # insecure = true
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

# Create Kubernetes Namespace
resource "kubernetes_namespace_v1" "with_vault_app_prod" {
  metadata {
    name = "with-vault-app-prod"

    labels = {
      environment = "prod"
      managed-by  = "terraform"
      "argocd.argoproj.io/managed-by" = "openshift-gitops"
    }
  }
}

resource "kubernetes_service_account_v1" "with_vault_pipeline" {
  metadata {
    name      = "pipeline"
    namespace = "with-vault-app-prod"
  }
}

resource "kubernetes_manifest" "app_dev_src_pvc" {
  manifest = {
    apiVersion = "v1"
    kind       = "PersistentVolumeClaim"
    metadata = {
      name      = "app-dev-src-pvc"
      namespace = var.namespace
      labels = {
        "app.kubernetes.io/managed-by" = "terraform"
      }
    }
    spec = {
      accessModes = [
        "ReadWriteMany" # RWX
      ]
      storageClassName = "ocs-storagecluster-cephfs"
      resources = {
        requests = {
          storage = "10Gi"
        }
      }
    }
  }
}

resource "kubernetes_role_binding_v1" "scc_binding" {
  metadata {
    name      = "allow-anyuid-scc"
    namespace = "with-vault-app-prod"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "system:openshift:scc:privileged" 
  }

  subject {
    kind      = "ServiceAccount"
    name      = "pipeline"
    namespace = "with-vault-app-prod"
  }
}


resource "kubernetes_cluster_role_binding_v1" "pipeline_image_builder_prod" {
  metadata {
    name = "my-openshift-cluster-role-binding"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "system:image-builder" 
  }

  subject {
    kind      = "ServiceAccount"
    name      = "pipeline"
    namespace = "with-vault-app-prod"
  }
}

resource "kubernetes_config_map_v1" "custom-ca-bundle" {
  metadata {
    name      = "custom-ca-bundle"
    namespace = "with-vault-app-prod"
  }

  data = {
    "custom-ca.crt" = var.CUSTOM_CA_CRT
  }
}

variable "namespace" {
  type        = string
  description = "Target OpenShift / Kubernetes namespace"
  default     = "with-vault-app-prod"
}

variable "vault_address" {
  type        = string
  description = "Vault cluster address"
  default     = "http://vault1.ucmcswg.com:8200"
}

variable "vault_auth_ref" {
  type        = string
  description = "Name of the VaultAuth CR in the cluster"
  default     = "vault-auth"
}

# 1. VaultConnection Custom Resource
resource "kubernetes_manifest" "vault_connection" {
  manifest = {
    apiVersion = "secrets.hashicorp.com/v1beta1"
    kind       = "VaultConnection"
    metadata = {
      name      = "vault-connection"
      namespace = var.namespace
    }
    spec = {
      address       = var.vault_address
      skipTLSVerify = true
    }
  }
}

# 1. Vault Authentication Configuration
resource "kubectl_manifest" "vault_auth" {
  yaml_body = <<YAML
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultAuth
metadata:
  name: ${var.vault_auth_ref}
  namespace: ${var.namespace}
spec:
  method: "kubernetes"
  mount: "kubernetes"
  kubernetes:
    role: "with-vault-dev-app-role" 
    serviceAccount: "default"
  vaultConnectionRef: "vault-connection"
YAML

  lifecycle {
    ignore_changes = [
      yaml_body,
    ]
  }

  depends_on = [kubernetes_manifest.vault_connection]
}


# 2. Database Credentials Secret
resource "kubectl_manifest" "postgres_vso_secret" {
  yaml_body = <<YAML
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: postgres-vso-secret
  namespace: ${var.namespace}
spec:
  vaultAuthRef: ${var.vault_auth_ref}
  mount: "secret"
  type: "kv-v2"
  path: "dev/database"
  refreshInterval: "1m"
  destination:
    name: "postgres-secret"
    create: true
YAML

  lifecycle {
    ignore_changes = [
      yaml_body,
    ]
  }

  depends_on = [kubernetes_manifest.vault_connection]
}

# 3. GitHub PAT Secret (HTTP Auth)
resource "kubectl_manifest" "github_gitops_token_sync" {
  yaml_body = <<YAML
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: github-gitops-token-sync
  namespace: ${var.namespace}
spec:
  vaultAuthRef: ${var.vault_auth_ref}
  mount: "secret"
  type: "kv-v2"
  path: "dev/github"
  refreshInterval: "1m"
  transformation:
    includeKeys:
      - "password"
  destination:
    name: "github-gitops-token"
    create: true
YAML

  lifecycle {
    ignore_changes = [
      yaml_body,
    ]
  }

  depends_on = [kubernetes_manifest.vault_connection]
}

# 4. SonarQube Token Secret
resource "kubectl_manifest" "sonarqube_token_sync" {
  yaml_body = <<YAML
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: sonarqube-token-sync
  namespace: ${var.namespace}
spec:
  vaultAuthRef: ${var.vault_auth_ref}
  mount: "secret"
  type: "kv-v2"
  path: "dev/sonarqube"
  refreshInterval: "1m"
  destination:
    name: "sonarqube-token"
    create: true
YAML

  lifecycle {
    ignore_changes = [
      yaml_body,
    ]
  }

  depends_on = [kubernetes_manifest.vault_connection]
}
# 5. GitHub SSH Key Secret (SSH Auth for Tekton)
resource "kubectl_manifest" "github_gitops_ssh_sync" {
  yaml_body = <<YAML
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: github-gitops-ssh-sync
  namespace: ${var.namespace}
spec:
  vaultAuthRef: ${var.vault_auth_ref}
  mount: "secret"
  type: "kv-v2"
  path: "dev/github"
  refreshInterval: "1m"
  transformation:
    includeKeys:
      - "ssh-privatekey"
  destination:
    name: "github-gitops-ssh"
    create: true
    type: "kubernetes.io/ssh-auth"
    annotations:
      tekton.dev/git-0: "github.com"
YAML

  lifecycle {
    ignore_changes = [
      yaml_body,
    ]
  }

  depends_on = [kubernetes_manifest.vault_connection]
}
# update to test