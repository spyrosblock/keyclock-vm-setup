resource "random_string" "suffix" {
  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false
}

locals {
  suffix    = random_string.suffix.result
  base_name = "${var.prefix}-${local.suffix}"
  dns_label = var.dns_label != "" ? var.dns_label : local.base_name

  # Keycloak FQDN: custom domain, or the Azure-provided public IP FQDN.
  domain = var.domain != "" ? var.domain : azurerm_public_ip.this.fqdn

  admin_ssh_public_key = trimspace(
    var.admin_ssh_public_key != "" ? var.admin_ssh_public_key : file(pathexpand(var.admin_ssh_public_key_path))
  )

  smtp_host = "smtp.azurecomm.net"
  smtp_port = 587
  smtp_from = "DoNotReply@${azurerm_email_communication_service_domain.this.from_sender_domain}"
}

resource "azurerm_resource_group" "this" {
  name     = "${var.prefix}-keycloak-rg"
  location = var.location
  tags     = var.tags
}
