# Azure Communication Services Email with an Azure-managed sender domain
# (<guid>.azurecomm.net), used by Keycloak over SMTP (smtp.azurecomm.net:587).

resource "azurerm_email_communication_service" "this" {
  name                = "${local.base_name}-email"
  resource_group_name = azurerm_resource_group.this.name
  data_location       = var.acs_data_location
  tags                = var.tags
}

resource "azurerm_email_communication_service_domain" "this" {
  name              = "AzureManagedDomain"
  email_service_id  = azurerm_email_communication_service.this.id
  domain_management = "AzureManaged"
  tags              = var.tags
}

resource "azurerm_communication_service" "this" {
  name                = "${local.base_name}-acs"
  resource_group_name = azurerm_resource_group.this.name
  data_location       = var.acs_data_location
  tags                = var.tags
}

resource "azurerm_communication_service_email_domain_association" "this" {
  communication_service_id = azurerm_communication_service.this.id
  email_service_domain_id  = azurerm_email_communication_service_domain.this.id
}

# --- SMTP authentication: an Entra app whose service principal has rights on
# --- the Communication Service. Username = "<acs name>.<app id>.<tenant id>",
# --- password = the app's client secret.

resource "azuread_application" "smtp" {
  display_name = "${local.base_name}-acs-smtp"
  owners       = [data.azuread_client_config.current.object_id]
}

resource "azuread_service_principal" "smtp" {
  client_id = azuread_application.smtp.client_id
  owners    = [data.azuread_client_config.current.object_id]
}

# Rotated (new secret + Key Vault update) on the first `terraform apply` after a
# year; ansible-pull then picks up the new value from Key Vault.
resource "time_rotating" "smtp_secret" {
  rotation_years = 1
}

resource "azuread_application_password" "smtp" {
  application_id = azuread_application.smtp.id
  display_name   = "keycloak-smtp"
  end_date       = timeadd(time_rotating.smtp_secret.rfc3339, "17520h") # +2 years

  rotate_when_changed = {
    rotation = time_rotating.smtp_secret.id
  }
}

resource "azurerm_role_assignment" "smtp_acs" {
  scope                = azurerm_communication_service.this.id
  role_definition_name = "Communication and Email Service Owner"
  principal_id         = azuread_service_principal.smtp.object_id
  principal_type       = "ServicePrincipal"
}

locals {
  smtp_username = join(".", [
    azurerm_communication_service.this.name,
    azuread_application.smtp.client_id,
    data.azuread_client_config.current.tenant_id,
  ])
}
