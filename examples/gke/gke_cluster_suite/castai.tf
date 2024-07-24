

# Configure Data sources and providers required for CAST AI connection.
provider "castai" {
  api_token = var.castai_api_token
  api_url   = var.castai_api_url
}

provider "helm" {
  kubernetes {
    host                   = "https://${module.gke.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(module.gke.ca_certificate)
    config_path            = "~/.kube/config"
  }
}

module "castai-gke-iam" {
  source = "castai/gke-iam/castai"

  project_id       = var.project_id
  gke_cluster_name = var.cluster_name
  service_accounts_unique_ids = length(var.service_accounts_unique_ids) == 0 ? [] : var.service_accounts_unique_ids
}

# Configure GKE cluster connection to CAST AI in read-only mode.
resource "castai_gke_cluster" "this" {
  project_id = var.project_id
  location   = module.gke.location
  name       = var.cluster_name
  delete_nodes_on_disconnect = var.delete_nodes_on_disconnect

  credentials_json = var.readonly ? null : module.castai-gke-iam.private_key
}

resource "helm_release" "castai_agent" {
  name             = "castai-agent"
  repository       = "https://castai.github.io/helm-charts"
  chart            = "castai-agent"
  namespace        = "castai-agent"
  create_namespace = true
  cleanup_on_fail  = true

  set {
    name  = "provider"
    value = "gke"
  }
  set_sensitive {
    name  = "apiKey"
    value = castai_gke_cluster.this.cluster_token
  }

  # required until https://github.com/castai/helm-charts/issues/135 is fixed.
  set {
    name  = "createNamespace"
    value = "false"
  }
}

resource "castai_node_configuration" "default" {
  count      = var.readonly ? 0 : 1
  cluster_id = castai_gke_cluster.this.id

  name           = "default"
  disk_cpu_ratio = 0
  min_disk_size  = 100
  subnets        = [module.vpc.subnets_ids[0]] # var.subnets
}

resource "castai_node_configuration_default" "this" {
  count            = var.readonly ? 0 : 1
  cluster_id       = castai_gke_cluster.this.id
  configuration_id = castai_node_configuration.default[0].id
}

resource "helm_release" "castai_cluster_controller" {
  count            = var.readonly ? 0 : 1
  name             = "cluster-controller"
  repository       = "https://castai.github.io/helm-charts"
  chart            = "castai-cluster-controller"
  namespace        = "castai-agent"
  create_namespace = true
  cleanup_on_fail  = true
  wait             = true

  set {
    name  = "castai.clusterID"
    value = castai_gke_cluster.this.id
  }
  
  set {
    name = "additionalEnv.LOG_LEVEL"
    value = var.castai_log_level
  }

  dynamic "set" {
    for_each = var.castai_api_url != "" ? [var.castai_api_url] : []
    content {
      name  = "castai.apiURL"
      value = var.castai_api_url
    }
  }

  set_sensitive {
    name  = "castai.apiKey"
    value = castai_gke_cluster.this.cluster_token
  }

  depends_on = [helm_release.castai_agent]

  lifecycle {
    ignore_changes = [version]
  }
}

resource "castai_autoscaler" "castai_autoscaler_policies" {
  count      = var.readonly ? 0 : 1
  cluster_id = castai_gke_cluster.this.id

  autoscaler_settings {
    enabled = var.autoscaler_enabled
    node_templates_partial_matching_enabled = false

    unschedulable_pods {
      enabled = var.autoscaler_enabled
    }

    node_downscaler {
      enabled = true

      empty_nodes {
        enabled = true
      }

      evictor {
        aggressive_mode           = var.evictor_aggressive_mode
        cycle_interval            = "5m10s"
        dry_run                   = false
        enabled                   = var.install_evictor_agent
        node_grace_period_minutes = 10
        scoped_mode               = false
      }
    }

    cluster_limits {
      enabled = var.autoscaler_limits_enabled

      dynamic "cpu" {
        for_each = var.autoscaler_cpu_limits != "" ? [var.autoscaler_cpu_limits] : []
        content {
          min_cores = cpu.value["min_cores"]
          max_cores = cpu.value["max_cores"]
        }
      }
    }
  }

  depends_on = [helm_release.castai_agent]
}

