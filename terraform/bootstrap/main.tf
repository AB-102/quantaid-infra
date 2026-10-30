# Applied once from the main PC, as the subscription's Owner: assigning roles needs Owner.
# Creates the state storage, the production resource group, and the two identities GitHub Actions logs in as.

data "azurerm_client_config" "current" {}

data "azurerm_subscription" "current" {}

locals {
  github_repo = "AB-102/quantaid-infra"
}

# --- State storage for the azure and cloudflare stacks ---

resource "azurerm_resource_group" "tfstate" {
  name     = "quantaid-tfstate"
  location = var.location
}

resource "azurerm_storage_account" "tfstate" {
  name                            = var.state_storage_account
  resource_group_name             = azurerm_resource_group.tfstate.name
  location                        = azurerm_resource_group.tfstate.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  # State holds secrets, so it's reached only through Entra ID roles, never with account keys
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true

  blob_properties {
    # Every state write keeps the previous version, so a bad state can be recovered
    versioning_enabled = true
  }
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"
}

# --- Production ---

# Created here, not in the azure stack, so the apply identity's Contributor role can be scoped to it
resource "azurerm_resource_group" "prod" {
  name     = "quantaid-prod"
  location = var.location
}

# --- GitHub Actions identities (quantaid-infra's terraform.yml). Federated credentials: no secrets to rotate. ---

resource "azurerm_user_assigned_identity" "plan" {
  name                = "quantaid-tf-plan"
  resource_group_name = azurerm_resource_group.tfstate.name
  location            = azurerm_resource_group.tfstate.location
}

resource "azurerm_federated_identity_credential" "plan" {
  name                      = "github-pull-requests"
  user_assigned_identity_id = azurerm_user_assigned_identity.plan.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = "repo:${local.github_repo}:pull_request"
}

resource "azurerm_user_assigned_identity" "apply" {
  name                = "quantaid-tf-apply"
  resource_group_name = azurerm_resource_group.tfstate.name
  location            = azurerm_resource_group.tfstate.location
}

# Only jobs in the terraform-apply environment, which waits for your approval
resource "azurerm_federated_identity_credential" "apply" {
  name                      = "github-terraform-apply"
  user_assigned_identity_id = azurerm_user_assigned_identity.apply.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = "repo:${local.github_repo}:environment:terraform-apply"
}

# --- Roles ---

# Owner can't read blob data, so you need this too to run the other stacks. A plan also writes: it takes the state lock.
resource "azurerm_role_assignment" "state" {
  for_each = {
    you   = { principal_id = data.azurerm_client_config.current.object_id, type = "User" }
    plan  = { principal_id = azurerm_user_assigned_identity.plan.principal_id, type = "ServicePrincipal" }
    apply = { principal_id = azurerm_user_assigned_identity.apply.principal_id, type = "ServicePrincipal" }
  }

  scope                = azurerm_storage_container.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value.principal_id
  principal_type       = each.value.type
}

resource "azurerm_role_assignment" "plan_reader" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.plan.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "apply_contributor" {
  scope                = azurerm_resource_group.prod.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.apply.principal_id
  principal_type       = "ServicePrincipal"
}

# The budget is on the subscription, outside the resource group
resource "azurerm_role_assignment" "apply_budget" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Cost Management Contributor"
  principal_id         = azurerm_user_assigned_identity.apply.principal_id
  principal_type       = "ServicePrincipal"
}
