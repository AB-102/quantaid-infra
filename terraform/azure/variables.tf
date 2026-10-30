variable "admin_cidr" {
  description = "Your home IP as a /32. The only address allowed to SSH in."
  type        = string
}

variable "admin_ssh_public_key" {
  description = "The main PC's public key: the contents of ~/.ssh/id_ed25519.pub"
  type        = string
}

variable "alert_email" {
  description = "Where the budget and VM alerts go. A personal address, which outlives the school one."
  type        = string
}

variable "monthly_budget_usd" {
  description = "Monthly budget. Emails at 50% and 100% of actual spend, and 100% of forecast."
  type        = number
  default     = 5
}

variable "budget_start_date" {
  description = "The first of the current or a later month, e.g. 2026-11-01T00:00:00Z. Can't change once created."
  type        = string
}

variable "backup_storage_account" {
  description = "Globally unique storage account name for the backups"
  type        = string
  default     = "quantaidbackups"
}
