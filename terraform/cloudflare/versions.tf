terraform {
  required_version = "~> 1.17"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.28"
    }
  }

  # Created by the bootstrap stack. Entra ID roles, not account keys.
  backend "azurerm" {
    resource_group_name  = "quantaid-tfstate"
    storage_account_name = "quantaidtfstate"
    container_name       = "tfstate"
    key                  = "cloudflare.tfstate"
    use_azuread_auth     = true
  }
}

# The API token comes from CLOUDFLARE_API_TOKEN
provider "cloudflare" {}
