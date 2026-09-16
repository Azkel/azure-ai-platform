#!/usr/bin/env bash
# End-to-end smoke for mcp-on-azure: health → Entra token → platform_list_blobs → user_get_blob.
# Requires: az login, jq, curl, python3. Stack must be applied (terraform outputs or env overrides).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${ROOT}/terraform"

tf_out() {
  local key="$1"
  if [[ -n "${MCP_ENDPOINT:-}" && "$key" == "mcp_endpoint" ]]; then
    echo "$MCP_ENDPOINT"
    return
  fi
  if [[ -n "${MCP_SCOPE:-}" && "$key" == "entra_scope" ]]; then
    echo "$MCP_SCOPE"
    return
  fi
  terraform -chdir="${TF_DIR}" output -raw "$key" 2>/dev/null
}

ENDPOINT="${MCP_ENDPOINT:-}"
SCOPE="${MCP_SCOPE:-}"
if [[ -z "${ENDPOINT}" ]]; then
  ENDPOINT="$(tf_out mcp_endpoint || true)"
fi
if [[ -z "${SCOPE}" ]]; then
  SCOPE="$(tf_out entra_scope || true)"
fi

if [[ -z "${ENDPOINT}" || -z "${SCOPE}" ]]; then
  echo "Need MCP endpoint + Entra scope."
  echo "  Apply terraform, or export MCP_ENDPOINT and MCP_SCOPE."
  exit 1
fi

ENDPOINT="${ENDPOINT%/}"
STORAGE="$(tf_out storage_account_name || true)"
CONTAINER="$(tf_out storage_container_name || true)"
CONTAINER_PO="$(tf_out storage_platform_only_container_name || echo mcp-platform-only)"

SESSION_ID=""

echo "== health =="
curl -fsS "${ENDPOINT}/health" | jq .
echo

echo "== unauthenticated /mcp → 401 =="
code="$(curl -sS -o /dev/null -w '%{http_code}' -X POST "${ENDPOINT}/mcp" \
  -H 'content-type: application/json' -d '{}')"
[[ "$code" == "401" ]] || { echo "FAIL: expected 401, got ${code}"; exit 1; }
echo "PASS: ${code}"
echo

echo "== acquire token (scope=${SCOPE}) =="
TOKEN="$(az account get-access-token --scope "${SCOPE}" --query accessToken -o tsv)"
[[ -n "${TOKEN}" ]] || { echo "FAIL: empty token"; exit 1; }
echo "PASS: token acquired"
echo

auth_headers() {
  local -a h=(
    -H "Authorization: Bearer ${TOKEN}"
    -H "Content-Type: application/json"
    -H "Accept: application/json, text/event-stream"
  )
  if [[ -n "${SESSION_ID}" ]]; then
    h+=(-H "Mcp-Session-Id: ${SESSION_ID}")
  fi
  printf '%s\0' "${h[@]}"
}

mcp_post() {
  local body="$1"
  local hdr_file="$2"
  local out_file="$3"
  local -a h=(
    -H "Authorization: Bearer ${TOKEN}"
    -H "Content-Type: application/json"
    -H "Accept: application/json, text/event-stream"
  )
  if [[ -n "${SESSION_ID}" ]]; then
    h+=(-H "Mcp-Session-Id: ${SESSION_ID}")
  fi
  curl -sS -D "${hdr_file}" -o "${out_file}" -X POST "${ENDPOINT}/mcp" "${h[@]}" -d "${body}"
}

extract_text() {
  # Read SSE/JSON from stdin (must not use a heredoc for the program — that steals stdin).
  python3 -c '
import sys, json, re
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
    texts = [x.get("text", "") for x in content if isinstance(x, dict) and x.get("type") == "text"]
    if texts:
        print("\n".join(texts))
        sys.exit(0)
    err = obj.get("error")
    if err:
        print(json.dumps(err, indent=2))
        sys.exit(0)
    if "protocolVersion" in result or "serverInfo" in result:
        print(json.dumps(result, indent=2))
        sys.exit(0)
sys.stderr.write(raw[:2000] + "\n")
sys.exit(1)
'
}

