terraform {
  required_version = "~> 1.17"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.12"
    }
  }

  # Created by the bootstrap stack. Entra ID roles, not account keys.
  backend "azurerm" {
    resource_group_name  = "quantaid-tfstate"
    storage_account_name = "quantaidtfstate"
    container_name       = "tfstate"
    key                  = "azure.tfstate"
    use_azuread_auth     = true
  }
}

# The subscription comes from ARM_SUBSCRIPTION_ID
provider "azurerm" {
  features {}
  # The bootstrap stack registered what this stack uses; the CI identities aren't allowed to register
  resource_provider_registrations = "none"
}
