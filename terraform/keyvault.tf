resource "azurerm_key_vault" "this" {
  name                = "${var.prefix}-kv-${local.suffix}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  # azurerm >= 4.4x: `enable_rbac_authorization` is deprecated in favour of this.
  rbac_authorization_enabled = true

  # Soft delete is always on; keep retention short for dev.
  soft_delete_retention_days = 7
  # Dev-friendly: purge protection OFF so the vault can be destroyed/purged
  # and its name reused. Turn this on for production (it cannot be turned off).
  purge_protection_enabled = false

  # The VM reads secrets over the public endpoint using its managed identity.
  public_network_access_enabled = true

  tags = var.tags
}

# The identity running Terraform must be able to write secrets.
resource "azurerm_role_assignment" "kv_deployer_secrets_officer" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Azure RBAC data-plane grants take a while to propagate.
resource "time_sleep" "kv_rbac_propagation" {
  create_duration = "60s"
  depends_on      = [azurerm_role_assignment.kv_deployer_secrets_officer]
}

# The VM's managed identity reads the secrets during ansible-pull runs.
resource "azurerm_role_assignment" "kv_vm_secrets_user" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_virtual_machine.this.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

# Limited special-char set: safe in YAML, shell, URLs and JDBC strings.
resource "random_password" "postgres" {
  length           = 32
  special          = true
  override_special = "-_.~"
  min_lower        = 2
  min_upper        = 2
  min_numeric      = 2
}

resource "random_password" "keycloak_admin" {
  length           = 24
  special          = true
  override_special = "-_.~"
  min_lower        = 2
  min_upper        = 2
  min_numeric      = 2
  min_special      = 1
}

resource "azurerm_key_vault_secret" "postgres_password" {
  name         = "postgres-password"
  value        = random_password.postgres.result
  key_vault_id = azurerm_key_vault.this.id
  depends_on   = [time_sleep.kv_rbac_propagation]
}

resource "azurerm_key_vault_secret" "keycloak_admin_password" {
  name         = "keycloak-admin-password"
  value        = random_password.keycloak_admin.result
  key_vault_id = azurerm_key_vault.this.id
  depends_on   = [time_sleep.kv_rbac_propagation]
}

resource "azurerm_key_vault_secret" "smtp_username" {
  name         = "smtp-username"
  value        = local.smtp_username
  key_vault_id = azurerm_key_vault.this.id
  depends_on   = [time_sleep.kv_rbac_propagation]
}

resource "azurerm_key_vault_secret" "smtp_password" {
  name         = "smtp-password"
  value        = azuread_application_password.smtp.value
  key_vault_id = azurerm_key_vault.this.id
  depends_on   = [time_sleep.kv_rbac_propagation]
}
