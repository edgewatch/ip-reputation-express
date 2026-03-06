<div align="center">

# ⚡ IP Reputation Express
### _Fast, simplified IP reputation lookup and enrichment for threat intel workflows_

</div>

IP Reputation Express is an **offline IP reputation lookup** tool built around a single, locally stored dump file. It uses **Edgewatch CTI** as the primary ground truth for maliciousness: the dump generator extracts distinct malicious `source.ip` entries from the CTI events dataset (along with related ASN/network metadata) and compiles them into an optimized offline structure for rapid reputation checks. The core idea is **speed and scale without external queries**—reducing data leakage risk and avoiding external bottlenecks—by memory-mapping the dump and querying it efficiently (e.g., via binary search) to deliver **deterministic verdicts** for known-bad hits, targeting **sub-millisecond performance** (**<100 µs per lookup**).

When an IP is not a direct blacklist hit, the tool produces a **probabilistic risk score (0.0–1.0)** using neighborhood and ownership signals: blacklist density within the IP’s `/24` and `/16`, **ASN reputation**, and a small neighbor `/24` signal, combined into a weighted score surfaced with a **PROBABILISTIC** confidence label. Users interact through a CLI that supports **single IP checks**, **batch checks**, **dump info**, and optional **JSON output**; results are shown as a concise report including **Status** (e.g., BLACKLISTED / NOT LISTED), **Confidence** (CERTAIN vs PROBABILISTIC), **Score**, ASN enrichment, `/24` `/16` densities, and the **dump version + entry count** to make the underlying dataset explicit.


## Example output

```text
  IP Address    185.220.101.45
  Status        ■ BLACKLISTED
  Confidence    CERTAIN (100%)
  Score         1.00 / 1.00

  ASN           AS205100
  ASN Name      F3 Netze e.V.
  ASN Rep.      0.847 (HIGH RISK)

  Subnet /24    185.220.101.0/24
  /24 Density   89 / 256 (34.8% blacklisted)

  Subnet /16    185.220.0.0/16
  /16 Density   412 / 65536 (0.6% blacklisted)

╭──────────────────────────────────────────────────────╮
│  Dump Version: 2026-03-05T12:00:00Z | 24.3M entries │
╰──────────────────────────────────────────────────────╯
````

## Fields explained

### IP Address

The IP you queried.

### Status

* **■ BLACKLISTED**: the IP was found in the blacklist (known-bad).
* If not found, you’ll typically see a **NOT LISTED** / clean-style status.

### Confidence

* **CERTAIN (100%)**: the IP is a direct blacklist hit (deterministic).
* **PROBABILISTIC**: the IP is not listed; the tool estimates risk from surrounding signals.

### Score (0.00 → 1.00)

A normalized risk score:

* **1.00** for deterministic blacklist hits.
* Otherwise computed from **/24 density**, **/16 density**, **ASN reputation**, and a **neighbor /24** signal.

### ASN / ASN Name

The Autonomous System that owns (or most specifically routes) the IP, derived from an offline prefix table.

### ASN Rep.

ASN reputation score (**0.0 = clean**, **1.0 = worst**) from the dump’s ASN reputation table.
The label (e.g., **HIGH RISK**) is a human-friendly banding of that number.

### Subnet /24 and /24 Density

* Shows the IP’s **/24 block** (`A.B.C.0/24`)
* Density: how many IPs in that /24 are blacklisted, out of **256** total addresses.

### Subnet /16 and /16 Density

* Shows the IP’s **/16 block** (`A.B.0.0/16`)
* Density: how many IPs in that /16 are blacklisted, out of **65,536** total addresses.

### Dump Version / entries

* The timestamped version of the local dump being used
* Total number of entries in the dump (useful to confirm you’re on the expected dataset)

## Notes & limitations

* **IPv4 only (v1).**
* Results depend entirely on the **dump version** shown at the bottom of the output.
