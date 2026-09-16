#!/usr/bin/env bash
# Demo-only: grant Storage Blob Data Reader on the mcp-demo container.
#
# NOT part of core Terraform on purpose — meetup callers need data-plane read on
# hello.txt for user_get_blob, while mcp-platform-only stays MI-only (deny demo).
# Owner/Contributor on the RG is control-plane only and does NOT grant blob reads.
#
# Usage:
#   ./scripts/grant-demo-blob-reader.sh                         # signed-in user
#   ./scripts/grant-demo-blob-reader.sh <object-id> [...]       # explicit principals
#   DEMO_BLOB_READER_OBJECT_IDS="id1,id2" ./scripts/grant-demo-blob-reader.sh
#
# Run from labs/mcp-on-azure/terraform after apply (needs az + terraform outputs),
# or set STORAGE_ACCOUNT_NAME / DEMO_CONTAINER_NAME.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

need() { command -v "$1" >/dev/null || { echo "missing: $1"; exit 1; }; }
need az

ST="${STORAGE_ACCOUNT_NAME:-}"
CT="${DEMO_CONTAINER_NAME:-}"
if [[ -z "$ST" || -z "$CT" ]]; then
  need terraform
  ST="${ST:-$(terraform output -raw storage_account_name 2>/dev/null || true)}"
  CT="${CT:-$(terraform output -raw storage_container_name 2>/dev/null || true)}"
fi
ST="${ST:?set STORAGE_ACCOUNT_NAME or run from terraform/ with outputs}"
CT="${CT:-mcp-demo}"

PRINCIPALS=()
if [[ $# -gt 0 ]]; then
  PRINCIPALS=("$@")
elif [[ -n "${DEMO_BLOB_READER_OBJECT_IDS:-}" ]]; then
  IFS=',' read -ra PRINCIPALS <<< "${DEMO_BLOB_READER_OBJECT_IDS}"
else
  PRINCIPALS=("$(az ad signed-in-user show --query id -o tsv)")
fi

SCOPE_ID="$(az storage account show -n "$ST" --query id -o tsv)"
CT_SCOPE="${SCOPE_ID}/blobServices/default/containers/${CT}"

echo "== demo RBAC (explicit script — not Terraform) =="
echo "  container: ${CT} @ ${ST}"
echo "  role:      Storage Blob Data Reader"
echo "  note:      does NOT grant mcp-platform-only (deny demo stays intact)"

for oid in "${PRINCIPALS[@]}"; do
  oid="$(echo "$oid" | tr -d '[:space:]')"
  [[ -z "$oid" ]] && continue
  echo "  assignee:  ${oid}"
  # --assignee resolves User vs SP; idempotent if assignment already exists.
  az role assignment create \
    --assignee "$oid" \
    --role "Storage Blob Data Reader" \
    --scope "$CT_SCOPE" \
    -o none 2>/dev/null \
    || echo "  (already assigned or create returned non-zero — continuing)"
done

echo "waiting for RBAC propagation..."
sleep "${DEMO_RBAC_WAIT_SECONDS:-30}"
echo "done — user_get_blob hello.txt should work for the assignees above"
