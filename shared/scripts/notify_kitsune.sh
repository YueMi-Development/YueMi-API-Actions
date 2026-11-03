#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

require_tool curl
require_tool jq

if [ -z "${INPUT_API_KEY}" ]; then
  log_error "Missing required input: api-key"
  exit 1
fi

if [ -z "${INPUT_VERSION}" ]; then
  log_error "Missing required input: version"
  exit 1
fi

BASE_URL="$(clean_url "${INPUT_API_URL:-https://api.yuemi.org}")"
CATEGORY="${INPUT_CATEGORY:-panel}"
IS_LATEST="$(normalize_boolean "is-latest" "${INPUT_IS_LATEST:-false}")"

ENDPOINT="${BASE_URL}/api/v1/private/kitsune/versions"

TMP_RESP="$(mktemp)"
trap 'rm -f "${TMP_RESP}"' EXIT

PAYLOAD=$(jq -n \
  --arg cat "${CATEGORY}" \
  --arg ver "${INPUT_VERSION}" \
  --argjson latest "${IS_LATEST}" \
  '{category: $cat, version: $ver, is_latest: $latest}')

echo "Registering Kitsune version '${INPUT_VERSION}' (category: ${CATEGORY}, is_latest: ${IS_LATEST})..."
echo "Endpoint: ${ENDPOINT}"

HTTP_CODE=$(curl --silent --show-error \
  -w "%{http_code}" \
  -o "${TMP_RESP}" \
  -X POST "${ENDPOINT}" \
  -H "X-API-Key: ${INPUT_API_KEY}" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d "${PAYLOAD}")

RESP_BODY="$(cat "${TMP_RESP}")"

if [ "$HTTP_CODE" -lt 200 ] || [ "$HTTP_CODE" -ge 300 ]; then
  log_error "Failed to notify Kitsune version (HTTP ${HTTP_CODE}):"
  echo "$RESP_BODY" >&2
  exit 1
fi

SUCCESS_FLAG=$(echo "$RESP_BODY" | jq -r '.success // empty' 2>/dev/null || true)
if [ "$SUCCESS_FLAG" = "false" ]; then
  ERR_MSG=$(echo "$RESP_BODY" | jq -r '.message // "Unknown API error"' 2>/dev/null || true)
  log_error "Failed to register Kitsune version: ${ERR_MSG}"
  echo "$RESP_BODY" >&2
  exit 1
fi

echo "Successfully registered Kitsune version: ${RESP_BODY}"

set_action_output "response" "${RESP_BODY}"
set_action_output "category" "${CATEGORY}"
set_action_output "version" "${INPUT_VERSION}"

