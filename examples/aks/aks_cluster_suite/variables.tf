variable "cluster_name" {
  type        = string
  description = "Name of the AKS cluster to be connected to the CAST AI."
}

variable "cluster_region" {
  type        = string
  description = "Region of the cluster to be connected to CAST AI."
}

variable "kubernetes_version" {
  type        = string
  description = "The Kubernetes version specified when creating AKS managed cluster. Defaults to the latest available version when not specified"
  default     = null
}

variable "resource_group" {
  type        = string
  description = "Azure resource group that contains the cluster."
}

variable "subnets" {
  type        = list(string)
  description = "Subnet IDs used by CAST AI to provision nodes."
}

variable "subscription_id" {
  type        = string
  description = "Azure subscription ID."
}

variable "additional_resource_groups" {
  type    = list(string)
  default = []
}

variable "delete_nodes_on_disconnect" {
  type        = bool
  description = "Optionally delete Cast AI created nodes when the cluster is destroyed."
  default     = true
}

variable "castai_api_url" {
  type        = string
  description = "CAST AI url to API, default value is https://api.cast.ai"
  default     = "https://api.cast.ai"
}

variable "castai_api_token" {
  type        = string
  description = "CAST AI API token created in console.cast.ai API Access keys section."
}

variable "readonly" {
  type        = bool
  description = "Controls if cluster is connected to CAST AI in 'read-only' mode ir in 'Full Access' mode"
  default     = true
}

variable "castai_grpc_url" {
  type        = string
  description = "CAST AI gRPC URL"
  default     = "grpc.cast.ai:443"
}

variable "autoscaler_enabled" {
  type        = bool
  description = "Controls if CAST AI autoscaler is enabled"
  default     = false
}

variable "api_grpc_addr" {
  type        = string
  description = "CAST AI GRPC API address"
  default     = "api-grpc.cast.ai:443"
}

variable "install_security_agent" {
  type        = bool
  default     = false
  description = "Optional flag for installation of security agent (https://docs.cast.ai/product-overview/console/security-insights/)"
}

variable "install_evictor_agent" {
  type        = bool
  default     = false
  description = "Optional flag for installation of evictor agent (https://docs.cast.ai/faq-evictor/)"
}

variable "self_managed" {
  type        = bool
  default     = false
  description = "Whether CAST AI components' upgrades are managed by a customer; by default upgrades are managed CAST AI central system."
}

variable "kvisor_values" {
  description = "List of YAML formatted string with kvisor values"
  type        = list(string)
  default     = []
}

variable "kvisor_version" {
  description = "Version of kvisor chart. Default latest"
  type        = string
  default     = null
}

variable "evictor_values" {
  description = "List of YAML formatted string with evictor values"
  type        = list(string)
  default     = []
}

variable "evictor_version" {
  description = "Version of evictor chart. Default latest"
  type        = string
  default     = null
}

variable "install_pod_node_lifecycle" {
  type        = bool
  default     = false
  description = "Optional flag for installation of castai-pod-node-lifecycle (https://docs.cast.ai/docs/spot-only-cluster)"
}

variable "pod_node_lifecycle_values" {
  description = "List of YAML formatted string with pod_node_lifecycle values"
  type        = list(string)
  default     = []
}

variable "pod_node_lifecycle_version" {
  description = "Version of pod_node_lifecycle chart. Default latest"
  type        = string
  default     = null
}

variable "install_spothandler_agent" {
  type        = bool
  default     = false
  description = "Optional flag for installation of spothandler agent (https://docs.cast.ai/product-overview/console/security-insights/)"
}

variable "spothandler_values" {
  description = "List of YAML formatted string with spothandler values"
  type        = list(string)
  default     = []
}

variable "spothandler_version" {
  description = "Version of spothandler chart. Default latest"
  type        = string
  default     = null
}

variable "woop_autoscaler_enabled" {
  type        = bool
  description = "Controls if CAST AI workload optimization autoscaler is enabled"
  default     = false
}

variable "workload_autoscaler_values" {
  description = "List of YAML formatted string with workload-autoscaler values"
  type        = list(string)
  default     = []
}

variable "workload_autoscaler_version" {
  description = "Version of workload-autoscaler chart. Default latest"
  type        = string
  default     = null
}


variable "tags" {
  type        = map(any)
  description = "Optional tags for new cluster nodes. This parameter applies only to new nodes - tags for old nodes are not reconciled."
  default     = {}
}