resource "castai_node_template" "default_by_castai" {
  count            = var.readonly ? 0 : 1
  name             = "default-by-castai"
  cluster_id       = castai_gke_cluster.this.id
  configuration_id = castai_node_configuration.default[0].id
  cluster_id       = castai_gke_cluster.this.id
  is_default       = true
  is_enabled       = true
  should_taint     = false

  constraints {
    on_demand          = true
    spot               = true
    use_spot_fallbacks = true

    enable_spot_diversity                       = false
    spot_diversity_price_increase_limit_percent = 20
    storage_optimized_state = "disabled"
    compute_optimized_state = ""
  }
}

resource "castai_node_template" "spot_tmpl" {
  count            = var.readonly ? 0 : 1
  name             = "spot-tmpl"
  # cluster_id       = castai_gke_cluster.this.id
  configuration_id = castai_node_configuration.default[0].id
  cluster_id       = castai_gke_cluster.this.id
  is_default       = false
  is_enabled       = true
  should_taint     = true

  custom_labels = {
    "cloud.google.com/gke-spot" = "true"
  }

  constraints {
    spot    = true
  }

  custom_taints {
      key    = "cloud.google.com/gke-spot"
      value  = "true"
      effect = "NoSchedule"
  }

  depends_on = [castai_autoscaler.castai_autoscaler_policies]
}

resource "helm_release" "castai_kvisor" {
  count = var.install_security_agent && !var.self_managed ? 1 : 0

  name             = "castai-kvisor"
  repository       = "https://castai.github.io/helm-charts"
  chart            = "castai-kvisor"
  namespace        = "castai-agent"
  create_namespace = true
  cleanup_on_fail  = true

  values  = var.kvisor_values
  version = var.kvisor_version

  lifecycle {
    ignore_changes = [version]
  }

  set {
    name  = "castai.clusterid"
    value = castai_gke_cluster.this.id
  }

  set_sensitive {
    name  = "castai.apiKey"
    value = castai_gke_cluster.this.cluster_token
  }

  set {
    name  = "castai.grpcaddr"
    value = var.api_grpc_addr
  }

  dynamic "set" {
    for_each = var.kvisor_controller_extra_args
    content {
      name  = "controller.extraArgs.${set.key}"
      value = set.value
    }
  }

  set {
    name  = "controller.extraArgs.kube-bench-cloud-provider"
    value = "gke"
  }

  depends_on = [helm_release.castai_agent]
}

resource "helm_release" "castai_pod_pinner" {
  count = var.install_precision_packer && !var.self_managed ? 1 : 0

  name             = "castai-pod-pinner"
  repository       = "https://castai.github.io/helm-charts"
  chart            = "castai-pod-pinner"
  namespace        = "castai-agent"
  create_namespace = true
  cleanup_on_fail  = true
  wait             = true

  version = var.pod_pinner_version

  set {
    name  = "castai.clusterID"
    value = castai_gke_cluster.this.id
  }

  dynamic "set" {
    for_each = var.castai_api_url != "" ? [var.castai_api_url] : []
    content {
      name  = "castai.apiURL"
      value = var.castai_api_url
    }
  }

  set_sensitive {
    name  = "castai.apiKey"
    value = castai_gke_cluster.this.cluster_token
  }

  dynamic "set" {
    for_each = var.api_grpc_addr != "" ? [var.api_grpc_addr] : []
    content {
      name  = "castai.grpcURL"
      value = var.api_grpc_addr
    }
  }

  depends_on = [helm_release.castai_agent]

  lifecycle {
    ignore_changes = [set, version]
  }
}

resource "helm_release" "castai_pod_pinner_self_managed" {
  count = var.install_precision_packer && var.self_managed ? 1 : 0

  name             = "castai-pod-pinner"
  repository       = "https://castai.github.io/helm-charts"
  chart            = "castai-pod-pinner"
  namespace        = "castai-agent"
  create_namespace = true
  cleanup_on_fail  = true
  wait             = true

  version = var.pod_pinner_version

  set {
    name  = "castai.clusterID"
    value = castai_gke_cluster.this.id
  }

  dynamic "set" {
    for_each = var.castai_api_url != "" ? [var.castai_api_url] : []
    content {
      name  = "castai.apiURL"
      value = var.castai_api_url
    }
  }

  set_sensitive {
    name  = "castai.apiKey"
    value = castai_gke_cluster.this.cluster_token
  }

  dynamic "set" {
    for_each = var.api_grpc_addr != "" ? [var.api_grpc_addr] : []
    content {
      name  = "castai.grpcURL"
      value = var.api_grpc_addr
    }
  }

  depends_on = [helm_release.castai_agent]
}

