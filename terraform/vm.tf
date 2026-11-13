locals {
  # Contract with the Ansible playbook: written to /etc/keycloak-setup/vars.yml.
  ansible_vars = {
    key_vault_name    = azurerm_key_vault.this.name
    domain            = local.domain
    letsencrypt_email = var.letsencrypt_email
    smtp_host         = local.smtp_host
    smtp_port         = local.smtp_port
    smtp_from         = local.smtp_from
    repo_url          = var.repo_url
    repo_branch       = var.repo_branch
  }

  cloud_init = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    vars_yaml   = yamlencode(local.ansible_vars)
    repo_url    = var.repo_url
    repo_branch = var.repo_branch
  })
}

# NOTE: custom_data is only consumed by cloud-init on first boot, and changing it
# forces VM replacement. Day-2 changes should normally go through the Ansible
# repo (ansible-pull re-runs every 30 min), not through cloud-init.
resource "azurerm_linux_virtual_machine" "this" {
  name                            = "${var.prefix}-keycloak-vm"
  computer_name                   = "${var.prefix}-keycloak"
  location                        = azurerm_resource_group.this.location
  resource_group_name             = azurerm_resource_group.this.name
  size                            = var.vm_size
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.vm.id]
  custom_data                     = base64encode(local.cloud_init)
  secure_boot_enabled             = true
  vtpm_enabled                    = true
  tags                            = var.tags

  admin_ssh_key {
    username   = var.admin_username
    public_key = local.admin_ssh_public_key
  }

  os_disk {
    name                 = "${var.prefix}-keycloak-osdisk"
    caching              = "ReadWrite"
    storage_account_type = var.os_disk_type
    disk_size_gb         = var.os_disk_size_gb
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  identity {
    type = "SystemAssigned"
  }

  boot_diagnostics {} # managed storage account; enables serial console

  # Make sure the secrets exist before first boot so the first ansible-pull run
  # can succeed (the VM's own Key Vault RBAC grant can only be created after the
  # VM exists; the 30-min ansible-pull timer covers RBAC propagation delays).
  depends_on = [
    azurerm_key_vault_secret.postgres_password,
    azurerm_key_vault_secret.keycloak_admin_password,
    azurerm_key_vault_secret.smtp_username,
    azurerm_key_vault_secret.smtp_password,
    azurerm_network_interface_security_group_association.vm,
  ]
}
