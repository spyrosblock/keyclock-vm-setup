# keyclock-vm-setup

Keycloak on a single Azure VM:

- **Terraform** (`terraform/`) – Ubuntu 24.04 VM (static IP + Azure FQDN, NSG 22/80/443,
  system-assigned identity), Key Vault (RBAC) holding all secrets, and Azure Communication
  Services Email (Azure-managed sender domain + Entra app for SMTP auth).
- **cloud-init → ansible-pull** – on first boot the VM clones this repo and runs
  `ansible/site.yml`; a systemd timer re-runs it every 30 min so the host keeps converging.
- **Ansible** (`ansible/`) – Docker, secrets from Key Vault via managed identity (IMDS),
  Let's Encrypt (certbot), docker compose stack **Keycloak + Postgres + nginx**, and the
  master realm's SMTP settings (via `kcadm`).

```
Internet ──443/80──> nginx ──frontend net──> keycloak:8080 ──backend net (internal)──> postgres
                       │                         │
              /etc/letsencrypt          smtp.azurecomm.net:587 (ACS Email)
```

## Prerequisites

- `az` CLI logged in (`az login`), Terraform >= 1.6
- Deployer needs **Owner** (or User Access Administrator + Contributor) on the subscription
  and permission to create Entra app registrations
- This repo must be reachable by the VM (public, or adjust `repo_url`)
- Defaults: VM in **swedencentral** on **Standard_D2als_v6** (2 vCPU / 4 GiB); Terraform state in
  `kc-tfstate-rg` (northeurope). If you change `location`/`vm_size`, the size must be both offered
  in the region and within your core quota: `az vm list-usage -l <location> -o table`

## Deploy

```bash
# 1. Remote state (once)
WRITE_BACKEND_FILE=true ./bootstrap/tfstate.sh      # writes terraform/backend.hcl

# 2. Variables
cd terraform
cp terraform.tfvars.example terraform.tfvars        # set subscription_id, letsencrypt_email, ssh_allowed_cidrs, ...

# 3. Apply
terraform init -backend-config=backend.hcl
terraform apply
```

First boot takes ~5–10 minutes. Follow it with:

```bash
$(terraform output -raw ssh_command) 'sudo tail -f /var/log/ansible-pull.log'
```

Then open `terraform output keycloak_url` and log in as `admin` with:

```bash
eval "$(terraform output -raw keycloak_admin_password_command)"
```

### Custom domain

Leave `domain` empty to use `<dns_label>.<location>.cloudapp.azure.com` (works out of the
box). For your own domain, set `domain = "auth.example.com"` and create an A record pointing
to `terraform output public_ip`. The certbot role waits for DNS before requesting a
certificate; if it times out, the next timer run retries.

## Day-2

| Task | How |
|------|-----|
| Change config / bump images | Edit `ansible/` (e.g. `group_vars/all.yml`), push to `repo_branch`; applied within 30 min |
| Apply immediately | `sudo systemctl start ansible-pull.service` on the VM |
| Logs | `/var/log/ansible-pull.log`, `docker compose -p keycloak -f /opt/keycloak/docker-compose.yml logs -f` |
| Rotate SMTP secret | `terraform apply` (auto-rotates yearly); next ansible-pull pushes it into Keycloak |
| Test TLS without rate limits | set `certbot_staging: true` in `ansible/group_vars/all.yml` |

## Secrets (Key Vault)

| Secret | Source |
|--------|--------|
| `postgres-password` | `random_password` |
| `keycloak-admin-password` | `random_password` |
| `smtp-username` | `<acs-name>.<entra-app-client-id>.<tenant-id>` |
| `smtp-password` | Entra app client secret |

Nothing secret is stored in git or in cloud-init `custom_data`.

## Caveats

- **Bootstrap admin is temporary** in Keycloak 26 – create a permanent admin user and remove
  the bootstrap one. If you change the admin password in the UI, update
  `keycloak-admin-password` in Key Vault too (the SMTP role logs in with it).
- **Postgres password** only applies when the volume is first created; rotating it requires
  `ALTER USER` in the database as well.
- **Azure-managed email domain** has low sending limits and a fixed `DoNotReply@<guid>.azurecomm.net`
  sender – fine for password resets/verification, use a custom ACS domain for production volume.
- **Cert renewal** (certbot.timer, standalone mode) stops nginx for a few seconds.
- First run may fail on Key Vault 403 until the VM's role assignment propagates; the timer
  retries automatically.
- Changing `custom_data` (e.g. `repo_url`) replaces the VM.
