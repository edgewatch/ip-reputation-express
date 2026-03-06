<div align="center">

# ⚡ IP Reputation Express
### _Fast, simplified IP reputation lookup and enrichment for threat intel workflows_

</div>

IP Reputation Express is an **offline IP reputation lookup** tool built around a single, locally stored dump file. It uses **Edgewatch CTI** as the primary ground truth for maliciousness: the dump generator extracts distinct malicious `source.ip` entries from the CTI events dataset (along with related ASN/network metadata) and compiles them into an optimized offline structure for rapid reputation checks. The core idea is **speed and scale without external queries**—reducing data leakage risk and avoiding external bottlenecks—by memory-mapping the dump and querying it efficiently (e.g., via binary search) to deliver **deterministic verdicts** for known-bad hits, targeting **sub-millisecond performance** (**<100 µs per lookup**).

When an IP is not a direct blacklist hit, the tool produces a **probabilistic risk score (0.0–1.0)** using neighborhood and ownership signals: blacklist density within the IP’s `/24` and `/16`, **ASN reputation**, and a small neighbor `/24` signal, combined into a weighted score surfaced with a **PROBABILISTIC** confidence label. Users interact through a CLI that supports **single IP checks**, **batch checks**, **dump info**, and optional **JSON output**; results are shown as a concise report including **Status** (e.g., BLACKLISTED / NOT LISTED), **Confidence** (CERTAIN vs PROBABILISTIC), **Score**, ASN enrichment, `/24` `/16` densities, and the **dump version + entry count** to make the underlying dataset explicit.
