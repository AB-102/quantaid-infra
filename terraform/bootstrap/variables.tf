variable "location" {
  description = "Azure region for everything, e.g. eastus: the one nearest the production Atlas cluster"
  type        = string
}

variable "state_storage_account" {
  description = "Globally unique storage account name for the state. The azure and cloudflare backends name it too."
  type        = string
  default     = "quantaidtfstate"
}
