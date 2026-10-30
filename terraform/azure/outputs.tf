output "host_fqdn" {
  description = "ansible_host for quantaid-azure in the Ansible inventory"
  value       = azurerm_public_ip.host.fqdn
}

output "host_ip" {
  description = "Add it to production Atlas's Network Access if that isn't 0.0.0.0/0"
  value       = azurerm_public_ip.host.ip_address
}

output "backup_container_url" {
  value = "${azurerm_storage_account.backups.primary_blob_endpoint}${azurerm_storage_container.backups.name}"
}
