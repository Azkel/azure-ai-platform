#!/usr/bin/env bash
# Deploy mcp-on-azure (infra + image + seeds) and validate three scenarios.
# Run OUTSIDE the Cursor agent sandbox (normal terminal) after: az login
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${ROOT}/terraform"
TAG="${IMAGE_TAG:-0.1.7-$(date +%Y%m%d%H%M)}"

need() { command -v "$1" >/dev/null || { echo "missing: $1"; exit 1; }; }
need az; need terraform; need curl; need python3; need jq

az account show -o none

cd "${TF_DIR}"
# -force-copy: if a leftover local terraform.tfstate exists, push it to the remote
# backend without an interactive prompt (common after first local apply).
terraform init -migrate-state -force-copy -backend-config=backend.hcl -input=false

echo "== terraform apply (infra) =="
terraform apply -auto-approve -input=false

ACR="$(terraform output -raw acr_login_server)"
ACR_NAME="${ACR%%.*}"
RG="$(terraform output -raw resource_group_name)"
ENDPOINT="$(terraform output -raw mcp_endpoint)"
SCOPE="$(terraform output -raw entra_scope)"
ST="$(terraform output -raw storage_account_name)"
CT="$(terraform output -raw storage_container_name)"
CT_PO="$(terraform output -raw storage_platform_only_container_name)"

echo "== acr build ${ACR}/mcp-on-azure:${TAG} =="
az acr build -r "$ACR_NAME" -g "$RG" \
  -t "mcp-on-azure:${TAG}" \
  -t "mcp-on-azure:latest" \
  "${ROOT}/src"

MCP_IMAGE="${ACR}/mcp-on-azure:${TAG}"
echo "== terraform apply (image ${MCP_IMAGE}) =="
terraform apply -auto-approve -input=false -var="mcp_image=${MCP_IMAGE}"

# Persist image in local tfvars so next apply keeps it (optional).
if [[ -f terraform.tfvars ]] && grep -q '^mcp_image' terraform.tfvars; then
  sed -i "s|^mcp_image *=.*|mcp_image = \"${MCP_IMAGE}\"|" terraform.tfvars
fi

if [[ -x scripts/bind-custom-domain.sh ]]; then
  echo "== bind custom domain (best effort) =="
  ./scripts/bind-custom-domain.sh || true
fi

echo "== seed blobs =="
# Owner ≠ blob data-plane. Grant account Contributor only long enough to seed,
# then remove it so user.* cannot read mcp-platform-only.
OID="$(az ad signed-in-user show --query id -o tsv)"
SCOPE_ID="$(az storage account show -n "$ST" --query id -o tsv)"
CT_SCOPE="${SCOPE_ID}/blobServices/default/containers/${CT}"

az role assignment create --assignee-object-id "$OID" --assignee-principal-type User \
  --role "Storage Blob Data Contributor" --scope "$SCOPE_ID" -o none 2>/dev/null || true
echo "waiting for seed RBAC..."
sleep 30
printf 'hello from mcp lab\n' | az storage blob upload \
  --account-name "$ST" --container-name "$CT" --name hello.txt \
  --data @- --auth-mode login --overwrite -o none
printf 'platform identity only — user.* should get 403\n' | az storage blob upload \
  --account-name "$ST" --container-name "$CT_PO" --name platform-only.txt \
  --data @- --auth-mode login --overwrite -o none

echo "narrowing your data-plane rights to ${CT} reader only..."
# Drop account-scoped data roles that would break the deny demo.
for role in "Storage Blob Data Contributor" "Storage Blob Data Owner" "Storage Blob Data Reader"; do
  az role assignment delete --assignee-object-id "$OID" --role "$role" --scope "$SCOPE_ID" -o none 2>/dev/null || true
done
az role assignment create --assignee-object-id "$OID" --assignee-principal-type User \
  --role "Storage Blob Data Reader" --scope "$CT_SCOPE" -o none 2>/dev/null || true
echo "waiting for narrowed RBAC..."
sleep 30

