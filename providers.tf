terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.11"
    }
  }
}

provider "kubernetes" {
  config_path    = var.k8s_config_path
  config_context = var.k8s_context
}