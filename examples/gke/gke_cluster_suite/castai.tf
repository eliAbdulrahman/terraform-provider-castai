# 3. Connect GKE cluster to CAST AI in read-only mode.

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
    value = castai_gke_cluster.this.cluster_token # var.castai_api_token
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
  subnets        = var.subnets
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
    value = var.castai_api_token
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
    name  = "controller.extraargs.kube-bench-cloud-provider"
    value = "gke"
  }

  depends_on = [helm_release.castai_agent]
}

# resource "helm_release" "castai_pod_pinner" {
#   count = var.self_managed ? 0 : 1
# 
#   name             = "castai-pod-pinner"
#   repository       = "https://castai.github.io/helm-charts"
#   chart            = "castai-pod-pinner"
#   namespace        = "castai-agent"
#   create_namespace = true
#   cleanup_on_fail  = true
#   wait             = true
# 
#   version = var.pod_pinner_version
# 
#   set {
#     name  = "castai.clusterID"
#     value = castai_gke_cluster.castai_cluster.id
#   }
# 
#   dynamic "set" {
#     for_each = var.api_url != "" ? [var.api_url] : []
#     content {
#       name  = "castai.apiURL"
#       value = var.api_url
#     }
#   }
# 
#   set_sensitive {
#     name  = "castai.apiKey"
#     value = castai_gke_cluster.castai_cluster.cluster_token
#   }
# 
#   dynamic "set" {
#     for_each = var.grpc_url != "" ? [var.grpc_url] : []
#     content {
#       name  = "castai.grpcURL"
#       value = var.grpc_url
#     }
#   }
# 
#   dynamic "set" {
#     for_each = var.castai_components_labels
#     content {
#       name  = "podLabels.${set.key}"
#       value = set.value
#     }
#   }
# 
#   set {
#     name  = "replicaCount"
#     value = "0"
#   }
# 
#   depends_on = [helm_release.castai_agent]
# 
#   lifecycle {
#     ignore_changes = [set, version]
#   }
# }

# resource "helm_release" "castai_pod_pinner_self_managed" {
#   count = var.self_managed ? 1 : 0
# 
#   name             = "castai-pod-pinner"
#   repository       = "https://castai.github.io/helm-charts"
#   chart            = "castai-pod-pinner"
#   namespace        = "castai-agent"
#   create_namespace = true
#   cleanup_on_fail  = true
#   wait             = true
# 
#   version = var.pod_pinner_version
# 
#   set {
#     name  = "castai.clusterID"
#     value = castai_gke_cluster.castai_cluster.id
#   }
# 
#   dynamic "set" {
#     for_each = var.api_url != "" ? [var.api_url] : []
#     content {
#       name  = "castai.apiURL"
#       value = var.api_url
#     }
#   }
# 
#   set_sensitive {
#     name  = "castai.apiKey"
#     value = castai_gke_cluster.castai_cluster.cluster_token
#   }
# 
#   dynamic "set" {
#     for_each = var.grpc_url != "" ? [var.grpc_url] : []
#     content {
#       name  = "castai.grpcURL"
#       value = var.grpc_url
#     }
#   }
# 
#   dynamic "set" {
#     for_each = var.castai_components_labels
#     content {
#       name  = "podLabels.${set.key}"
#       value = set.value
#     }
#   }
# 
#   set {
#     name  = "replicaCount"
#     value = "0"
#   }
# 
#   depends_on = [helm_release.castai_agent]
# }

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
    # value = castai_gke_cluster.this.cluster_token
    value = var.castai_api_token
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
    name  = "controller.extraargs.kube-bench-cloud-provider"
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
    value = var.castai_api_token
  }

  depends_on = [helm_release.castai_agent]
}