resource "helm_release" "castai_kvisor_self_managed" {
  count = var.install_security_agent && var.self_managed ? 1 : 0

  name             = "castai-kvisor"
  repository       = "https://castai.github.io/helm-charts"
  chart            = "castai-kvisor"
  namespace        = "castai-agent"
  create_namespace = true
  cleanup_on_fail  = true

  values  = var.kvisor_values
  version = var.kvisor_version

  set {
    name  = "castai.clusterid"
    value = castai_gke_cluster.this.id
  }

  set_sensitive {
    name  = "castai.apiKey"
    value = castai_gke_cluster.this.cluster_token
  }

  set {
    name  = "castai.grpcaddr"
    value = var.api_grpc_addr
  }

  dynamic "set" {
    for_each = var.kvisor_controller_extra_args
    content {
      name  = "controller.extraArgs.${set.key}"
      value = set.value
    }
  }

  set {
    name  = "controller.extraArgs.kube-bench-cloud-provider"
    value = "gke"
  }

  depends_on = [helm_release.castai_agent]
}

resource "helm_release" "castai_evictor_self_managed" {
  count = var.install_evictor_agent && var.self_managed ? 1 : 0

  name             = "castai-evictor"
  repository       = "https://castai.github.io/helm-charts"
  chart            = "castai-evictor"
  namespace        = "castai-agent"
  create_namespace = true
  cleanup_on_fail  = true

  values  = var.evictor_values
  version = var.evictor_version

  lifecycle {
    ignore_changes = [version]
  }

  set {
    name = "managedByCASTAI"
    value = false
  }

  set {
    name = "scopedMode"
    value = false
  }

  depends_on = [helm_release.castai_agent]
}

resource "helm_release" "castai_spothandler_self_managed" {
  count = var.install_spothandler_agent && var.self_managed ? 1 : 0

  name             = "castai-spot-handler"
  repository       = "https://castai.github.io/helm-charts"
  chart            = "castai-spot-handler"
  namespace        = "castai-agent"
  create_namespace = true
  cleanup_on_fail  = true

  values  = var.spothandler_values
  version = var.spothandler_version

  lifecycle {
    ignore_changes = [version]
  }

  set {
    name  = "castai.provider"
    value = "gke"
  }

  set {
    name  = "castai.clusterID"
    value = castai_gke_cluster.this.id
  }

  set_sensitive {
    name  = "apiKey"
    value = castai_gke_cluster.this.cluster_token
  }

  depends_on = [helm_release.castai_agent]
}

resource "helm_release" "castai-egressd" {
  count = var.install_egressd_agent && var.self_managed ? 1 : 0

  name             = "castai-egressd"
  repository       = "https://castai.github.io/helm-charts"
  chart            = "egressd"
  namespace        = "castai-agent"
  create_namespace = true
  cleanup_on_fail  = true

  values  = var.egressd_values
  version = var.egressd_version

  lifecycle {
    ignore_changes = [version]
  }

  set_sensitive {
    name  = "castai.apiKey"
    value = castai_gke_cluster.this.cluster_token
  }

  set {
    name  = "castai.clusterID"
    value = castai_gke_cluster.this.id
  }


  depends_on = [helm_release.castai_agent, helm_release.castai_cluster_controller]
}

resource "helm_release" "castai_audit_logs_receiver" {
  count = var.install_audit_logs_receiver && var.self_managed ? 1 : 0

  name             = "castai-audit-logs-receiver"
  repository       = "https://castai.github.io/helm-charts"
  chart            = "castai-audit-logs-receiver"
  namespace        = "castai-agent"
  create_namespace = true
  cleanup_on_fail  = true

  values  = var.audit_log_receiver_values
  version = var.audit_log_receiver_version

  lifecycle {
    ignore_changes = [version]
  }

  set_sensitive {
    name  = "castai.apiKey"
    value = castai_gke_cluster.this.cluster_token
  }

  depends_on = [helm_release.castai_agent, helm_release.castai_cluster_controller]
}
