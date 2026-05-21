# NQ Integration

How blackbox-exporter samples flow into NQ, and the discipline that keeps that flow honest.

## Path

```
[ blackbox_exporter on host H ]   ← runs as a separate process / service unit
        |
        |  /probe?module=...&target=...
        v
[ NQ scraper on host H' ]        ← configured via NQ's prometheus_targets
        |
        |  parses Prometheus text exposition format
        |  stamps each sample with scrape_target_name / scrape_target_url
        v
[ MetricSample in NQ DB ]         ← samples retain source identity
        |
        |  (SQL composition runs here, NOT in this repo)
        v
[ Operator query / sql-composed-checks.md ]
```

The path crosses three boundaries:

1. **Probe → exporter exposition.** Blackbox does its own evaluation against the probe target and emits `probe_*` metrics in Prometheus text format on its `/metrics`-like `/probe` endpoint.
2. **Exporter exposition → NQ samples.** NQ's Prometheus scraper (`crates/nq/src/collect/prometheus.rs`) parses the text into `MetricSample` instances. Parsing stays pure; provenance is stamped immediately after parse by `stamp_with_target` (notquery commit `1ea2000`).
3. **NQ samples → operator queries.** Stored samples carry `name`, `labels`, `value`, `metric_type`, **and** `scrape_target_name` / `scrape_target_url`. SQL composition keys off the provenance fields.

Each boundary fails differently. The smoke harness (`scripts/smoke_probe.sh` when implemented) must be able to distinguish them.

## Precondition (now satisfied)

NQ's `MetricSample` must carry scrape-target provenance. Without it, two blackbox probes both emitting `probe_success` for different `target=` query parameters fuse into indistinguishable rows in NQ's store, and any SQL composition over them produces nonsense.

**Status:** satisfied as of notquery commit `1ea2000` ("Stamp Prometheus scrape target provenance on MetricSample"). Each `MetricSample` now carries two optional fields:

- `scrape_target_name: Option<String>` — the configured target name (e.g. `"blackbox_labelwatch_health"`)
- `scrape_target_url: Option<String>` — the `/probe?...` URL the scraper hit

Both are additive (`#[serde(default, skip_serializing_if = "Option::is_none")]`); older payloads without them deserialize cleanly. Stamping happens at the struct level, not via injected `nq_*` labels, so exporter-emitted labels are never clobbered.

## What blackbox can testify to (from NQ's view)

Blackbox emits metrics like `probe_success`, `probe_duration_seconds`, `probe_http_status_code`, `probe_dns_lookup_time_seconds`, `probe_ssl_earliest_cert_expiry`, etc. From NQ's vantage these are **scoped substrate observations**, not service-health claims.

| Blackbox metric (illustrative) | NQ-side admissible claim | NQ-side inadmissible claim |
|---|---|---|
| `probe_success` | "Probe from vantage V at T concluded success under module M" | "Service is healthy"; "users can reach it"; "next probe will succeed" |
| `probe_http_status_code` | "Endpoint returned code C from vantage V at T" | "Application is functioning"; "endpoint is broken"; "users see code C" |
| `probe_dns_lookup_time_seconds` | "DNS resolution from resolver R took N seconds at T" | "DNS is slow globally"; "users experience latency"; "resolver is broken" |
| `probe_ssl_earliest_cert_expiry` | "Earliest certificate in chain not_after observed at T is timestamp E" | "TLS is valid for all clients"; "renewal pipeline is healthy"; "trust chain is verified" |

The pattern: probe metrics testify to *what the probe observed from its vantage*. Promoting that into causal or service-health claims is what NQ's claim-preflight surface refuses.

## What NQ does with these samples

NQ ingests samples and stores them; that's the contract this lab depends on. Beyond that:

- **No automatic claims.** A `probe_success=0` sample does not, on its own, mint any claim in NQ. It is data.
- **No automatic alerts.** This lab does not configure alerting. If alerts exist, they live elsewhere in operator policy.
- **SQL composition is the next layer.** Operators may write queries that join probe samples with NQ's substrate state (services_current, monitored_dbs_current, warning_state, etc.); concrete candidates live in `notquery/docs/coverage/sql-composed-checks.md` — particularly `service_facade_inconsistency` and `dns_response_kind_correlated_with_service_status`.
- **Composed claims (if they ever land) live on the NQ side.** A future composed-claim family that consumes probe samples (e.g. a `service_facade_contradiction` claim kind) would be authored in NQ, not here. This repo stays at the witness altitude.

## Smoke test contract (when implemented)

The smoke harness at `scripts/smoke_probe.sh` (currently a stub) must validate the full path:

1. Blackbox exporter is reachable on its configured port.
2. A known-good `/probe` invocation returns HTTP 200 with `probe_success 1` in the exposition body.
3. NQ's scraper picks up the sample on its next scheduled pulse.
4. The stored `MetricSample` carries the expected `scrape_target_name` and `scrape_target_url`.
5. The probe content (`name`, `labels`, `value`) survives unaltered.

Failure to satisfy any one of these is a distinct incident class:

- (1) → exporter not running or misconfigured.
- (2) → probe target legitimately failing OR exporter module misconfigured.
- (3) → NQ scraper not configured for this target OR pulse interval too long for the test window.
- (4) → NQ-side regression in stamp_with_target.
- (5) → NQ-side regression in parse_exposition.

The smoke harness names which incident class fired. Conflating them is the bug a real harness exists to refuse.

## Out of scope

- NQ does not interpret blackbox module semantics. The exporter does its own success determination; NQ just ingests the result.
- NQ does not mint composed claims from probe samples in this layer. SQL composition is the first place suspicion can be voiced; claim preflight is where suspicion becomes admissible refusal.
- This repo does not deploy or supervise the exporter. Use systemd, container orchestration, whatever the host runs. Configuration that ships here is the exporter's own `blackbox.yml`, not a deployment manifest.

## Related (in `notquery`)

- `crates/nq-core/src/wire.rs` — `MetricSample` definition (provenance fields).
- `crates/nq/src/collect/prometheus.rs` — `scrape_target` + `stamp_with_target` helpers.
- `docs/coverage/sql-composed-checks.md` — the SQL workbench where probe samples compose with substrate state.
- `docs/CLAIM_ADMISSIBILITY_MATTERS.md` — why the three altitudes are kept distinct.
- `docs/CLAIM_PREFLIGHT.md` — where suspicions become refusable claims.
