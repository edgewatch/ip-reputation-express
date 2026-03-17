#!/usr/bin/env bash
# install-cluster.sh — Deploy Edgewatch IP Reputation Express to a Wazuh cluster node.
# Run as root on each Wazuh manager node (master and workers).
#
# Usage:
#   sudo ./scripts/install-cluster.sh --role master  [--bin /path/to/ip-express-linux-amd64]
#   sudo ./scripts/install-cluster.sh --role worker  [--bin /path/to/ip-express-linux-amd64]
#
# Roles:
#   master  — installs rules + integration + binary + dump + cron
#   worker  — installs integration + binary + dump + cron (rules sync automatically from master)
#
# Notes:
#   - Rules are installed only on master; Wazuh cluster syncs them to workers automatically.
#   - The ossec.conf <integration> block must be added manually on each node after installation.
#   - Run this script sequentially on each node; no inter-node coordination required.

set -euo pipefail

# ── Paths ─────────────────────────────────────────────────────────────────────
WAZUH_ROOT="/var/ossec"
EDGEWATCH_DIR="${WAZUH_ROOT}/integrations/edgewatch"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

INTEGRATION_SRC="${REPO_ROOT}/integrations/custom-edgewatch-ip-reputation-express.py"
INTEGRATION_DST="${WAZUH_ROOT}/integrations/custom-edgewatch-ip-reputation-express.py"
RULES_SRC="${REPO_ROOT}/rules/edgewatch-ip-reputation-express.xml"
RULES_DST="${WAZUH_ROOT}/etc/rules/edgewatch-ip-reputation-express.xml"
REFRESH_SRC="${SCRIPT_DIR}/edgewatch-refresh-dump.sh"
REFRESH_DST="${WAZUH_ROOT}/integrations/edgewatch-refresh-dump.sh"
BIN_DST="/usr/local/bin/ip-express"
CRON_FILE="/etc/cron.d/edgewatch-dump-refresh"
LOG_DIR="${WAZUH_ROOT}/logs"

# ── Args ──────────────────────────────────────────────────────────────────────
ROLE=""
BIN_SRC=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role) ROLE="$2"; shift 2 ;;
    --bin)  BIN_SRC="$2"; shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

[[ "${ROLE}" == "master" || "${ROLE}" == "worker" ]] \
  || { echo "Usage: $0 --role master|worker [--bin <path>]"; exit 1; }

# ── Helpers ───────────────────────────────────────────────────────────────────
info()    { echo "[INFO]  $*"; }
warn()    { echo "[WARN]  $*" >&2; }
error()   { echo "[ERROR] $*" >&2; exit 1; }
section() { echo; echo "── $* ──────────────────────────────────────────────"; }

# ── Preflight ─────────────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]]       && error "Run as root (sudo)."
[[ -d "${WAZUH_ROOT}" ]] || error "Wazuh root not found at ${WAZUH_ROOT}."
[[ -f "${INTEGRATION_SRC}" ]] || error "Integration script not found: ${INTEGRATION_SRC}"
[[ -f "${REFRESH_SRC}" ]]     || error "Refresh script not found: ${REFRESH_SRC}"

echo
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Edgewatch IP Reputation Express — Cluster installer         ║"
echo "║  Role: ${ROLE^^}$(printf '%*s' $((52 - ${#ROLE})) '')║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo "  Node role : ${ROLE}"
echo "  Wazuh root: ${WAZUH_ROOT}"
echo "  Repo root : ${REPO_ROOT}"
echo

# ── Step 1: ip-express binary ─────────────────────────────────────────────────
section "Step 1 — ip-express binary"
if [[ -n "${BIN_SRC}" ]]; then
  info "Installing ip-express from ${BIN_SRC}"
  install -m 755 "${BIN_SRC}" "${BIN_DST}"
  info "Installed: ${BIN_DST}"
elif [[ -x "${BIN_DST}" ]]; then
  info "ip-express already installed at ${BIN_DST}: $("${BIN_DST}" --version 2>/dev/null || echo 'unknown version')"
elif command -v ip-express &>/dev/null; then
  info "ip-express found in PATH: $(command -v ip-express)"
else
  warn "ip-express binary not found. Pass --bin <path> or install manually to ${BIN_DST}."
  warn "Dump seeding will be skipped."
fi

# ── Step 2: Edgewatch data directory ──────────────────────────────────────────
section "Step 2 — Edgewatch data directory"
info "Creating ${EDGEWATCH_DIR}"
mkdir -p "${EDGEWATCH_DIR}"
chown root:wazuh "${EDGEWATCH_DIR}"
chmod 750 "${EDGEWATCH_DIR}"
info "Directory ready: ${EDGEWATCH_DIR}"

# ── Step 3: Refresh script ────────────────────────────────────────────────────
section "Step 3 — Dump refresh script"
info "Installing ${REFRESH_DST}"
install -m 750 -o root -g wazuh "${REFRESH_SRC}" "${REFRESH_DST}"
info "Installed: ${REFRESH_DST}"

