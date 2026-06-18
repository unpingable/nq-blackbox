# nq-blackbox

Integration lab for [Prometheus blackbox_exporter](https://github.com/prometheus/blackbox_exporter) + NQ Prom ingestion.

> **Blackbox supplies vantage. NQ supplies restraint.**

This repo owns probe configuration, target catalogs, smoke scripts, and (eventually) SQL composition examples that demonstrate how external-vantage probe testimony composes with NQ's internal substrate state. It does **not** implement a probe engine, does **not** define claim semantics, and does **not** ship a dashboard.

## Scope

`nq-blackbox` is an integration lab, not a product. The boundary:

- **Owns:** probe configuration (`blackbox.yml`), target catalogs (`targets/`), smoke scripts (`scripts/`), and operator-facing notes (`docs/`) about what each probe can and cannot testify to.
- **Consumes:** the upstream `blackbox_exporter` binary (runs separately; install with the operator's package manager or as a systemd unit on the host that needs the vantage). This repo does not vendor it.
- **Feeds:** NQ's existing `prometheus_targets` config, which scrapes the exporter's `/probe` endpoint and ingests samples into the NQ SQLite database. NQ stamps each sample with scrape-target provenance (`scrape_target_name`, `scrape_target_url`) — see the precondition in [`docs/NQ_INTEGRATION.md`](docs/NQ_INTEGRATION.md).
- **Does not own:** claim semantics, verdict rendering, dashboard surfaces, alerting rules, or anything that promotes a `probe_success` observation into a service-health claim. Those live on the NQ side in claim-preflight machinery.

## Three altitudes (cross-tool keeper)

> Raw witnesses observe facts. SQL composes suspicions. Claim preflight decides what those suspicions are allowed to mean.

`nq-blackbox` operates at the **witness** altitude. Probes observe protocol-facing facts from a declared vantage. SQL composition of probe results with NQ substrate state lives in the consuming NQ tree (`nq/docs/coverage/sql-composed-checks.md`). Claim-preflight refusal families (what those compositions are allowed to mean) live in NQ gap docs.

## Three probe buckets

The probe catalog (see [`docs/PROBE_CATALOG.md`](docs/PROBE_CATALOG.md)) is organized into three buckets, each with a different operational purpose:

1. **Overlap probes** — touch things NQ already covers, so cross-vantage comparison works. Used to validate that the integration is functioning at all. Internal witness says X; external blackbox vantage says Y; agreement or disagreement is itself testimony.
2. **Contradiction probes** — the operational payoff. Internal green / external red (or vice versa). Process exists + port listens + HTTP probe fails. DNS resolves + TLS handshake fails. TLS valid + application body wrong. The class of "facade contradicts substrate" failures that NQ is specifically designed to refuse to launder.
3. **New vantage probes** — external HTTP(S) reachability for NQ's own surfaces, TLS expiry / chain / SNI sanity, DNS from a specific resolver / vantage, TCP connect-only where HTTP would overclaim. Coverage NQ does not have today.

What gets configured here is bounded by what each probe can honestly testify to, **not** by what monitoring conventionally promises. A `probe_success` is testimony from a declared vantage at an observation time — it is not "the service is healthy."

## Precondition (now satisfied)

NQ's Prometheus scraper must stamp each ingested sample with the scrape target that produced it. Otherwise two blackbox probes both emitting `probe_success` for different `target=` parameters become indistinguishable in NQ's store, and SQL composition turns to soup.

This precondition is **satisfied as of nq commit `1ea2000`** ("Stamp Prometheus scrape target provenance on MetricSample"). `MetricSample` now carries `scrape_target_name` and `scrape_target_url`. Without this, the rest of the lab cannot compose cleanly. See [`docs/NQ_INTEGRATION.md`](docs/NQ_INTEGRATION.md) for the details.

## Layout

```
nq-blackbox/
  README.md                  — this file
  blackbox.yml               — blackbox_exporter module configuration (stub)
  targets/
    local.yml                — probe targets for the local host (stub)
    linode.yml               — probe targets for the Linode external vantage (stub)
  scripts/
    smoke_probe.sh           — smoke harness (stub, not yet implemented)
  docs/
    PROBE_CATALOG.md         — overlap / contradiction / new-vantage probe inventory
    NQ_INTEGRATION.md        — how blackbox samples flow into NQ; the provenance precondition
```

`blackbox.yml` and `targets/*.yml` are currently **stubs** (no probe is promoted until its full 5-criterion path holds — see `docs/PROBE_CATALOG.md`). `scripts/smoke_probe.sh` is **implemented** (2026-06-12): it runs the full ingestion-path contract with distinct exit codes per incident class. The NQ-side provenance precondition is also closed (nq migration 058 — provenance is now queryable, not wire-only). What remains for the first probe promotion is a deployed `blackbox_exporter` + an NQ scrape loop (a deploy-session task), not a missing data path.

## What this repo is not

- Not a fork of `blackbox_exporter`. Use upstream.
- Not a Prometheus replacement. NQ ingests Prom-shaped samples but does not become Prometheus.
- Not a claim engine. `probe_success=1` is testimony, not a verdict. NQ decides what it is allowed to mean.
- Not a dashboard. Operator-facing surfaces live on the NQ side, if they live at all.
- Not a discovery system. Targets are declared in `targets/*.yml`; nothing auto-discovers.
- Not security tooling. Probes do not test authentication, authorization, or vulnerability surfaces.

## Related

- [`nq`](https://github.com/unpingable/nq) — NQ proper, the consumer side of this lab. The precondition for safe composition (`MetricSample` scrape-target provenance) lives there.
- Upstream blackbox exporter: <https://github.com/prometheus/blackbox_exporter>
- NQ's `docs/coverage/sql-composed-checks.md` — composed-SQL-check workbench where probe results compose with substrate state at the SQL altitude.
- NQ's `docs/CLAIM_ADMISSIBILITY_MATTERS.md` — why the three altitudes exist at all.
