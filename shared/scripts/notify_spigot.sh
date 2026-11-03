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

if [ -z "${INPUT_MINECRAFT_VERSION}" ]; then
  log_error "Missing required input: minecraft-version"
  exit 1
fi

if [ -z "${INPUT_VERSION}" ]; then
  log_error "Missing required input: version"
  exit 1
fi

BASE_URL="$(clean_url "${INPUT_API_URL:-https://api.yuemi.org}")"
IS_LATEST="$(normalize_boolean "is-latest" "${INPUT_IS_LATEST:-true}")"

GIT_COMMIT="${INPUT_GIT_COMMIT:-}"
if [ -z "$GIT_COMMIT" ]; then
  GIT_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo "")"
fi

GIT_BRANCH="${INPUT_GIT_BRANCH:-}"
if [ -z "$GIT_BRANCH" ]; then
  GIT_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
fi

ENDPOINT="${BASE_URL}/api/v1/private/spigot/versions"

TMP_RESP="$(mktemp)"
trap 'rm -f "${TMP_RESP}"' EXIT

PAYLOAD=$(jq -n \
  --arg mv "${INPUT_MINECRAFT_VERSION}" \
  --arg v "${INPUT_VERSION}" \
  --arg gc "${GIT_COMMIT}" \
  --arg gb "${GIT_BRANCH}" \
  --argjson latest "${IS_LATEST}" \
  '{
    minecraft_version: $mv,
    version: $v,
    git_commit: $gc,
    git_branch: $gb,
    is_latest: $latest
  }')

echo "Registering Spigot version '${INPUT_VERSION}' (Minecraft: ${INPUT_MINECRAFT_VERSION}, branch: ${GIT_BRANCH}, commit: ${GIT_COMMIT}, is_latest: ${IS_LATEST})..."
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
  log_error "Failed to register Spigot version (HTTP ${HTTP_CODE}):"
  echo "$RESP_BODY" >&2
  exit 1
fi

SUCCESS_FLAG=$(echo "$RESP_BODY" | jq -r '.success // empty' 2>/dev/null || true)
if [ "$SUCCESS_FLAG" = "false" ]; then
  ERR_MSG=$(echo "$RESP_BODY" | jq -r '.message // "Unknown API error"' 2>/dev/null || true)
  log_error "Failed to register Spigot version: ${ERR_MSG}"
  echo "$RESP_BODY" >&2
  exit 1
fi

BUILD_NUMBER=$(echo "$RESP_BODY" | jq -r '.data.build_number // empty' 2>/dev/null || true)
VERSION_ID=$(echo "$RESP_BODY" | jq -r '.data.id // empty' 2>/dev/null || true)

echo "Assigned Build Number: ${BUILD_NUMBER}"
echo "Assigned Version ID: ${VERSION_ID}"
echo "Full API Response: ${RESP_BODY}"

set_action_output "build-number" "${BUILD_NUMBER}"
set_action_output "version-id" "${VERSION_ID}"
set_action_output "response" "${RESP_BODY}"
set_action_output "minecraft-version" "${INPUT_MINECRAFT_VERSION}"
set_action_output "version" "${INPUT_VERSION}"

