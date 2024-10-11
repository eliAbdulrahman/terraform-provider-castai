data "aws_caller_identity" "current" {}

resource "castai_eks_user_arn" "castai_user_arn" {
  cluster_id = castai_eks_clusterid.cluster_id.id
}

# Create AWS IAM policies and a user to connect to CAST AI.
module "castai-eks-role-iam" {
  source = "castai/eks-role-iam/castai"

  aws_account_id     = data.aws_caller_identity.current.account_id
  aws_cluster_region = var.cluster_region
  aws_cluster_name   = var.cluster_name
  aws_cluster_vpc_id = module.vpc.vpc_id

  castai_user_arn = castai_eks_user_arn.castai_user_arn.arn

  create_iam_resources_per_cluster = true
}

resource "castai_eks_cluster" "this" {
  account_id = data.aws_caller_identity.current.account_id
  region     = var.cluster_region
  name       = var.cluster_name

  delete_nodes_on_disconnect = var.delete_nodes_on_disconnect
  assume_role_arn            = var.readonly ? null : module.castai-eks-role-iam.role_arn
    
  // depends_on helps Terraform with creating proper dependencies graph in case of resource creation and in this case destroy.
  // module "castai-eks-cluster" has to be destroyed before module "castai-eks-role-iam".
  depends_on = [module.castai-eks-role-iam]
}

resource "helm_release" "castai_agent" {
  name             = "castai-agent"
  repository       = "https://castai.github.io/helm-charts"
  chart            = "castai-agent"
  namespace        = "castai-agent"
  create_namespace = true
  cleanup_on_fail  = true
  version          = "0.77.2" # From 0.68.3 to 0.77.2

  set {
    name  = "provider"
    value = "eks"
  }
  set_sensitive {
    name  = "apiKey"
    value = castai_eks_cluster.this.cluster_token
  }

  # Required until https://github.com/castai/helm-charts/issues/135 is fixed.
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

resource "castai_eks_clusterid" "cluster_id" {
  account_id   = data.aws_caller_identity.current.account_id
  region       = var.cluster_region
  cluster_name = var.cluster_name
}

resource "castai_node_configuration" "default" {
  count      = var.readonly ? 0 : 1
  cluster_id = castai_eks_cluster.this.id

  name           = "default"
  disk_cpu_ratio = 0
  min_disk_size  = 100
  subnets        = module.vpc.private_subnets
  eks {
    max_pods_per_node_formula = "8"
    security_groups = [
      module.eks.cluster_security_group_id,
      module.eks.node_security_group_id,
    ]
    instance_profile_arn = module.castai-eks-role-iam.instance_profile_arn
  }

  depends_on = [module.eks.cluster_endpoint]
}

resource "castai_node_configuration_default" "this" {
  count            = var.readonly ? 0 : 1
  cluster_id       = castai_eks_cluster.this.id
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
  version          = "0.61.0" # From 0.56.2 To 0.61.0

  set {
    name  = "castai.clusterID"
    value = castai_eks_cluster.this.id
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
    value = castai_eks_cluster.this.cluster_token
  }

  depends_on = [helm_release.castai_agent]

  lifecycle {
    ignore_changes = [version]
  }
}

resource "castai_autoscaler" "castai_autoscaler_policies" {
  count      = var.readonly ? 0 : 1
  cluster_id = castai_eks_cluster.this.id

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
        aggressive_mode           = var.evictor_aggressive_mode
        cycle_interval            = "5m10s"
        dry_run                   = false
        enabled                   = true
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

resource "castai_node_template" "default_by_castai" {
  count            = var.readonly ? 0 : 1
  name             = "default-by-castai"
  configuration_id = castai_node_configuration.default[0].id
  cluster_id       = castai_eks_cluster.this.id
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

  depends_on = [castai_autoscaler.castai_autoscaler_policies]
}

resource "castai_node_template" "spot_tmpl" {
  count            = var.readonly ? 0 : 1
  name             = "spot-tmpl"
  configuration_id = castai_node_configuration.default[0].id
  cluster_id       = castai_eks_cluster.this.id
  is_default       = false
  is_enabled       = true
  should_taint     = true

  custom_labels = {
    "eks.amazonaws.com/capacityType" = "SPOT"
  }

  constraints {
    spot    = true
  }

  custom_taints {
      key    = "eks.amazonaws.com/capacityType"
      value  = "SPOT"
      effect = "NoSchedule"
  }

  depends_on = [castai_autoscaler.castai_autoscaler_policies]
}

resource "helm_release" "castai_evictor" {
  count = var.install_evictor_agent && !var.readonly ? 0 : 1

  name             = "castai-evictor"
  repository       = "https://castai.github.io/helm-charts"
  chart            = "castai-evictor"
  namespace        = "castai-agent"
  create_namespace = true
  cleanup_on_fail  = true

  values  = var.evictor_values
  version = var.evictor_version

  set {
    name  = "provider"
    value = "eks"
  }

  set {
    name  = "replicasCount"
    value = 0 # 0 if not already deployed, 1 if upgrading
  }

  dynamic "set" {
    for_each = var.castai_api_url != "" ? [var.castai_api_url] : []
    content {
      name  = "apiURL"
      value = var.castai_api_url
    }
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

  set {
    name = "agent.enabled"
    value = "true"
  }

  set {
    name  = "castai.clusterID"
    value = castai_eks_cluster.this.id
  }

  set_sensitive {
    name  = "castai.apiKey"
    value = var.castai_api_token
  }

  set {
    name  = "castai.grpcAddr"
    value = var.api_grpc_addr
  }

  set {
    name  = "controller.extraArgs.kube-bench-cloud-provider"
    value = "eks"
  }

  dynamic "set" {
    for_each = var.kvisor_controller_extra_args
    content {
      name  = "controller.extraArgs.${set.key}"
      value = set.value
    }
  }

  dynamic "set" {
    for_each = var.kvisor_agent_extra_args
    content {
      name  = "agent.extraArgs.${set.key}"
      value = set.value
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
    name = "agent.enabled"
    value = "true"
  }

  set {
    name  = "castai.clusterID"
    value = castai_eks_cluster.this.id
  }

  set_sensitive {
    name  = "castai.apiKey"
    value = var.castai_api_token
  }


  set {
    name  = "castai.grpcAddr"
    value = var.api_grpc_addr
  }

  set {
    name  = "controller.extraArgs.kube-bench-cloud-provider"
    value = "eks"
  }

  dynamic "set" {
    for_each = var.kvisor_controller_extra_args
    content {
      name  = "controller.extraArgs.${set.key}"
      value = set.value
    }
  }

  dynamic "set" {
    for_each = var.kvisor_agent_extra_args
    content {
      name  = "agent.extraArgs.${set.key}"
      value = set.value
    }
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
    value = castai_eks_cluster.this.id
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
    value = castai_eks_cluster.this.cluster_token
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
    value = castai_eks_cluster.this.id
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
    value = castai_eks_cluster.this.cluster_token
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
    value = castai_eks_cluster.this.cluster_token
  }

  set {
    name  = "castai.clusterID"
    value = castai_eks_cluster.this.id
  }

  depends_on = [helm_release.castai_agent, helm_release.castai_cluster_controller]
}

resource "helm_release" "castai_workload_autoscaler" {
  count = var.woop_autoscaler_enabled && var.self_managed ? 1 : 0

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
    value = var.castai_api_token
  }

  depends_on = [helm_release.castai_agent, helm_release.castai_cluster_controller]
}
