#!/var/ossec/framework/python/bin/python3
"""
Wazuh custom integration — Edgewatch offline IP reputation (ip-reputation-express).

Flow:
- Reads Wazuh alert JSON from file argument.
- Extracts source IP from common alert fields.
- Validates the IP is a public IPv4 address.
- Calls local ip-express binary against an offline dump.
- Emits enriched event back to Wazuh queue socket.

No external Python dependencies — stdlib only.
Deploy to: /var/ossec/integrations/custom-edgewatch-ip-reputation-express.py
Permissions: chmod 750 / chown root:wazuh
"""

import ipaddress
import json
import os
import subprocess
import sys
import time
from socket import AF_UNIX, SOCK_DGRAM, socket
from typing import Any, Dict, Optional, Tuple

# ── Configuration (overridable via environment variables) ─────────────────────

_BASE_DIR = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))

IP_EXPRESS_BIN    = os.environ.get("IPEXPRESS_BIN",          "/usr/local/bin/ip-express")
DUMP_PATH         = os.environ.get("IPEXPRESS_DUMP_PATH",    "")   # empty = use binary default
WRAPPER_TIMEOUT   = int(os.environ.get("IPEXPRESS_TIMEOUT",  "8"))
DEBUG_ENABLED     = os.environ.get("IPEXPRESS_DEBUG",        "true").lower() == "true"
LOG_FILE          = os.environ.get("IPEXPRESS_LOG_FILE",     f"{_BASE_DIR}/logs/integrations.log")
SOCKET_ADDR       = os.environ.get("IPEXPRESS_QUEUE_SOCKET", f"{_BASE_DIR}/queue/sockets/queue")

INTEGRATION_NAME  = "edgewatch_offline"


# ── Logging ───────────────────────────────────────────────────────────────────

def debug(message: str) -> None:
    if not DEBUG_ENABLED:
        return
    now = time.strftime("%a %b %d %H:%M:%S %Z %Y")
    line = f"{now}: {message}\n"
    try:
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(line)
    except OSError:
        pass  # keep integration functional even if logging fails


# ── IP helpers ────────────────────────────────────────────────────────────────

def _nested_get(data: Dict[str, Any], *path: str) -> Optional[Any]:
    cur: Any = data
    for key in path:
        if not isinstance(cur, dict) or key not in cur:
            return None
        cur = cur[key]
    return cur


def _first_non_empty(*values: Optional[Any]) -> Optional[str]:
    for value in values:
        if value is None:
            continue
        s = value.strip() if isinstance(value, str) else str(value).strip()
        if s:
            return s
    return None


def extract_srcip(alert: Dict[str, Any]) -> Optional[str]:
    """Extract source IP from common Wazuh alert field locations."""
    return _first_non_empty(
        _nested_get(alert, "data", "srcip"),
        _nested_get(alert, "srcip"),
        _nested_get(alert, "ip"),
        _nested_get(alert, "data", "win", "eventdata", "ipAddress"),  # Windows events
        _nested_get(alert, "data", "src_ip"),
    )


def is_public_ipv4(ip_str: str) -> bool:
    """Return True only for routable public IPv4 addresses."""
    try:
        ip_obj = ipaddress.ip_address(ip_str)
    except ValueError:
        return False
    return isinstance(ip_obj, ipaddress.IPv4Address) and ip_obj.is_global


# ── Lookup ────────────────────────────────────────────────────────────────────

def run_lookup(srcip: str) -> Tuple[Optional[Dict[str, Any]], Optional[str]]:
    """Call ip-express binary and return (parsed_json, error_message)."""
    if not os.path.exists(IP_EXPRESS_BIN):
        return None, f"binary not found: {IP_EXPRESS_BIN}"

    cmd = [IP_EXPRESS_BIN]
    if DUMP_PATH:
        cmd += ["--dump", DUMP_PATH]
    cmd += ["--json", "check", srcip]

    debug(f"Running: {' '.join(cmd)}")

    try:
        proc = subprocess.run(
            cmd,
            text=True,
            capture_output=True,
            timeout=WRAPPER_TIMEOUT,
            check=False,
        )
    except subprocess.TimeoutExpired:
        return None, f"lookup timeout after {WRAPPER_TIMEOUT}s"
    except Exception as exc:
        return None, f"lookup execution error: {exc}"

    if proc.returncode != 0:
        details = (proc.stderr or proc.stdout or "unknown error").strip()
        return None, f"lookup failed (rc={proc.returncode}): {details}"

    raw = (proc.stdout or "").strip()
    if not raw:
        return None, "lookup returned empty output"

    try:
        return json.loads(raw), None
    except json.JSONDecodeError as exc:
        return None, f"invalid JSON from lookup: {exc}"


# ── Payload builder ───────────────────────────────────────────────────────────

