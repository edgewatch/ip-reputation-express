# Wazuh Integration for IP Reputation Express

Wazuh integration that enriches security alerts with **offline IP reputation data**
from [Edgewatch IP Reputation Express](https://github.com/edgewatch/ip-reputation-express)
— no external APIs, no rate limits, sub-millisecond lookups against a local binary.

## How it works

```
Wazuh detects an event with a public source IP
  → custom-edgewatch-ip-reputation-express.py is called
  → calls the local ip-express binary against an offline dump file
  → sends enriched event back to the Wazuh queue
  → enriched alert visible in dashboard with verdict + score + ASN + subnet data
```

Private and reserved IPs are skipped automatically. The dump file is refreshed
every 30 minutes via cron from the Edgewatch CTI feed.

## Requirements

- Wazuh Manager 4.x
- [`ip-express` binary](https://github.com/edgewatch/ip-reputation-express/releases)
  installed at `/usr/local/bin/ip-express`
- Internet access for the initial dump download and periodic refresh

## Contents of this directory

```
integrations/wazuh/
├── README.md                  ← you are here
├── integrations/
│   └── custom-edgewatch-ip-reputation-express.py   # Wazuh integration script
├── rules/
│   └── edgewatch-ip-reputation-express.xml          # Wazuh detection rules
├── config/
│   └── edgewatch-ip-reputation-express.xml          # ossec.conf snippet
├── scripts/
│   ├── install-cluster.sh                           # Installer (standalone + cluster)
│   └── edgewatch-refresh-dump.sh                    # Dump refresh with atomic swap
└── docs/
    └── installation.md                              # Full installation guide (Spanish)
```

## Quick install

### 1. Download the `ip-express` binary

Get the latest release from the
[IP Reputation Express releases page](https://github.com/edgewatch/ip-reputation-express/releases)
and install it:

```bash
sudo install -m 755 ip-express-linux-amd64 /usr/local/bin/ip-express
ip-express --version
```

### 2. Run the installer

Clone or download this repository, then run:

```bash
# Standalone or master node
sudo ./integrations/wazuh/scripts/install-cluster.sh \
  --role master --bin /path/to/ip-express-linux-amd64

# On each worker node (cluster deployments)
sudo ./integrations/wazuh/scripts/install-cluster.sh \
  --role worker --bin /path/to/ip-express-linux-amd64
```

The installer copies scripts, rules, downloads the initial dump, and sets up cron.

### 3. Add the integration block to `ossec.conf`

Edit `/var/ossec/etc/ossec.conf` and add this inside `<ossec_config>`:

```xml
<integration>
  <name>custom-edgewatch-ip-reputation-express.py</name>
  <group>authentication_failed,authentication_success,fortigate,web,windows</group>
  <alert_format>json</alert_format>
</integration>
```

> **Customize `<group>` for your environment.**
> Add or remove groups depending on what sources you have active.
> To see available groups: **Wazuh Dashboard > Threat Hunting > Events > filter by `rule.groups`**.

### 4. Set the dump path environment variable

```bash
sudo systemctl edit wazuh-manager
```

Add:

```ini
[Service]
Environment="IPEXPRESS_DUMP_PATH=/var/ossec/integrations/edgewatch/latest.bin"
```

### 5. Restart Wazuh Manager

```bash
sudo systemctl restart wazuh-manager
sudo systemctl status wazuh-manager
```

## Active Response Warning

> **This integration enriches alerts only. It does NOT configure or enable
> Wazuh active response.**

If you are considering using Wazuh
[active response](https://documentation.wazuh.com/current/user-manual/capabilities/active-response/index.html)
(e.g., `firewall-drop`) to automatically block IPs based on enrichment verdicts,
read the following carefully:

- **False positives can block legitimate traffic.** The underlying CTI dataset
  may contain IPs that are no longer malicious, or IPs shared by both legitimate
  and malicious users (e.g., VPNs, cloud providers, CDN exit nodes).

- **`PROBABILISTIC` verdicts are estimates, not certainties.** When an IP is not
  a direct blacklist hit, the tool computes a risk score from neighborhood and
  ASN signals. These scores should **never** be used as the sole trigger for
  blocking traffic.

- **Only `CERTAIN` / `BLACKLISTED` verdicts indicate a direct CTI match**, and
  even then, the data depends on the dump version and the upstream feed. If you
  decide to enable active response, limit it **exclusively** to `CERTAIN` verdicts
  and start with a short block duration.

- **Always test in passive/log-only mode first.** Monitor enriched alerts in
  the dashboard for at least a few days before enabling any automated blocking.
  Review the false-positive rate for your specific traffic profile.

- **Edgewatch is not responsible for traffic blocked by user-configured active
  responses.** The integration provides threat intelligence enrichment; the
  decision to act on it is yours.

## Alert fields

All fields are prefixed with `edgewatch_offline.*`:

| Field | Type | Description |
|-------|------|-------------|
| `edgewatch_offline.verdict` | string | `BLACKLISTED` / `SUSPICIOUS` / `CLEAN` |
| `edgewatch_offline.fraud_score` | int (0–100) | Normalized risk score |
| `edgewatch_offline.score` | float (0.0–1.0) | Raw score from ip-express |
| `edgewatch_offline.confidence` | string | `CERTAIN` or `PROBABILISTIC` |
| `edgewatch_offline.blacklisted` | bool | Direct CTI hit |
| `edgewatch_offline.asn` | int | Autonomous System Number |
| `edgewatch_offline.asn_score` | float | ASN reputation (0=clean, 1=worst) |
| `edgewatch_offline.density_24` | int | Blacklisted IPs in /24 subnet (out of 256) |
| `edgewatch_offline.density_16` | int | Blacklisted IPs in /16 subnet (out of 65536) |
| `edgewatch_offline.prefix_24` | string | e.g. `185.220.101.0/24` |
| `edgewatch_offline.source.srcip` | string | Queried IP address |
| `edgewatch_offline.source.rule` | string | Original Wazuh rule ID |
| `edgewatch_offline.skipped` | bool | `true` if IP is private or not found |
| `edgewatch_offline.lookup_error` | bool | `true` if binary failed or dump missing |

## Wazuh rules

| ID | Level | Condition |
|----|-------|-----------|
| 99383 | 5 | SSH auth failure from public IP (trigger) |
| 99384 | 5 | SSH auth success from public IP (trigger) |
| 99389 | 3 | Base rule — any enrichment event (parent of 99390–99394) |
| 99390 | 12 | `verdict = BLACKLISTED` — known malicious, certain |
| 99391 | 7 | `verdict = SUSPICIOUS` — probabilistic score >= 65/100 |
| 99392 | 7 | High /24 subnet density (>= 50 IPs blacklisted in /24) |
| 99393 | 3 | Informational enrichment (any verdict) |
| 99394 | 6 | Lookup error — binary failed, dump missing, or timeout |

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `IPEXPRESS_BIN` | `/usr/local/bin/ip-express` | Path to ip-express binary |
| `IPEXPRESS_DUMP_PATH` | *(binary default)* | Set to `/var/ossec/integrations/edgewatch/latest.bin` in production |
| `IPEXPRESS_TIMEOUT` | `8` | Subprocess timeout in seconds |
| `IPEXPRESS_DEBUG` | `true` | Enable logging to `integrations.log` |
| `IPEXPRESS_LOG_FILE` | `/var/ossec/logs/integrations.log` | Log file path |
| `IPEXPRESS_QUEUE_SOCKET` | `/var/ossec/queue/sockets/queue` | Wazuh queue socket |

## Dump refresh

The dump file (`latest.bin`) is the offline database used for IP lookups. It must
be refreshed periodically to stay current with the Edgewatch CTI feed.

The installer sets up a cron job that runs every 30 minutes:

```
*/30 * * * * root TARGET_DIR=/var/ossec/integrations/edgewatch \
  IP_EXPRESS_BIN=/usr/local/bin/ip-express \
  /var/ossec/integrations/edgewatch-refresh-dump.sh
```

The refresh script downloads the latest dump, validates it with `ip-express info`,
performs an atomic swap, and keeps a backup (`latest.bin.prev`) for rollback.

## Full installation guide

For step-by-step manual installation, cluster deployment, troubleshooting, and
rollback procedures, see [docs/installation.md](docs/installation.md).

## License

MIT
