resource "castai_aks_cluster" "this" {
  name = var.cluster_name

  region          = var.cluster_region
  subscription_id = data.azurerm_subscription.current.subscription_id
  tenant_id       = data.azurerm_subscription.current.tenant_id
  client_id       = azuread_application.castai.application_id
  client_secret   = azuread_application_password.castai.value

  node_resource_group        = azurerm_kubernetes_cluster.this.node_resource_group
  delete_nodes_on_disconnect = var.delete_nodes_on_disconnect

  timeouts {
    create = "10m"
  }

  depends_on = [
    azurerm_role_definition.castai,
    azurerm_role_assignment.castai_resource_group,
    azurerm_role_assignment.castai_node_resource_group,
    azurerm_role_assignment.castai_additional_resource_groups,
    azuread_application.castai,
    azuread_application_password.castai,
    azuread_service_principal.castai
  ]
}

resource "castai_node_configuration" "default" {
  count          = var.readonly ? 0 : 1
  cluster_id     = castai_aks_cluster.this.id
  name           = "default"
  disk_cpu_ratio = 0
  min_disk_size  = 100
  subnets        = var.subnets

  aks {
    max_pods_per_node = 40
  }
}

resource "castai_node_configuration_default" "this" {
 count            = var.readonly ? 0 : 1
 cluster_id       = castai_aks_cluster.this.id
 configuration_id = castai_node_configuration.default[0].id
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
    value = castai_aks_cluster.this.id
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
     value = castai_aks_cluster.this.id
   }
 
   set_sensitive {
     name  = "castai.apikey"
     value = var.castai_api_token
   }
 
   set {
     name  = "castai.grpcaddr"
     value = var.api_grpc_addr
   }
 
   set {
     name  = "controller.extraargs.kube-linter-enabled"
     value = "true"
   }
 
   set {
     name  = "controller.extraargs.image-scan-enabled"
     value = "true"
   }
 
   set {
     name  = "controller.extraargs.kube-bench-enabled"
     value = "true"
   }
 
   set {
     name  = "controller.extraargs.kube-bench-cloud-provider"
     value = "aks"
   }
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
    value = castai_aks_cluster.this.id
  }

  set_sensitive {
    name  = "castai.apikey"
    value = var.castai_api_token
  }

  set {
    name  = "castai.grpcaddr"
    value = var.api_grpc_addr
  }

  set {
    name  = "controller.extraargs.kube-linter-enabled"
    value = "true"
  }

  set {
    name  = "controller.extraargs.image-scan-enabled"
    value = "true"
  }

  set {
    name  = "controller.extraargs.kube-bench-enabled"
    value = "true"
  }

  set {
    name  = "controller.extraargs.kube-bench-cloud-provider"
    value = "aks"
  }

  depends_on = [helm_release.castai_kvisor]
}
 
 resource "helm_release" "castai_evictor" {
   count = var.install_evictor_agent && !var.self_managed ? 1 : 0
 
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
     name  = "castai.clusterid"
     value = castai_aks_cluster.this.id
   }
 
   set_sensitive {
     name  = "castai.apikey"
     value = var.castai_api_token
   }
 
   set {
     name  = "castai.grpcaddr"
     value = var.api_grpc_addr
   }
 
   set {
     name  = "controller.extraargs.kube-linter-enabled"
     value = "true"
   }
 
   set {
     name  = "controller.extraargs.image-scan-enabled"
     value = "true"
   }
 
   set {
     name  = "controller.extraargs.kube-bench-enabled"
     value = "true"
   }
 
   set {
     name  = "controller.extraargs.kube-bench-cloud-provider"
     value = "aks"
   }
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

  set {
    name  = "castai.clusterid"
    value = castai_aks_cluster.this.id
  }

  set_sensitive {
    name  = "castai.apikey"
    value = var.castai_api_token
  }

  set {
    name  = "castai.grpcaddr"
    value = var.api_grpc_addr
  }

  set {
    name  = "controller.extraargs.kube-linter-enabled"
    value = "true"
  }

  set {
    name  = "controller.extraargs.image-scan-enabled"
    value = "true"
  }

  set {
    name  = "controller.extraargs.kube-bench-enabled"
    value = "true"
  }

  set {
    name  = "controller.extraargs.kube-bench-cloud-provider"
    value = "aks"
  }

  depends_on = [helm_release.castai_evictor]
}
