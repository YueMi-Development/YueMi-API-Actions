#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

require_tool curl
require_tool jq

# Validate inputs
if [ -z "${INPUT_API_KEY}" ]; then
  log_error "Missing required input: api-key"
  exit 1
fi

if [ -z "${INPUT_UPLOAD_SIGNED_URL_ENDPOINT}" ]; then
  log_error "Missing required input: upload signed url endpoint"
  exit 1
fi

if [ -z "${INPUT_FILE_PATH}" ]; then
  log_error "Missing required input: file-path"
  exit 1
fi

if [ ! -f "${INPUT_FILE_PATH}" ]; then
  log_error "File does not exist or is not a regular file: ${INPUT_FILE_PATH}"
  exit 1
fi

FILE_NAME="${INPUT_FILENAME:-$(basename "${INPUT_FILE_PATH}")}"
FILE_SIZE=$(get_file_size "${INPUT_FILE_PATH}")

TMP_SIGNED_RESP="$(mktemp)"
TMP_SYNC_RESP="$(mktemp)"
trap 'rm -f "${TMP_SIGNED_RESP}" "${TMP_SYNC_RESP}"' EXIT

# Build JSON payload for requesting the signed upload URL
PAYLOAD=$(jq -n \
  --arg fn "$FILE_NAME" \
  --arg mt "${INPUT_MIME_TYPE:-}" \
  --argjson sz "${FILE_SIZE:-0}" \
  '{filename: $fn}
   + (if $mt != "" then {mime_type: $mt} else {} end)
   + (if $sz > 0 then {size: $sz} else {} end)')

echo "Requesting signed upload URL for '${FILE_NAME}' (${FILE_SIZE} bytes)..."
echo "Endpoint: ${INPUT_UPLOAD_SIGNED_URL_ENDPOINT}"

HTTP_CODE=$(curl --silent --show-error \
  -w "%{http_code}" \
  -o "${TMP_SIGNED_RESP}" \
  -X POST "${INPUT_UPLOAD_SIGNED_URL_ENDPOINT}" \
  -H "X-API-Key: ${INPUT_API_KEY}" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d "${PAYLOAD}")

RESP_BODY="$(cat "${TMP_SIGNED_RESP}")"

if [ "$HTTP_CODE" -lt 200 ] || [ "$HTTP_CODE" -ge 300 ]; then
  log_error "API request failed with HTTP ${HTTP_CODE}:"
  echo "$RESP_BODY" >&2
  exit 1
fi

# Check for explicit failure in API response body (e.g. { success: false, message: ... })
SUCCESS_FLAG=$(echo "$RESP_BODY" | jq -r '.success // empty' 2>/dev/null || true)
if [ "$SUCCESS_FLAG" = "false" ]; then
  ERR_MSG=$(echo "$RESP_BODY" | jq -r '.message // "Unknown API error"' 2>/dev/null || true)
  log_error "Failed to obtain upload signed URL: ${ERR_MSG}"
  echo "$RESP_BODY" >&2
  exit 1
fi

UPLOAD_URL=$(echo "$RESP_BODY" | jq -r '.data.url // .url // empty' 2>/dev/null || true)
FILE_ID=$(echo "$RESP_BODY" | jq -r '.data.file_id // .file_id // empty' 2>/dev/null || true)
HEADER_CONTENT_TYPE=$(echo "$RESP_BODY" | jq -r '.data.headers["Content-Type"] // empty' 2>/dev/null || true)

if [ -z "$UPLOAD_URL" ] || [ "$UPLOAD_URL" = "null" ]; then
  log_error "The API returned no upload URL:"
  echo "$RESP_BODY" >&2
  exit 1
fi

UPLOAD_CONTENT_TYPE="${HEADER_CONTENT_TYPE:-${INPUT_MIME_TYPE:-}}"

echo "Uploading file to storage..."
if [ -n "$UPLOAD_CONTENT_TYPE" ]; then
  echo "Content-Type: ${UPLOAD_CONTENT_TYPE}"
  curl --fail-with-body --silent --show-error \
    -X PUT \
    -H "Content-Type: ${UPLOAD_CONTENT_TYPE}" \
    -T "${INPUT_FILE_PATH}" \
    "${UPLOAD_URL}"
else
  curl --fail-with-body --silent --show-error \
    -X PUT \
    -T "${INPUT_FILE_PATH}" \
    "${UPLOAD_URL}"
fi
echo "File upload completed successfully."

# Sync metadata if requested and file_id is present
SYNC_FLAG=$(normalize_boolean "sync-metadata" "${INPUT_SYNC_METADATA:-true}")
SYNC_RESP_CONTENT=""

if [ "$SYNC_FLAG" = "true" ] && [ -n "$FILE_ID" ] && [ "$FILE_ID" != "null" ]; then
  if [ -n "${INPUT_SYNC_METADATA_ENDPOINT:-}" ]; then
    SYNC_URL="${INPUT_SYNC_METADATA_ENDPOINT//\{file_id\}/$FILE_ID}"
    echo "Syncing metadata for file ID '${FILE_ID}'..."
    echo "Endpoint: ${SYNC_URL}"

    SYNC_HTTP_CODE=$(curl --silent --show-error \
      -w "%{http_code}" \
      -o "${TMP_SYNC_RESP}" \
      -X POST "${SYNC_URL}" \
      -H "X-API-Key: ${INPUT_API_KEY}" \
      -H "Content-Type: application/json" \
      -H "Accept: application/json")

    SYNC_RESP_CONTENT="$(cat "${TMP_SYNC_RESP}")"

    if [ "$SYNC_HTTP_CODE" -lt 200 ] || [ "$SYNC_HTTP_CODE" -ge 300 ]; then
      log_error "Metadata sync failed with HTTP ${SYNC_HTTP_CODE}:"
      echo "$SYNC_RESP_CONTENT" >&2
      exit 1
    fi

    SYNC_SUCCESS=$(echo "$SYNC_RESP_CONTENT" | jq -r '.success // empty' 2>/dev/null || true)
    if [ "$SYNC_SUCCESS" = "false" ]; then
      SYNC_ERR=$(echo "$SYNC_RESP_CONTENT" | jq -r '.message // "Metadata sync error"' 2>/dev/null || true)
      log_error "Metadata sync failed: ${SYNC_ERR}"
      echo "$SYNC_RESP_CONTENT" >&2
      exit 1
    fi

    echo "Metadata synced successfully: ${SYNC_RESP_CONTENT}"
  else
    log_warning "file_id was provided but sync-metadata endpoint was empty; skipping sync."
  fi
fi

# Set outputs
set_action_output "file-id" "${FILE_ID}"
set_action_output "upload-url" "${UPLOAD_URL}"
set_action_output "upload-response" "${RESP_BODY}"
set_action_output "sync-response" "${SYNC_RESP_CONTENT}"

