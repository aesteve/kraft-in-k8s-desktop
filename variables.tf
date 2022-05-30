variable "k8s_context" {
  description = "The Kubernetes context to target"
  type = string
  default = "docker-desktop"
}

variable "k8s_config_path" {
  description = "Absolute path to Kubernetes config file"
  type = string
  default = "~/.kube/config"
}