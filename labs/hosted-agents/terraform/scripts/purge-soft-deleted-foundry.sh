#!/usr/bin/env bash
# Purge a soft-deleted Cognitive Services / Foundry account with retries.
#
# azurerm's purge_soft_delete_on_destroy often races Foundry delete (especially
# with agent network injection): purge returns 409 "provisioning state is not
# terminal". Soft-delete first (provider purge disabled), then run this script.
set -euo pipefail

LOCATION="${1:?location required (e.g. westeurope)}"
RESOURCE_GROUP="${2:?resource group required}"
ACCOUNT_NAME="${3:?account name required}"

MAX_ATTEMPTS="${PURGE_MAX_ATTEMPTS:-36}"   # ~12 minutes at 20s
SLEEP_SECONDS="${PURGE_SLEEP_SECONDS:-20}"

echo "Purging soft-deleted Cognitive account '$ACCOUNT_NAME' in '$RESOURCE_GROUP' ($LOCATION)"

attempt=1
while [ "$attempt" -le "$MAX_ATTEMPTS" ]; do
  set +e
  err="$(az cognitiveservices account purge \
    --location "$LOCATION" \
    --resource-group "$RESOURCE_GROUP" \
    --name "$ACCOUNT_NAME" 2>&1)"
  rc=$?
  set -e

  if [ "$rc" -eq 0 ]; then
    echo "Purged '$ACCOUNT_NAME'."
    exit 0
  fi

  if echo "$err" | grep -Eiq 'ResourceNotFound|NotFound|could not be found|does not exist|NoRegisteredProviderFound'; then
    echo "Nothing to purge for '$ACCOUNT_NAME' (already gone)."
    exit 0
  fi

  if echo "$err" | grep -Eiq 'not terminal|RequestConflict|Conflict|409|AnotherOperationInProgress|ConflictError'; then
    echo "Attempt $attempt/$MAX_ATTEMPTS: account not ready for purge yet; sleeping ${SLEEP_SECONDS}s"
    sleep "$SLEEP_SECONDS"
    attempt=$((attempt + 1))
    continue
  fi

  echo "Purge failed with unexpected error:"
  echo "$err"
  exit 1
done

echo "Timed out waiting to purge '$ACCOUNT_NAME' after $MAX_ATTEMPTS attempts."
exit 1
