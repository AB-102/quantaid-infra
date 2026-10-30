terraform {
  required_version = "~> 1.17"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.12"
    }
  }
  # Local state, gitignored: this stack creates the storage the other stacks keep their state in
}

# The subscription comes from ARM_SUBSCRIPTION_ID
provider "azurerm" {
  features {}
  # Only this stack registers resource providers, because only it runs as the subscription's Owner.
  # Insights (action groups, metric alerts) and Consumption (budgets) are what the azure stack uses beyond the core set.
  resource_provider_registrations = "core"
  resource_providers_to_register  = ["Microsoft.Insights", "Microsoft.Consumption"]
  # The state account has its keys turned off
  storage_use_azuread = true
}
