# GKE module variables.
variable "cluster_name" {
  type        = string
  description = "GKE cluster name in GCP project."
}

variable "cluster_region" {
  type        = string
  description = "The region to create the cluster."
}

variable "cluster_zones" {
  type        = list(string)
  description = "The zones to create the cluster."
}

variable "kvisor_controller_extra_args" {
  type        = map(string)
  description = "Extra arguments for the kvisor controller. Optionally enable kvisor to lint Kubernetes YAML manifests, scan workload images and check if workloads pass CIS Kubernetes Benchmarks as well as NSA, WASP and PCI recommendations."
  default = {
    "kube-linter-enabled"        = "true"
    "image-scan-enabled"         = "true"
    "kube-bench-enabled"         = "true"
    "kube-bench-cloud-provider"  = "gke"
  }
}

variable "project_id" {
  type        = string
  description = "GCP project ID in which GKE cluster would be created."
}

variable "subnets" {
  type        = list(string)
  description = "Subnet IDs used by CAST AI to provision nodes."
  default = []
}

variable "delete_nodes_on_disconnect" {
  type        = bool
  description = "Optionally delete Cast AI created nodes when the cluster is destroyed."
  default     = false
}

# Variables required for connecting EKS cluster to CAST AI
variable "castai_api_token" {
  type        = string
  description = "CAST AI API token created in console.cast.ai API Access keys section."
}

variable "castai_api_url" {
  type        = string
  description = "CAST AI api url"
  default     = "https://api.cast.ai"
}

variable "service_accounts_unique_ids" {
  type        = list(string)
  description = "Service Accounts' unique IDs used by node pools in the cluster."
  default     = []
}

variable "readonly" {
  type        = bool
  description = "Controls if cluster is connected to CAST AI in 'read-only' mode ir in 'Full Access' mode"
  default     = true
}

variable "autoscaler_enabled" {
  type        = bool
  description = "Controls if CAST AI autoscaler is enabled"
  default     = false
}

variable "autoscaler_limits_enabled" {
  type        = bool
  description = "Controls if CAST AI autoscaler CPU limits are enabled"
  default     = false
}

variable "autoscaler_cpu_limits" {
  type        = map(string)
  description = "Extra arguments for the kvisor controller. Optionally enable kvisor to lint Kubernetes YAML manifests, scan workload images and check if workloads pass CIS Kubernetes Benchmarks as well as NSA, WASP and PCI recommendations."
  default = {
    "max_cores"    = 100
    "min_cores"    = 1
  }
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

variable "self_managed" {
  type        = bool
  default     = false
  description = "Whether CAST AI components' upgrades are managed by a customer; by default upgrades are managed CAST AI central system."
}

variable "gke_cluster_version" {
  description = "The Kubernetes version of the masters. Defaults to the latest available version in the selected region"
  type        = string
  default     = "latest"
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

variable "install_evictor_agent" {
  type        = bool
  default     = false
  description = "Optional flag for installation of evictor agent (https://docs.cast.ai/product-overview/console/security-insights/)"
}

variable "evictor_aggressive_mode" {
  type        = bool
  default     = false
  description = "Allow evictor to consider single replica applications (https://docs.cast.ai/product-overview/console/security-insights/)"
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

variable "install_spothandler_agent" {
  type        = bool
  default     = false
  description = "Optional flag for installation of spothandler agent (https://docs.cast.ai/product-overview/console/security-insights/)"
}

variable "install_egressd_agent" {
  type        = bool
  default     = false
  description = "Optional flag for installation of egressd for monitoring network costs (https://docs.cast.ai/docs/network-cost)"
}

variable "install_audit_logs_receiver" {
  type        = bool
  default     = false
  description = "Optional flag for installation of the audit log receiver (https://docs.cast.ai/docs/audit-log-exporter)"
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

variable "egressd_values" {
  description = "List of YAML formatted string with egressd values"
  type        = list(string)
  default     = []
}

variable "egressd_version" {
  description = "Version of egressd chart. Default latest"
  type        = string
  default     = null
}

variable "audit_log_receiver_values" {
  description = "List of YAML formatted string with audit-log-receiver values"
  type        = list(string)
  default     = []
}

variable "audit_log_receiver_version" {
  description = "Version of audit-log-receiver chart. Default latest"
  type        = string
  default     = null
}

variable "pod_pinner_version" {
  description = "Version of pod-pinner chart. Default latest"
  type        = string
  default     = null
}

variable "install_precision_packer" {
  type        = bool
  default     = false
  description = "Optional flag for installation of the precision packer (https://docs.cast.ai/docs/pod-pinner)"
}