echo "== MCP initialize =="
INIT_BODY="$(jq -nc '{jsonrpc:"2.0",id:1,method:"initialize",params:{protocolVersion:"2025-11-25",capabilities:{},clientInfo:{name:"demo.sh",version:"0"}}}')"
mcp_post "${INIT_BODY}" /tmp/mcp-demo-init.hdr /tmp/mcp-demo-init.body
SESSION_ID="$(grep -i '^mcp-session-id:' /tmp/mcp-demo-init.hdr | awk '{print $2}' | tr -d '\r' || true)"
echo "session: ${SESSION_ID:-"(none)"}"
extract_text < /tmp/mcp-demo-init.body | head -c 500
echo
echo

# Required by streamable HTTP after initialize
NOTIFY="$(jq -nc '{jsonrpc:"2.0",method:"notifications/initialized"}')"
mcp_post "${NOTIFY}" /tmp/mcp-demo-notify.hdr /tmp/mcp-demo-notify.body >/dev/null || true

call_tool() {
  local name="$1"
  local args_json="$2"
  local body
  body="$(jq -nc --arg n "$name" --argjson a "$args_json" \
    '{jsonrpc:"2.0",id:2,method:"tools/call",params:{name:$n,arguments:$a}}')"
  mcp_post "${body}" /tmp/mcp-demo-tool.hdr /tmp/mcp-demo-tool.body
  cat /tmp/mcp-demo-tool.body
}

echo "========== platform_list_blobs (workload MI) =========="
S1="$(call_tool platform_list_blobs '{}')"
T1="$(printf '%s' "$S1" | extract_text)" || {
  echo "FAIL: could not parse tools/call response"
  echo "--- raw ---"
  echo "$S1" | head -c 2000
  exit 1
}
echo "$T1"
if ! echo "$T1" | grep -q 'mcp-demo/hello.txt'; then
  echo "FAIL: expected mcp-demo/hello.txt (seed the demo container)"
  echo "--- raw ---"
  echo "$S1" | head -c 2000
  exit 1
fi
if echo "$T1" | grep -q 'mcp-platform-only/platform-only.txt'; then
  echo "PASS: MI lists demo + platform-only"
  HAS_PLATFORM_ONLY=1
else
  echo "WARN: mcp-platform-only/platform-only.txt missing — deny scenario may be skipped"
  echo "      seed: printf 'platform identity only\\n' | az storage blob upload --account-name ${STORAGE:-<account>} --container-name ${CONTAINER_PO} --name platform-only.txt --auth-mode login --data @- --overwrite"
  HAS_PLATFORM_ONLY=0
fi
echo

echo "========== user_get_blob hello.txt (caller / OBO) =========="
S2="$(call_tool user_get_blob '{"blobName":"hello.txt"}')"
T2="$(printf '%s' "$S2" | extract_text)" || {
  echo "FAIL: could not parse user_get_blob response"
  echo "$S2" | head -c 2000
  exit 1
}
echo "$T2"
if ! echo "$T2" | grep -qi 'hello from mcp lab'; then
  echo "FAIL: expected hello content"
  echo "--- raw ---"
  echo "$S2" | head -c 2000
  exit 1
fi
echo "PASS: caller can read hello.txt"
echo

if [[ "${HAS_PLATFORM_ONLY}" == "1" ]]; then
  echo "========== user_get_blob platform-only (expect deny) =========="
  S3="$(call_tool user_get_blob '{"blobName":"mcp-platform-only/platform-only.txt"}')"
  T3="$(printf '%s' "$S3" | extract_text)" || true
  echo "$T3"
  if ! echo "$T3" | grep -qiE 'Access denied|403|AuthorizationFailure|not visible|failed'; then
    echo "FAIL: expected access denied for platform-only"
    echo "--- raw ---"
    echo "$S3" | head -c 2000
    exit 1
  fi
  echo "PASS: caller denied on platform-only"
  echo
fi
echo "============================================================"
echo "  demo.sh PASSED"
echo "  endpoint: ${ENDPOINT}"
echo "  storage:  ${STORAGE:-?} / ${CONTAINER:-?} (+ ${CONTAINER_PO})"
echo "  landing:  ${ENDPOINT}/"
echo "============================================================"
echo
echo "Optional: open the landing page and connect VS Code via interactive Entra login."
echo "Seed (if blobs missing):"
echo "  printf 'hello from mcp lab\\n' | az storage blob upload --account-name ${STORAGE:-<account>} --container-name ${CONTAINER:-mcp-demo} --name hello.txt --auth-mode login --data @- --overwrite"
echo "  printf 'platform identity only\\n' | az storage blob upload --account-name ${STORAGE:-<account>} --container-name ${CONTAINER_PO} --name platform-only.txt --auth-mode login --data @- --overwrite"
