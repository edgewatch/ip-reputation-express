# ip-express CLI — User Guide

Command-line tool for IP reputation lookups using the Edgewatch offline dump. On first run (or when the local dump is older than 3 hours), the CLI automatically downloads the latest dump from the project.

## Download

- **Releases:** [GitHub Releases](https://github.com/edgewatch/ip-reputation-express/releases) — pick the asset for your platform.
- **Latest binaries in repo:** [cli/](https://github.com/edgewatch/ip-reputation-express/tree/main/cli) — same files as in the latest release; use raw URLs below if you need a stable link.

| Platform        | Asset / raw file |
|----------------|-------------------|
| Linux (amd64)  | `ip-express-linux-amd64` |
| Linux (arm64)  | `ip-express-linux-arm64` |
| macOS (Intel)  | `ip-express-darwin-amd64` |
| macOS (Apple Silicon) | `ip-express-darwin-arm64` |
| Windows (amd64) | `ip-express-windows-amd64.exe` |

Raw URL example (Linux amd64):  
`https://raw.githubusercontent.com/edgewatch/ip-reputation-express/main/cli/ip-express-linux-amd64`

Checksums: `cli/checksums.txt` (or in release assets).

## Install and run

### Linux / macOS

Linux and macOS binaries have **no file extension**. After downloading:

1. Make the file executable:
   ```bash
   chmod +x ip-express-linux-amd64
   ```
   (Use the filename that matches your platform, e.g. `ip-express-darwin-arm64` on Apple Silicon.)

2. Run it:
   ```bash
   ./ip-express-linux-amd64 check 8.8.8.8
   ```

3. **(Optional)** Install to your PATH:
   ```bash
   sudo mv ip-express-linux-amd64 /usr/local/bin/ip-express
   ip-express check 8.8.8.8
   ```
   Or for your user only:
   ```bash
   mkdir -p ~/.local/bin
   mv ip-express-linux-amd64 ~/.local/bin/ip-express
   export PATH="$HOME/.local/bin:$PATH"
   ip-express check 8.8.8.8
   ```

### Windows

1. Download `ip-express-windows-amd64.exe`.
2. Run from Command Prompt or PowerShell:
   ```cmd
   ip-express-windows-amd64.exe check 8.8.8.8
   ```
   Optionally add the folder containing the exe to your `PATH`.

## First run and dump file

- The CLI uses a local dump file. By default it is stored at **`~/.ip-express/dump.bin`** (Linux/macOS) or **`%USERPROFILE%\.ip-express\dump.bin`** (Windows).
- **First run:** If the dump does not exist, the CLI downloads it automatically from the project.
- **Refresh:** If the dump is older than 3 hours, the CLI tries to download a new one when you run a command.
- **Offline / update failure:** If the download fails (no internet, server down, etc.), the CLI **still works** using the existing dump file. You only need a working connection for the first run or when you want to refresh; after that, lookups work with the local copy even when outdated.
- To use a custom dump path: `./ip-express-linux-amd64 --dump /path/to/dump.bin check 1.2.3.4`

## Commands

| Command | Description |
|--------|-------------|
| `check &lt;ip&gt;` | Look up reputation for one IP |
| `check --file &lt;file&gt;` | Batch lookup (one IP per line) |
| `info` | Show dump metadata (version, counts) |
| `asn &lt;number&gt;` | Look up ASN reputation |
| `update` | Download latest dump from an admin server (optional; auto-download handles default source) |

Add `--json` before the command for machine-readable output.  
Add `--verbose` (or `-v`) to get the full visual output with colored details, score bars, and dump metadata.

By default, `check` outputs only the numerical prediction score — ideal for scripting and piping.

## Examples

```bash
# Single IP lookup (outputs just the score, e.g. "0.8923")
./ip-express-linux-amd64 check 185.220.101.45

# Verbose output with full visual details
./ip-express-linux-amd64 --verbose check 185.220.101.45
./ip-express-linux-amd64 -v check 185.220.101.45

# Batch lookup from file (one score per line)
./ip-express-linux-amd64 check --file ips.txt

# Batch lookup with full table
./ip-express-linux-amd64 -v check --file ips.txt

# Dump info
./ip-express-linux-amd64 info

# ASN reputation
./ip-express-linux-amd64 asn 60729

# JSON output
./ip-express-linux-amd64 --json check 8.8.8.8
```

## Verdicts

- **BLACKLISTED** — IP is in the threat intelligence data (100% confidence).
- **SUSPICIOUS** — Probabilistic score ≥ 0.65.
- **CLEAN** — Score &lt; 0.65 or no significant signals.

## Links

- [Releases](https://github.com/edgewatch/ip-reputation-express/releases)
- [Latest dump (raw)](https://raw.githubusercontent.com/edgewatch/ip-reputation-express/main/dist/latest.bin)
