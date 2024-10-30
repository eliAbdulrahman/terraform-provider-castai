# 2. Create AKS cluster.

resource "azurerm_kubernetes_cluster" "this" {
  name                = var.cluster_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  dns_prefix          = var.cluster_name
  node_resource_group = "${var.cluster_name}-ng"
  kubernetes_version  = "1.28"

  default_node_pool {
    name = "default"
    # Node count has to be > 2 to successfully deploy CAST AI controller.
    node_count     = 2
    vm_size        = "Standard_D2_v2"
    vnet_subnet_id = azurerm_subnet.internal.id
  }

  identity {
    type = "SystemAssigned"
  }

  tags = {
    Environment = "EA-Test"
  }
}

resource "azurerm_kubernetes_cluster_node_pool" "workloads" {
  name                      = "wrklddev"
  vm_size                   = "Standard_D2_v2"
  node_count                = 0
  auto_scaling_enabled      = false
  kubernetes_cluster_id     = azurerm_kubernetes_cluster.this.id
  zones                     = ["1", "2"]

  tags = {
    Environment = "EA-Test"
  }
}
