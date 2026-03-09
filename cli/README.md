# iplookup CLI — User Guide

Command-line tool for IP reputation lookups using the Edgewatch offline dump. On first run (or when the local dump is older than 3 hours), the CLI automatically downloads the latest dump from the project.

## Download

- **Releases:** [GitHub Releases](https://github.com/edgewatch/ip-reputation-express/releases) — pick the asset for your platform.
- **Latest binaries in repo:** [cli/](https://github.com/edgewatch/ip-reputation-express/tree/main/cli) — same files as in the latest release; use raw URLs below if you need a stable link.

| Platform        | Asset / raw file |
|----------------|-------------------|
| Linux (amd64)  | `iplookup-linux-amd64` |
| Linux (arm64)  | `iplookup-linux-arm64` |
| macOS (Intel)  | `iplookup-darwin-amd64` |
| macOS (Apple Silicon) | `iplookup-darwin-arm64` |
| Windows (amd64) | `iplookup-windows-amd64.exe` |

Raw URL example (Linux amd64):  
`https://raw.githubusercontent.com/edgewatch/ip-reputation-express/main/cli/iplookup-linux-amd64`

Checksums: `cli/checksums.txt` (or in release assets).

## Install and run

### Linux / macOS

Linux and macOS binaries have **no file extension**. After downloading:

1. Make the file executable:
   ```bash
   chmod +x iplookup-linux-amd64
   ```
   (Use the filename that matches your platform, e.g. `iplookup-darwin-arm64` on Apple Silicon.)

2. Run it:
   ```bash
   ./iplookup-linux-amd64 check 8.8.8.8
   ```

3. **(Optional)** Install to your PATH:
   ```bash
   sudo mv iplookup-linux-amd64 /usr/local/bin/iplookup
   iplookup check 8.8.8.8
   ```
   Or for your user only:
   ```bash
   mkdir -p ~/.local/bin
   mv iplookup-linux-amd64 ~/.local/bin/iplookup
   export PATH="$HOME/.local/bin:$PATH"
   iplookup check 8.8.8.8
   ```

### Windows

1. Download `iplookup-windows-amd64.exe`.
2. Run from Command Prompt or PowerShell:
   ```cmd
   iplookup-windows-amd64.exe check 8.8.8.8
   ```
   Optionally add the folder containing the exe to your `PATH`.

## First run and dump file

- The CLI uses a local dump file. By default it is stored at **`~/.iplookup/dump.bin`** (Linux/macOS) or **`%USERPROFILE%\.iplookup\dump.bin`** (Windows).
- **First run:** If the dump does not exist, the CLI downloads it automatically from the project.
- **Refresh:** If the dump is older than 3 hours, the CLI will download a new one automatically when you run a command.
- To use a custom dump path: `./iplookup-linux-amd64 --dump /path/to/dump.bin check 1.2.3.4`

## Commands

| Command | Description |
|--------|-------------|
| `check &lt;ip&gt;` | Look up reputation for one IP |
| `check --file &lt;file&gt;` | Batch lookup (one IP per line) |
| `info` | Show dump metadata (version, counts) |
| `asn &lt;number&gt;` | Look up ASN reputation |
| `update` | Download latest dump from an admin server (optional; auto-download handles default source) |

Add `--json` before the command for machine-readable output.

## Examples

```bash
# Single IP lookup
./iplookup-linux-amd64 check 185.220.101.45

# Batch lookup from file
./iplookup-linux-amd64 check --file ips.txt

# Dump info
./iplookup-linux-amd64 info

# ASN reputation
./iplookup-linux-amd64 asn 60729

# JSON output
./iplookup-linux-amd64 --json check 8.8.8.8
```

## Verdicts

- **BLACKLISTED** — IP is in the threat intelligence data (100% confidence).
- **SUSPICIOUS** — Probabilistic score ≥ 0.65.
- **CLEAN** — Score &lt; 0.65 or no significant signals.

## Links

- [Releases](https://github.com/edgewatch/ip-reputation-express/releases)
- [Latest dump (raw)](https://raw.githubusercontent.com/edgewatch/ip-reputation-express/main/dist/latest.bin)
