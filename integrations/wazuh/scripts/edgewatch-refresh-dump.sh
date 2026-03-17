#!/usr/bin/env bash
# edgewatch-refresh-dump.sh — Refresh Edgewatch offline dump with atomic swap and rollback backup.
#
# Usage: edgewatch-refresh-dump.sh
#
# All paths and settings are configurable via environment variables.
# Designed to run as root or wazuh user via cron or systemd timer.
#
# Exit codes:
#   0   success
#   70  missing required command (curl or sha256sum)
#   71  ip-express binary not found or not executable
#   72  downloaded dump is empty
#   73  dump validation failed (ip-express info rejected the file)

set -euo pipefail

readonly DUMP_URL="${DUMP_URL:-https://raw.githubusercontent.com/edgewatch/ip-reputation-express/main/dist/latest.bin}"
readonly TARGET_DIR="${TARGET_DIR:-/var/ossec/integrations/edgewatch}"
readonly TARGET_DUMP="${TARGET_DUMP:-${TARGET_DIR}/latest.bin}"
readonly BACKUP_DUMP="${BACKUP_DUMP:-${TARGET_DIR}/latest.bin.prev}"
readonly TMP_DUMP="${TMP_DUMP:-${TARGET_DIR}/latest.bin.tmp}"
readonly IP_EXPRESS_BIN="${IP_EXPRESS_BIN:-/usr/local/bin/ip-express}"
readonly CURL_TIMEOUT="${CURL_TIMEOUT:-30}"

log() {
  printf '%s %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    log "missing required command: $1"
    exit 70
  }
}

main() {
  require_cmd curl
  require_cmd sha256sum

  [[ -x "$IP_EXPRESS_BIN" ]] || {
    log "ip-express binary not executable: $IP_EXPRESS_BIN"
    exit 71
  }

  mkdir -p "$TARGET_DIR"

  # ── 1. Download to temp file ─────────────────────────────────────────────
  log "downloading dump from $DUMP_URL"
  curl --fail --silent --show-error \
    --location \
    --retry 3 \
    --retry-delay 2 \
    --max-time "$CURL_TIMEOUT" \
    -o "$TMP_DUMP" \
    "$DUMP_URL"

  [[ -s "$TMP_DUMP" ]] || {
    log "downloaded dump is empty"
    rm -f "$TMP_DUMP"
    exit 72
  }

  # ── 2. Validate dump integrity ───────────────────────────────────────────
  log "validating dump integrity"
  if ! timeout --kill-after=2 10 \
      "$IP_EXPRESS_BIN" --dump "$TMP_DUMP" --json info >/dev/null 2>&1; then
    log "dump validation failed — keeping existing dump"
    rm -f "$TMP_DUMP"
    exit 73
  fi

  # ── 3. Backup current dump ───────────────────────────────────────────────
  if [[ -f "$TARGET_DUMP" ]]; then
    cp -f "$TARGET_DUMP" "$BACKUP_DUMP"
    log "backup created: $BACKUP_DUMP"
  fi

  # ── 4. Atomic swap ───────────────────────────────────────────────────────
  mv -f "$TMP_DUMP" "$TARGET_DUMP"
  chown root:wazuh "$TARGET_DUMP"
  chmod 0640 "$TARGET_DUMP"

  # ── 5. Log checksum for audit ────────────────────────────────────────────
  local checksum
  checksum="$(sha256sum "$TARGET_DUMP" | awk '{print $1}')"
  log "dump refresh successful: target=$TARGET_DUMP sha256=$checksum"
}

main "$@"
