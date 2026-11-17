variable "subscription_id" {
  description = "Azure subscription ID to deploy into (required by azurerm v4)."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.subscription_id))
    error_message = "subscription_id must be a subscription GUID."
  }
}

variable "location" {
  description = "Azure region for all regional resources. swedencentral is used because this subscription cannot create VMs in westeurope/northeurope."
  type        = string
  default     = "swedencentral"
}

variable "prefix" {
  description = "Short lowercase prefix used in resource names (a random suffix is appended where global uniqueness is required)."
  type        = string
  default     = "kc"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,9}$", var.prefix))
    error_message = "prefix must be 2-10 lowercase letters/digits, starting with a letter."
  }
}

variable "vm_size" {
  description = "VM size. Keycloak + Postgres needs ~4 GiB RAM. Must be offered in var.location AND have core quota on the subscription (check: az vm list-usage -l <location>)."
  type        = string
  default     = "Standard_D2als_v6"
}

variable "os_disk_type" {
  description = "OS disk storage account type."
  type        = string
  default     = "StandardSSD_LRS"

  validation {
    condition     = contains(["Standard_LRS", "StandardSSD_LRS", "Premium_LRS", "StandardSSD_ZRS", "Premium_ZRS"], var.os_disk_type)
    error_message = "os_disk_type must be one of Standard_LRS, StandardSSD_LRS, Premium_LRS, StandardSSD_ZRS, Premium_ZRS."
  }
}

variable "os_disk_size_gb" {
  description = "OS disk size in GiB."
  type        = number
  default     = 30

  validation {
    condition     = var.os_disk_size_gb >= 30
    error_message = "os_disk_size_gb must be at least 30 (Ubuntu image size)."
  }
}

variable "admin_username" {
  description = "Admin SSH user on the VM."
  type        = string
  default     = "azureuser"
}

variable "admin_ssh_public_key" {
  description = "SSH public key content. Takes precedence over admin_ssh_public_key_path when set."
  type        = string
  default     = ""
}

variable "admin_ssh_public_key_path" {
  description = "Path to the SSH public key file, used when admin_ssh_public_key is empty."
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "ssh_allowed_cidrs" {
  description = <<-EOT
    Source CIDRs allowed to reach SSH (22/tcp). Defaults to anywhere because the
    VM only accepts key-based auth, but you SHOULD restrict this to your own IP,
    e.g. ["203.0.113.10/32"]. Set to [] to create no SSH rule at all.
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = alltrue([for c in var.ssh_allowed_cidrs : can(cidrhost(c, 0))])
    error_message = "Every entry in ssh_allowed_cidrs must be a valid CIDR."
  }
}

variable "dns_label" {
  description = "Azure public IP DNS label -> <dns_label>.<location>.cloudapp.azure.com. Empty = \"<prefix>-<random>\"."
  type        = string
  default     = ""

  validation {
    condition     = var.dns_label == "" || can(regex("^[a-z][a-z0-9-]{1,61}[a-z0-9]$", var.dns_label))
    error_message = "dns_label must be 3-63 chars: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "domain" {
  description = <<-EOT
    FQDN Keycloak is served on (and the Let's Encrypt certificate is issued for).
    Empty = use the public IP's Azure FQDN (<dns_label>.<location>.cloudapp.azure.com).
    If you set a custom domain, create an A record pointing at the `public_ip` output.
  EOT
  type        = string
  default     = ""

  validation {
    condition     = var.domain == "" || can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,63}$", var.domain))
    error_message = "domain must be a lowercase fully qualified domain name (or empty)."
  }
}

variable "letsencrypt_email" {
  description = "Contact email for the Let's Encrypt ACME account."
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.letsencrypt_email))
    error_message = "letsencrypt_email must be a valid email address."
  }
}

variable "repo_url" {
  description = "Git repository (HTTPS) that ansible-pull checks out on the VM."
  type        = string
  default     = "https://github.com/spyrosblock/keyclock-vm-setup.git"

  validation {
    condition     = can(regex("^https://[^\\s'\"]+$", var.repo_url))
    error_message = "repo_url must be an https:// URL without spaces or quotes."
  }
}

variable "repo_branch" {
  description = "Branch ansible-pull checks out."
  type        = string
  default     = "main"

  validation {
    condition     = can(regex("^[A-Za-z0-9._/-]+$", var.repo_branch))
    error_message = "repo_branch may only contain letters, digits, '.', '_', '/' and '-'."
  }
}

variable "acs_data_location" {
  description = "Data location for Azure Communication Services / Email (e.g. Europe, United States)."
  type        = string
  default     = "Europe"
}

variable "tags" {
  description = "Tags applied to all taggable resources."
  type        = map(string)
  default = {
    project    = "keycloak"
    managed_by = "terraform"
  }
}
