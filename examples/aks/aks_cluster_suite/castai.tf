# Setup readonly agent
resource "helm_release" "castai_agent" {
  name             = "castai-agent"
  repository       = "https://castai.github.io/helm-charts"
  chart            = "castai-agent"
  namespace        = "castai-agent"
  create_namespace = true
  cleanup_on_fail  = true

  set {
    name  = "provider"
    value = "aks"
  }
  set_sensitive {
    name  = "apiKey"
    value = var.castai_api_token
  }

  # required until https://github.com/castai/helm-charts/issues/135 is fixed.
  set {
    name  = "createNamespace"
    value = "false"
  }
  dynamic "set" {
    for_each = var.castai_api_url != "" ? [var.castai_api_url] : []
    content {
      name  = "apiURL"
      value = var.castai_api_url
    }
  }
}

resource "castai_autoscaler" "castai_autoscaler_policies" {
  count      = var.readonly ? 0 : 1
  cluster_id = castai_aks_cluster.this[0].id

  autoscaler_settings {
    enabled = var.autoscaler_enabled
    node_templates_partial_matching_enabled = false

    unschedulable_pods {
      enabled = true
    }

    node_downscaler {
      enabled = true

      empty_nodes {
        enabled = true
      }

      evictor {
        aggressive_mode           = false
        cycle_interval            = "5m10s"
        dry_run                   = false
        enabled                   = true
        node_grace_period_minutes = 10
        scoped_mode               = false
      }
    }
  }

  depends_on = [helm_release.castai_agent]
}


resource "castai_aks_cluster" "this" {
  count           = var.readonly ? 0 : 1
  name            = var.cluster_name

  region          = var.cluster_region
  subscription_id = data.azurerm_subscription.current.subscription_id
  tenant_id       = data.azurerm_subscription.current.tenant_id
  client_id       = var.readonly ? null : azuread_application.castai.client_id
  client_secret   = var.readonly ? null : azuread_application_password.castai.value

  node_resource_group        = azurerm_kubernetes_cluster.this.node_resource_group
  delete_nodes_on_disconnect = var.delete_nodes_on_disconnect
}


resource "castai_node_configuration" "default" {
  count          = var.readonly ? 0 : 1
  cluster_id     = castai_aks_cluster.this[0].id
  name           = "default"
  disk_cpu_ratio = 0
  min_disk_size  = 100
  subnets        = [azurerm_subnet.internal.id] # var.subnets

  aks {
    max_pods_per_node = 40
  }
}

resource "castai_node_configuration_default" "this" {
 count            = var.readonly ? 0 : 1
 cluster_id       = castai_aks_cluster.this[0].id
 configuration_id = castai_node_configuration.default[0].id
}

resource "castai_node_template" "spot_tmpl" {
  count            = var.readonly ? 0 : 1
  name             = "spot-tmpl"
  configuration_id = castai_node_configuration.default[0].id
  cluster_id       = castai_aks_cluster.this[0].id
  is_default       = false
  is_enabled       = true
  should_taint     = true
  custom_instances_enabled = true

  constraints {
    spot    = true
  }

  depends_on = [castai_autoscaler.castai_autoscaler_policies]
}

# Deploy phase 2 configuration
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
    value = castai_aks_cluster.this[0].id
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
    value = var.castai_api_token
  }

  depends_on = [helm_release.castai_agent]

  lifecycle {
    ignore_changes = [version]
  }
}

resource "helm_release" "castai_workload_autoscaler" {
  count            = var.woop_autoscaler_enabled && var.self_managed ? 1 : 0

  name             = "castai-workload-autoscaler"
  repository       = "https://castai.github.io/helm-charts"
  chart            = "castai-workload-autoscaler"
  namespace        = "castai-agent"
  create_namespace = true
  cleanup_on_fail  = true

  values  = var.workload_autoscaler_values
  version = var.workload_autoscaler_version

  lifecycle {
    ignore_changes = [version]
  }

  set_sensitive {
    name  = "castai.apiKey"
    value = var.castai_api_token
  }

  set {
    name  = "castai.clusterID"
    value = castai_aks_cluster.this[0].id
  }

  depends_on = [helm_release.castai_agent, helm_release.castai_cluster_controller]
}

resource "helm_release" "castai_pod_node_lifecycle" {
  count = var.install_pod_node_lifecycle && var.self_managed ? 1 : 0

  name             = "castai-pod-node-lifecycle"
  repository       = "https://castai.github.io/helm-charts"
  chart            = "castai-pod-node-lifecycle"
  namespace        = "castai-agent"
  create_namespace = true
  cleanup_on_fail  = true

  values  = var.pod_node_lifecycle_values
  version = var.pod_node_lifecycle_version

  lifecycle {
    ignore_changes = [version]
  }

  set {
    name = "staticConfig.preset"
    value = "allSpotExceptKubeSystem"
  }

  set_sensitive {
    name  = "api.key"
    value = var.castai_api_token
  }
  set {
    name  = "api.clusterId"
    value = castai_aks_cluster.this[0].id
  }

  depends_on = [helm_release.castai_agent, helm_release.castai_cluster_controller]
}

resource "helm_release" "castai_hibernate" {
  count = var.cluster_hibernate_enabled && var.self_managed ? 1 : 0

  name             = "castai-hibernate"
  repository       = "https://castai.github.io/helm-charts"
  chart            = "castai-hibernate"
  namespace        = "castai-agent"
  create_namespace = true
  cleanup_on_fail  = true

  values  = var.hibernate_values
  version = var.hibernate_version

  lifecycle {
    ignore_changes = [version]
  }

  set {
    name  = "cloud"
    value = "AKS"
  }

  set {
    name = "pauseCronSchedule"
    value = var.hibernate_pause_schedule
  }

  set {
    name = "resumeCronSchedule"
    value = var.hibernate_resume_schedule
  }

  set_sensitive {
    name  = "apiKey"
    value = var.castai_api_token
  }

  depends_on = [helm_release.castai_agent, helm_release.castai_cluster_controller]
}