# ── Step 4: Initial dump seed ─────────────────────────────────────────────────
section "Step 4 — Initial dump download"
if [[ -x "${BIN_DST}" ]] || command -v ip-express &>/dev/null; then
  info "Downloading Edgewatch dump (first seed)..."
  TARGET_DIR="${EDGEWATCH_DIR}" \
  IP_EXPRESS_BIN="${BIN_DST}" \
    "${REFRESH_DST}" \
    && info "Dump ready: ${EDGEWATCH_DIR}/latest.bin" \
    || warn "Initial dump download failed. Run ${REFRESH_DST} manually."
else
  warn "Skipping dump seed — ip-express binary not available."
fi

# ── Step 5: Integration script ────────────────────────────────────────────────
section "Step 5 — Integration script"
info "Installing ${INTEGRATION_DST}"
install -m 750 -o root -g wazuh "${INTEGRATION_SRC}" "${INTEGRATION_DST}"
info "Installed: ${INTEGRATION_DST}"

# ── Step 6: Rules (master only) ───────────────────────────────────────────────
section "Step 6 — Wazuh rules"
if [[ "${ROLE}" == "master" ]]; then
  [[ -f "${RULES_SRC}" ]] || error "Rules file not found: ${RULES_SRC}"
  info "Installing rules to ${RULES_DST}"
  install -m 640 -o root -g wazuh "${RULES_SRC}" "${RULES_DST}"
  info "Installed: ${RULES_DST}"
  info "Rules will sync to worker nodes automatically via Wazuh cluster."
else
  info "Worker node — skipping rules installation (master syncs them automatically)."
fi

# ── Step 7: Cron for dump refresh ─────────────────────────────────────────────
section "Step 7 — Cron job (dump refresh every 30 min)"
cat > "${CRON_FILE}" <<CRONEOF
# Edgewatch IP Reputation Express — refresh dump every 30 minutes
*/30 * * * * root TARGET_DIR=${EDGEWATCH_DIR} IP_EXPRESS_BIN=${BIN_DST} ${REFRESH_DST} >> ${LOG_DIR}/edgewatch-refresh.log 2>&1
CRONEOF
chmod 644 "${CRON_FILE}"
info "Cron installed: ${CRON_FILE}"

# ── Step 8: Validate installation ─────────────────────────────────────────────
section "Step 8 — Validation"

ERRORS=0

check() {
  local desc="$1" result="$2"
  if [[ "${result}" == "ok" ]]; then
    echo "  [OK]  ${desc}"
  else
    echo "  [!!]  ${desc} — ${result}"
    ERRORS=$((ERRORS + 1))
  fi
}

check "ip-express binary" \
  "$( [[ -x "${BIN_DST}" ]] && echo ok || echo "NOT FOUND at ${BIN_DST}" )"

check "Dump file exists" \
  "$( [[ -s "${EDGEWATCH_DIR}/latest.bin" ]] && echo ok || echo "NOT FOUND or empty" )"

check "Integration script" \
  "$( [[ -x "${INTEGRATION_DST}" ]] && echo ok || echo "NOT FOUND or not executable" )"

check "Refresh script" \
  "$( [[ -x "${REFRESH_DST}" ]] && echo ok || echo "NOT FOUND or not executable" )"

check "Cron job" \
  "$( [[ -f "${CRON_FILE}" ]] && echo ok || echo "NOT FOUND" )"

if [[ "${ROLE}" == "master" ]]; then
  check "Rules file (master)" \
    "$( [[ -f "${RULES_DST}" ]] && echo ok || echo "NOT FOUND at ${RULES_DST}" )"
fi

if [[ -x "${BIN_DST}" && -s "${EDGEWATCH_DIR}/latest.bin" ]]; then
  VERDICT=$("${BIN_DST}" --dump "${EDGEWATCH_DIR}/latest.bin" --json check 185.220.101.45 2>/dev/null \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('Verdict','?'))" 2>/dev/null || echo "error")
  check "Test lookup 185.220.101.45 = BLACKLISTED" \
    "$( [[ "${VERDICT}" == "BLACKLISTED" ]] && echo ok || echo "got: ${VERDICT}" )"
fi

echo

# ── Summary ───────────────────────────────────────────────────────────────────
echo "╔══════════════════════════════════════════════════════════════╗"
if [[ ${ERRORS} -eq 0 ]]; then
  echo "║  Installation complete — ${ERRORS} errors                          ║"
else
  echo "║  Installation finished with ${ERRORS} error(s) — review above      ║"
fi
echo "╚══════════════════════════════════════════════════════════════╝"

cat <<MANUAL

ACTION REQUIRED — Complete these steps manually on this node:

1. Add to ${WAZUH_ROOT}/etc/ossec.conf inside <ossec_config>:

$(cat "${REPO_ROOT}/config/edgewatch-ip-reputation-express.xml")

2. Set dump path for the integration via systemd override:

   systemctl edit wazuh-manager

   Add the following content:

   [Service]
   Environment="IPEXPRESS_DUMP_PATH=${EDGEWATCH_DIR}/latest.bin"

   Then reload and restart:

   systemctl daemon-reload
   systemctl restart wazuh-manager

3. Verify:

   tail -f ${LOG_DIR}/integrations.log | grep edgewatch

MANUAL
