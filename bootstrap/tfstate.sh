#!/usr/bin/env bash
# Creates the Azure Storage backend for Terraform remote state (idempotent).
#
# Usage:
#   az login
#   [SUBSCRIPTION_ID=...] [LOCATION=northeurope] [STATE_RG=kc-tfstate-rg] \
#   [STATE_SA=tfstate<unique>] [STATE_CONTAINER=tfstate] [STATE_KEY=keycloak-vm.tfstate] \
#   [WRITE_BACKEND_FILE=true] ./bootstrap/tfstate.sh
#
# STATE_SA must be globally unique (3-24 lowercase letters/digits). If unset,
# an existing "tfstate*" account in STATE_RG is reused, otherwise a random
# name is generated.
set -euo pipefail

LOCATION="${LOCATION:-northeurope}"
STATE_RG="${STATE_RG:-kc-tfstate-rg}"
STATE_CONTAINER="${STATE_CONTAINER:-tfstate}"
STATE_KEY="${STATE_KEY:-keycloak-vm.tfstate}"
WRITE_BACKEND_FILE="${WRITE_BACKEND_FILE:-false}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_FILE="${SCRIPT_DIR}/../terraform/backend.hcl"

command -v az >/dev/null || { echo "ERROR: az CLI not found" >&2; exit 1; }
az account show >/dev/null 2>&1 || { echo "ERROR: run 'az login' first" >&2; exit 1; }

if [[ -n "${SUBSCRIPTION_ID:-}" ]]; then
  az account set --subscription "${SUBSCRIPTION_ID}"
fi
SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
echo "Subscription: ${SUBSCRIPTION_ID}"

echo "Ensuring resource group ${STATE_RG} (${LOCATION})..."
az group create --name "${STATE_RG}" --location "${LOCATION}" \
  --tags purpose=terraform-state --output none

if [[ -z "${STATE_SA:-}" ]]; then
  STATE_SA="$(az storage account list --resource-group "${STATE_RG}" \
    --query "[?starts_with(name, 'tfstate')].name | [0]" -o tsv)"
  if [[ -z "${STATE_SA}" ]]; then
    STATE_SA="tfstate$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
  fi
fi

if [[ ! "${STATE_SA}" =~ ^[a-z0-9]{3,24}$ ]]; then
  echo "ERROR: STATE_SA '${STATE_SA}' must be 3-24 lowercase letters/digits" >&2
  exit 1
fi

if az storage account show --name "${STATE_SA}" --resource-group "${STATE_RG}" >/dev/null 2>&1; then
  echo "Storage account ${STATE_SA} already exists."
else
  if [[ "$(az storage account check-name --name "${STATE_SA}" --query nameAvailable -o tsv)" != "true" ]]; then
    echo "ERROR: storage account name '${STATE_SA}' is not available; set STATE_SA" >&2
    exit 1
  fi
  echo "Creating storage account ${STATE_SA}..."
  az storage account create \
    --name "${STATE_SA}" \
    --resource-group "${STATE_RG}" \
    --location "${LOCATION}" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --min-tls-version TLS1_2 \
    --https-only true \
    --allow-blob-public-access false \
    --tags purpose=terraform-state \
    --output none
fi

echo "Enabling blob versioning and soft delete (state recovery)..."
az storage account blob-service-properties update \
  --account-name "${STATE_SA}" \
  --resource-group "${STATE_RG}" \
  --enable-versioning true \
  --enable-delete-retention true --delete-retention-days 14 \
  --enable-container-delete-retention true --container-delete-retention-days 14 \
  --output none

echo "Ensuring container ${STATE_CONTAINER}..."
# Management-plane call: works without data-plane RBAC having propagated yet.
az storage container-rm create \
  --storage-account "${STATE_SA}" \
  --resource-group "${STATE_RG}" \
  --name "${STATE_CONTAINER}" \
  --public-access off \
  --output none

# The backend uses Entra ID auth (use_azuread_auth = true), which needs a
# data-plane role for the signed-in user.
SA_ID="$(az storage account show --name "${STATE_SA}" --resource-group "${STATE_RG}" --query id -o tsv)"
USER_OID="$(az ad signed-in-user show --query id -o tsv 2>/dev/null || true)"
if [[ -n "${USER_OID}" ]]; then
  echo "Granting 'Storage Blob Data Contributor' to the signed-in user..."
  az role assignment create \
    --assignee-object-id "${USER_OID}" \
    --assignee-principal-type User \
    --role "Storage Blob Data Contributor" \
    --scope "${SA_ID}" \
    --output none 2>/dev/null \
    || echo "WARN: could not create role assignment (it may already exist, or you lack permission)." >&2
else
  echo "WARN: not signed in as a user; grant 'Storage Blob Data Contributor' on ${SA_ID} to your principal manually." >&2
fi

BACKEND_CONFIG="resource_group_name  = \"${STATE_RG}\"
storage_account_name = \"${STATE_SA}\"
container_name       = \"${STATE_CONTAINER}\"
key                  = \"${STATE_KEY}\"
use_azuread_auth     = true"

echo
echo "Backend config (terraform/backend.hcl):"
echo "----------------------------------------"
echo "${BACKEND_CONFIG}"
echo "----------------------------------------"

if [[ "${WRITE_BACKEND_FILE}" == "true" ]]; then
  printf '%s\n' "${BACKEND_CONFIG}" > "${BACKEND_FILE}"
  echo "Wrote ${BACKEND_FILE}"
fi

echo
echo "Next: cd terraform && terraform init -backend-config=backend.hcl"
echo "(RBAC can take a minute or two to propagate if init returns 403.)"
