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

variable "broker_app_name" {
  description = "App selector for the brokers"
  type = string
  default = "broker"
}

variable "service_name" {
  description = "Service name for communicating with brokers"
  type = string
  default = "kafka-svc"
}

variable "nb_brokers" {
  description = "Number of brokers to create"
  type = number
  default = 3
}

variable "advertised_hostname" {
  description = "What hostname should be advertised to connect from  outside the k8s cluster (e.g. localhost if port-forward)"
  type = string
  default = "localhost"
}