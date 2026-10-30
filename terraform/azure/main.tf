# The Azure Docker host, its off-site backup storage, and the alerts that watch its cost and health.
# Ansible's docker_host role configures the VM; nothing here runs on it.

data "azurerm_subscription" "current" {}

# Created by the bootstrap stack, which scopes the apply identity's Contributor role to it
data "azurerm_resource_group" "prod" {
  name = "quantaid-prod"
}

# --- Cost and alerts. Applied first, before anything costs money. ---

resource "azurerm_monitor_action_group" "alerts" {
  name                = "quantaid-alerts"
  resource_group_name = data.azurerm_resource_group.prod.name
  short_name          = "quantaid"

  email_receiver {
    name                    = "owner"
    email_address           = var.alert_email
    use_common_alert_schema = true
  }
}

resource "azurerm_consumption_budget_subscription" "monthly" {
  name            = "quantaid-monthly"
  subscription_id = data.azurerm_subscription.current.id
  amount          = var.monthly_budget_usd
  time_grain      = "Monthly"

  time_period {
    start_date = var.budget_start_date
  }

  notification {
    threshold      = 50
    threshold_type = "Actual"
    operator       = "GreaterThanOrEqualTo"
    contact_emails = [var.alert_email]
  }

  notification {
    threshold      = 100
    threshold_type = "Actual"
    operator       = "GreaterThanOrEqualTo"
    contact_emails = [var.alert_email]
  }

  notification {
    threshold      = 100
    threshold_type = "Forecasted"
    operator       = "GreaterThanOrEqualTo"
    contact_emails = [var.alert_email]
  }
}

# --- Network ---

resource "azurerm_virtual_network" "main" {
  name                = "quantaid-vnet"
  resource_group_name = data.azurerm_resource_group.prod.name
  location            = data.azurerm_resource_group.prod.location
  # Doesn't overlap the home LAN (10.67.1.0/24) or the VMware lab network (192.168.111.0/24)
  address_space = ["10.68.0.0/24"]
}

resource "azurerm_subnet" "main" {
  name                 = "quantaid-subnet"
  resource_group_name  = data.azurerm_resource_group.prod.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.68.0.0/24"]
  # New subnets are private: Azure retired default outbound access on 2026-03-31. The VM reaches Cloudflare,
  # GHCR and Atlas through its own public IP.
  default_outbound_access_enabled = false
}

resource "azurerm_network_security_group" "main" {
  name                = "quantaid-nsg"
  resource_group_name = data.azurerm_resource_group.prod.name
  location            = data.azurerm_resource_group.prod.location
}

# SSH from your home IP only. Nothing else comes in: cloudflared connects out.
resource "azurerm_network_security_rule" "ssh" {
  name                        = "ssh-from-home"
  resource_group_name         = data.azurerm_resource_group.prod.name
  network_security_group_name = azurerm_network_security_group.main.name
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_address_prefix       = var.admin_cidr
  source_port_range           = "*"
  destination_address_prefix  = "*"
  destination_port_range      = "22"
}

resource "azurerm_subnet_network_security_group_association" "main" {
  subnet_id                 = azurerm_subnet.main.id
  network_security_group_id = azurerm_network_security_group.main.id
}

resource "azurerm_public_ip" "host" {
  name                = "quantaid-azure-ip"
  resource_group_name = data.azurerm_resource_group.prod.name
  location            = data.azurerm_resource_group.prod.location
  sku                 = "Standard"
  allocation_method   = "Static"
  # quantaid-azure.<region>.cloudapp.azure.com, the name Ansible's inventory uses
  domain_name_label = "quantaid-azure"
}

resource "azurerm_network_interface" "host" {
  name                = "quantaid-azure-nic"
  resource_group_name = data.azurerm_resource_group.prod.name
  location            = data.azurerm_resource_group.prod.location

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.host.id
  }
}

# --- The VM ---

resource "azurerm_linux_virtual_machine" "host" {
  name                = "quantaid-azure"
  resource_group_name = data.azurerm_resource_group.prod.name
  location            = data.azurerm_resource_group.prod.location
  # 1 vCPU, 1 GiB: free for the first 12 months. Ansible adds a 2 GB swap file.
  size                            = "Standard_B1s"
  network_interface_ids           = [azurerm_network_interface.host.id]
  admin_username                  = "anb"
  disable_password_authentication = true
  # No custom_data: Ansible does all the setup, and custom data is stored in plain text

  admin_ssh_key {
    username   = "anb"
    public_key = var.admin_ssh_public_key
  }

  os_disk {
    caching = "ReadWrite"
    # A 64 GB Premium SSD is the free P6
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 64
  }

  # Rocky 9, like the laptop, from the Rocky project's own images
  source_image_reference {
    publisher = "resf"
    offer     = "rockylinux-x86_64"
    sku       = "9-base"
    version   = "latest"
  }

  # Managed storage for the serial log, which shows why a VM won't boot
  boot_diagnostics {}
}

resource "azurerm_monitor_metric_alert" "host_unavailable" {
  name                = "quantaid-azure-unavailable"
  resource_group_name = data.azurerm_resource_group.prod.name
  scopes              = [azurerm_linux_virtual_machine.host.id]
  description         = "The Azure VM is down. Its boot diagnostics in the portal show the serial log."
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "VmAvailabilityMetric"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 1
  }

  action {
    action_group_id = azurerm_monitor_action_group.alerts.id
  }
}

# A B-series VM runs at a low baseline once its burst credits are used up
resource "azurerm_monitor_metric_alert" "host_cpu_credits" {
  name                = "quantaid-azure-cpu-credits-low"
  resource_group_name = data.azurerm_resource_group.prod.name
  scopes              = [azurerm_linux_virtual_machine.host.id]
  description         = "The Azure VM is nearly out of CPU credits and will slow down. Check docker stats and top on it."
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "CPU Credits Remaining"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 30
  }

  action {
    action_group_id = azurerm_monitor_action_group.alerts.id
  }
}

# --- Off-site backups: every Docker host uploads its daily dump here ---

resource "azurerm_storage_account" "backups" {
  name                            = var.backup_storage_account
  resource_group_name             = data.azurerm_resource_group.prod.name
  location                        = data.azurerm_resource_group.prod.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  # Keys stay on: the hosts' upload SAS is signed with one, so revoking it means rotating that key
}

resource "azurerm_storage_container" "backups" {
  name                  = "mongo-backups"
  storage_account_id    = azurerm_storage_account.backups.id
  container_access_type = "private"
}

# Nobody can delete or overwrite a backup for 14 days, even with a leaked credential. Unlocked until a restore has
# been tested: a locked policy can never be shortened or removed.
resource "azurerm_storage_container_immutability_policy" "backups" {
  storage_container_resource_manager_id = azurerm_storage_container.backups.id
  immutability_period_in_days           = 14
}

resource "azurerm_storage_management_policy" "backups" {
  storage_account_id = azurerm_storage_account.backups.id

  rule {
    name    = "delete-after-30-days"
    enabled = true

    filters {
      prefix_match = ["mongo-backups/"]
      blob_types   = ["blockBlob"]
    }

    actions {
      base_blob {
        delete_after_days_since_creation_greater_than = 30
      }
    }
  }
}