def build_payload(alert: Dict[str, Any]) -> Dict[str, Any]:
    """Build the enriched payload to send back to Wazuh."""
    srcip = extract_srcip(alert)

    source = {
        "alert_id":    alert.get("id", ""),
        "rule":        _nested_get(alert, "rule", "id") or "",
        "description": _nested_get(alert, "rule", "description") or "",
        "full_log":    alert.get("full_log", ""),
        "srcip":       srcip or "",
    }

    payload: Dict[str, Any] = {
        "integration": INTEGRATION_NAME,
        INTEGRATION_NAME: {
            "found":        0,
            "lookup_error": False,
            "skipped":      False,
            "source":       source,
        },
    }

    ie = payload[INTEGRATION_NAME]

    # ── Guard: no IP found ────────────────────────────────────────────────────
    if not srcip:
        ie["skipped"] = True
        ie["skip_reason"] = "no source IP in alert"
        debug("No source IP found — skipping lookup")
        return payload

    # ── Guard: skip private / non-routable IPs ────────────────────────────────
    if not is_public_ipv4(srcip):
        ie["skipped"] = True
        ie["skip_reason"] = "source IP is not a public IPv4"
        debug(f"Skipping non-public IP: {srcip}")
        return payload

    # ── Lookup ────────────────────────────────────────────────────────────────
    data, error = run_lookup(srcip)
    if error:
        ie["lookup_error"] = True
        ie["error"] = error
        debug(f"Lookup error for {srcip}: {error}")
        return payload

    # ── Enrich ────────────────────────────────────────────────────────────────
    ie["found"] = 1
    ie.update({
        # Core verdict
        "verdict":     data.get("Verdict", "UNKNOWN"),
        "blacklisted": bool(data.get("Blacklisted", False)),
        "confidence":  data.get("Confidence", "UNKNOWN"),

        # Scores (native 0.0–1.0 + normalized 0–100 int for pcre2 thresholds)
        "score":       float(data.get("Score", 0.0)),
        "fraud_score": int(round(float(data.get("Score", 0.0)) * 100)),

        # ASN
        "asn":       int(data.get("ASN", 0)),
        "asn_score": float(data.get("ASNScore", 0.0)),
        "asn_found": bool(data.get("ASNFound", False)),

        # Subnet density
        "density_24": int(data.get("Density24", 0)),
        "density_16": int(data.get("Density16", 0)),
        "prefix_24":  data.get("Prefix24Str", ""),
        "prefix_16":  data.get("Prefix16Str", ""),

        # Dump metadata (for traceability)
        "dump_version": int(data.get("DumpVersion", 0)),
        "dump_time":    data.get("DumpTime", ""),
        "dump_count":   int(data.get("DumpCount", 0)),
    })

    debug(
        f"Enriched {srcip}: verdict={ie['verdict']} "
        f"score={ie['fraud_score']}/100 asn={ie['asn']}"
    )
    return payload


# ── Event sender ──────────────────────────────────────────────────────────────

def send_event(message: Dict[str, Any], agent: Optional[Dict[str, Any]] = None) -> None:
    """Send enriched event to Wazuh internal queue via Unix socket."""
    if not agent or agent.get("id") == "000":
        string = f"1:{INTEGRATION_NAME}:{json.dumps(message)}"
    else:
        agent_id   = agent.get("id", "000")
        agent_name = agent.get("name", "unknown")
        agent_ip   = agent.get("ip", "any")
        string = (
            f"1:[{agent_id}] ({agent_name}) {agent_ip}"
            f"->{INTEGRATION_NAME}:{json.dumps(message)}"
        )

    debug(f"Sending to socket: {string[:140]}...")
    sock = socket(AF_UNIX, SOCK_DGRAM)
    try:
        sock.connect(SOCKET_ADDR)
        sock.send(string.encode("utf-8"))
    finally:
        sock.close()


# ── Entry point ───────────────────────────────────────────────────────────────

def main(argv: list) -> int:
    debug("=== Edgewatch offline integration started ===")

    if len(argv) < 2:
        debug("Invalid arguments: missing alert file path")
        return 1

    alert_file = argv[1]
    debug(f"Alert file: {alert_file}")

    try:
        with open(alert_file, encoding="utf-8") as f:
            alert = json.load(f)
    except Exception as exc:
        debug(f"Failed to load alert JSON: {exc}")
        return 1

    debug(f"Alert: rule={_nested_get(alert, 'rule', 'id')} agent={_nested_get(alert, 'agent', 'name')}")

    payload = build_payload(alert)
    debug(f"Payload built: {json.dumps(payload)}")

    try:
        send_event(payload, alert.get("agent"))
    except Exception as exc:
        debug(f"Failed to send event to Wazuh queue: {exc}")
        return 1

    debug("=== Done ===")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
