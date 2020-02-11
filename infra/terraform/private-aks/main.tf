terraform {
  required_version = ">= 0.12" 
  backend "azurerm" {
      storage_account_name = "__terraformstorageaccount__"
      container_name       = "terraform"
      key                  = "terraform.tfstate"
      access_key  ="__storagekey__"
  }
}

# Create Resource Group
resource "azurerm_resource_group" "k8s" {
  name      = local.rg_name
  location  = var.location
  tags = merge(
    local.common_tags, 
    {
        display_name = "App AKS Resource Group"
    }
    )
}

resource "azurerm_virtual_network" "k8s" {
  name                = local.vnet_name
  location            = azurerm_resource_group.k8s.location
  resource_group_name = azurerm_resource_group.k8s.name
  address_space       = ["192.168.0.0/16"]

  tags = merge(
    local.common_tags, 
    {
        display_name = "AKS Virtual Network"
    }
  )
}

resource "azurerm_subnet" "proxy" {
  name                 = "proxy-subnet"
  resource_group_name  = azurerm_resource_group.k8s.name
  virtual_network_name = azurerm_virtual_network.k8s.name
  address_prefix       = "192.168.0.0/24"

  enforce_private_link_service_network_policies = true
}

resource "azurerm_subnet" "default" {
  name                 = "aks-subnet"
  resource_group_name  = azurerm_resource_group.k8s.name
  virtual_network_name = azurerm_virtual_network.k8s.name
  address_prefix       = "192.168.1.0/24"
  
  service_endpoints = [
    "Microsoft.ContainerRegistry"
  ]
}

resource "random_id" "log_analytics_workspace_name_suffix" {
    byte_length = 8
}

resource "azurerm_log_analytics_workspace" "monitor" {
  # The WorkSpace name has to be unique across the whole of azure, not just the current subscription/tenant.
  name                = "${local.log_analytics_workspace_name}-${random_id.log_analytics_workspace_name_suffix.dec}"
  location            = azurerm_resource_group.k8s.location
  resource_group_name = azurerm_resource_group.k8s.name
  sku                 = local.log_analytics_workspace_sku

  tags = merge(
    local.common_tags, 
    {
        display_name = "Log Analitics Workspace for Container Insights"
    }
  )
}


resource "azurerm_log_analytics_solution" "monitor" {
  solution_name         = "ContainerInsights"
  location              = azurerm_log_analytics_workspace.monitor.location
  resource_group_name   = azurerm_resource_group.k8s.name
  workspace_resource_id = azurerm_log_analytics_workspace.monitor.id
  workspace_name        = azurerm_log_analytics_workspace.monitor.name

  plan {
      publisher = "Microsoft"
      product   = "OMSGallery/ContainerInsights"
  }
}

resource "azurerm_container_registry" "acr" {
  name                     = local.acr_name
  resource_group_name      = azurerm_resource_group.k8s.name
  location                 = azurerm_resource_group.k8s.location
  sku                      = "Premium"

  network_rule_set {
    default_action = "Deny"

    virtual_network {
      action = "Allow"
      subnet_id = azurerm_subnet.default.id
    }
    
    virtual_network {
      action = "Allow"
      subnet_id = var.ado_subnet_id
    }
  }

  tags = merge(
    local.common_tags, 
    {
        display_name = "Azure Container Registry"
    }
  )
}

resource "azurerm_kubernetes_cluster" "k8s" {
  name                = local.aks_name
  resource_group_name = azurerm_resource_group.k8s.name
  location            = azurerm_resource_group.k8s.location
  dns_prefix          = local.aks_dns_prefix

  default_node_pool {
    name       = "default"
    node_count = local.aks_node_count
    vm_size    = "Standard_D2_v3"

    vnet_subnet_id = azurerm_subnet.default.id
  }

  service_principal {
    client_id     = var.aks_service_principal_client_id
    client_secret = var.aks_service_principal_client_secret
  }

  private_link_enabled = true

  network_profile {
    network_plugin = "kubenet"
    load_balancer_sku = "standard"

    docker_bridge_cidr = "172.17.0.1/16"
    pod_cidr = "10.244.0.0/16"
    service_cidr = "10.0.0.0/16"
    dns_service_ip = "10.0.0.10"
  }

  addon_profile {
    oms_agent {
      enabled                    = true
      log_analytics_workspace_id = azurerm_log_analytics_workspace.monitor.id
    }

    kube_dashboard {
      enabled = true
    }
  }

  tags = merge(
    local.common_tags, 
    {
        display_name = "AKS Cluster"
    }
  )
}

# resource "azurerm_role_assignment" "acr" {
#   scope                = azurerm_container_registry.acr.id
#   role_definition_name = "acrpull"
#   principal_id         = var.aks_service_principal_client_id
# }

data "azurerm_lb" "k8s" {
  name                = "kubernetes"
  resource_group_name = local.aks_rg_name

  depends_on = [
    azurerm_kubernetes_cluster.k8s
  ]
}

# resource "azurerm_private_endpoint" "pe" {
#   name                = local.aks_private_link_endpoint_name
#   location            = azurerm_resource_group.k8s.location
#   resource_group_name = azurerm_resource_group.k8s.name

#   subnet_id           = var.bastion_subnet_id
  
#   private_service_connection {
#     is_manual_connection = false
#     name = local.aks_private_link_endpoint_name
#     private_connection_resource_id = azurerm_kubernetes_cluster.k8s.id
#     subresource_names = ["management"]
#   }
# }

# resource "azurerm_private_link_service" "pls" {
#   name                = local.aks_private_link_service_name
#   location            = azurerm_resource_group.k8s.location
#   resource_group_name = azurerm_resource_group.k8s.name
  
#   nat_ip_configuration {
#     name               = "nat-config"
#     subnet_id          = azurerm_subnet.proxy.id
#     primary            = true
#   }

#   load_balancer_frontend_ip_configuration_ids = [data.azurerm_lb.k8s.frontend_ip_configuration.0.id] 

#   tags = merge(
#     local.common_tags, 
#     {
#         display_name = "Private Link Service for AKS"
#     }
#   )
# }