echo "== wait for revision =="
for i in $(seq 1 30); do
  code="$(curl -sS -o /dev/null -w '%{http_code}' "${ENDPOINT}/health" || true)"
  [[ "$code" == "200" ]] && break
  sleep 5
done
curl -fsS "${ENDPOINT}/health" | jq .

TOKEN="$(az account get-access-token --scope "$SCOPE" --query accessToken -o tsv)"

mcp_call() {
  local method="$1"
  local params="$2"
  curl -sS -X POST "${ENDPOINT}/mcp" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -d "$(jq -nc --arg m "$method" --argjson p "$params" \
      '{jsonrpc:"2.0",id:1,method:$m,params:$p}')"
}

echo "== MCP initialize =="
INIT="$(mcp_call initialize '{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"deploy-validate","version":"0"}}')"
echo "$INIT" | head -c 500; echo

# Streamable HTTP may return SSE; extract tool results via a small helper.
call_tool() {
  local name="$1"
  local args_json="$2"
  local body
  body="$(jq -nc --arg n "$name" --argjson a "$args_json" \
    '{jsonrpc:"2.0",id:2,method:"tools/call",params:{name:$n,arguments:$a}}')"
  curl -sS -X POST "${ENDPOINT}/mcp" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -d "$body"
}

extract_text() {
  # Read SSE/JSON from stdin (heredoc would steal stdin from the pipe).
  python3 -c '
import sys, json
raw = sys.stdin.read()
chunks = []
for line in raw.splitlines():
    if line.startswith("data:"):
        chunks.append(line[5:].lstrip())
stripped = raw.lstrip()
if stripped.startswith("{"):
    chunks.insert(0, stripped)
seen = set()
for c in chunks:
    c = c.strip()
    if not c or c == "[DONE]" or c in seen:
        continue
    seen.add(c)
    try:
        obj = json.loads(c)
    except Exception:
        continue
    result = obj.get("result") or {}
    content = result.get("content") or []
    texts = [x.get("text","") for x in content if isinstance(x, dict) and x.get("type")=="text"]
    if texts:
        print("\n".join(texts))
        sys.exit(0)
    if "isError" in result:
        print(json.dumps(result, indent=2))
        sys.exit(0)
print(raw[:2000])
'
}

echo
echo "========== SCENARIO 1: platform_list_blobs (MI) =========="
S1="$(call_tool platform_list_blobs '{}')"
T1="$(printf '%s' "$S1" | extract_text)"
echo "$T1"
echo "$T1" | grep -q 'mcp-demo/hello.txt' || { echo "FAIL: expected mcp-demo/hello.txt"; exit 1; }
echo "$T1" | grep -q 'mcp-platform-only/platform-only.txt' || { echo "FAIL: expected mcp-platform-only/platform-only.txt"; exit 1; }
echo "PASS: MI lists both blobs"

echo
echo "========== SCENARIO 2: user_get_blob hello.txt (caller OK) =========="
S2="$(call_tool user_get_blob '{"blobName":"hello.txt"}')"
T2="$(printf '%s' "$S2" | extract_text)"
echo "$T2"
echo "$T2" | grep -qi 'hello from mcp lab' || { echo "FAIL: expected hello content"; exit 1; }
echo "PASS: user can read hello.txt"

echo
echo "========== SCENARIO 3: user_get_blob platform-only (deny) =========="
S3="$(call_tool user_get_blob '{"blobName":"mcp-platform-only/platform-only.txt"}')"
T3="$(printf '%s' "$S3" | extract_text)"
echo "$T3"
echo "$T3" | grep -qiE 'Access denied|403|AuthorizationFailure|not visible' \
  || { echo "FAIL: expected access denied for platform-only"; exit 1; }
echo "PASS: user denied on platform-only"

echo
echo "============================================================"
echo "  ALL THREE SCENARIOS PASSED"
echo "  endpoint: ${ENDPOINT}"
echo "  image:    ${MCP_IMAGE}"
echo "============================================================"
