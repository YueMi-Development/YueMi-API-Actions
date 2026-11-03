#!/usr/bin/env bash
# Common utility functions for YueMi API actions

log_info() {
  echo "::notice::$*"
}

log_error() {
  echo "::error::$*" >&2
}

log_warning() {
  echo "::warning::$*"
}

require_tool() {
  local tool="$1"
  if ! command -v "$tool" >/dev/null 2>&1; then
    log_error "Required tool '$tool' is not installed or not in PATH."
    exit 1
  fi
}

# Sets a GitHub / Forgejo action step output
set_action_output() {
  local key="$1"
  local val="$2"
  if [ -n "$GITHUB_OUTPUT" ]; then
    if [[ "$val" =~ $'\n' ]]; then
      local delimiter
      delimiter="EOF_$(head -c 16 /dev/urandom 2>/dev/null | xxd -p 2>/dev/null || date +%s%N)"
      {
        echo "${key}<<${delimiter}"
        echo "$val"
        echo "${delimiter}"
      } >> "$GITHUB_OUTPUT"
    else
      echo "${key}=${val}" >> "$GITHUB_OUTPUT"
    fi
  fi
}

# Cross-platform / POSIX compliant file size calculation in bytes
get_file_size() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "0"
    return 1
  fi
  wc -c < "$file" | tr -d ' \r\n\t'
}

# Normalizes and validates boolean strings (true/false)
normalize_boolean() {
  local field_name="$1"
  local val
  val="$(echo "$2" | tr '[:upper:]' '[:lower:]' | tr -d ' \r\n\t')"
  case "$val" in
    true|1)
      echo "true"
      ;;
    false|0|"")
      echo "false"
      ;;
    *)
      log_error "Field '$field_name' must be 'true' or 'false', got: '$2'"
      exit 1
      ;;
  esac
}

# Removes trailing slashes from URLs
clean_url() {
  local url="$1"
  echo "${url%/}"
}

