output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "public_ip" {
  description = "VM public IP. Point your DNS A record here when using a custom domain."
  value       = azurerm_public_ip.this.ip_address
}

output "azure_fqdn" {
  description = "Azure-provided FQDN of the public IP."
  value       = azurerm_public_ip.this.fqdn
}

output "domain" {
  description = "FQDN Keycloak is served on."
  value       = local.domain
}

output "keycloak_url" {
  value = "https://${local.domain}"
}

output "keycloak_admin_console_url" {
  value = "https://${local.domain}/admin/"
}

output "keycloak_admin_username" {
  value = "admin"
}

output "keycloak_admin_password_command" {
  description = "Fetch the Keycloak bootstrap admin password from Key Vault."
  value       = "az keyvault secret show --vault-name ${azurerm_key_vault.this.name} --name keycloak-admin-password --query value -o tsv"
}

output "ssh_command" {
  value = "ssh ${var.admin_username}@${azurerm_public_ip.this.ip_address}"
}

output "bootstrap_log_hint" {
  description = "Where to look while the VM converges."
  value       = "sudo cloud-init status --long; sudo tail -f /var/log/ansible-pull.log; systemctl list-timers ansible-pull.timer"
}

output "key_vault_name" {
  value = azurerm_key_vault.this.name
}

output "key_vault_uri" {
  value = azurerm_key_vault.this.vault_uri
}

output "smtp_host" {
  value = local.smtp_host
}

output "smtp_port" {
  value = local.smtp_port
}

output "smtp_from" {
  value = local.smtp_from
}

output "communication_service_name" {
  value = azurerm_communication_service.this.name
}

output "vm_principal_id" {
  description = "Object ID of the VM's system-assigned managed identity."
  value       = azurerm_linux_virtual_machine.this.identity[0].principal_id
}
