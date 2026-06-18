# Probe Catalog

Inventory of probe candidates, organized into the three buckets named in the [`README`](../README.md). Each row names a probe candidate, its intended module, what it would honestly testify to from its declared vantage, and a short list of inadmissible claims a careless reader might infer.

Naming candidates is not authorizing implementation. Each entry stays in `candidate` status until a `blackbox.yml` module + `targets/*.yml` entry + smoke result lands together. This document is the map; the configs in the sibling directories will be the territory.

## Top rule

> A probe result is testimony from a declared vantage at an observation time. It is not service truth.

A `probe_success` sample says the probe — under module M, from vantage V, at time T — concluded success. It does not say:

- the service is healthy
- users can reach it
- the application is functioning
- the network is fine
- the certificate is trustworthy for all clients
- the next probe will succeed

Those conclusions, if they are drawn at all, are drawn downstream by NQ's claim-preflight machinery — never by the probe itself, never by this catalog.

## Bucket 1 — Overlap probes

Touch things NQ already covers internally. Used to validate the integration path is functioning, and to surface internal-vs-external disagreement when it appears.

| Candidate | Module | Vantage | Honestly testifies to | Inadmissible claims |
|---|---|---|---|---|
| `nq_aggregator_http_localhost` | `http_2xx` | local | "Local HTTP probe of NQ aggregator returned 2xx at T" | "NQ is healthy"; "NQ is reachable for external users"; "all NQ surfaces are up" |
| `labelwatch_health_localhost` | `http_2xx` | local | "Local HTTP probe of labelwatch /health returned 2xx at T" | "labelwatch is fine"; "labelwatch is processing"; "labelwatch is not dropping events" |
| `dns_neutralzone_localhost` | `dns_a` | local | "Local resolver returned an A record for nq.neutral.zone at T" | "DNS is globally correct"; "nq.neutral.zone resolves identically from every vantage"; "the record's value is authoritative" |

## Bucket 2 — Contradiction probes

The operational payoff. Probes that create cleanly testable internal-vs-external (or substrate-vs-facade) disagreement.

| Candidate | Module | Vantage | Honestly testifies to | Inadmissible claims |
|---|---|---|---|---|
| `service_facade_http` | `http_strict` | local + linode | "HTTP probe of service S from vantage V observed status code C; matched/unmatched declared whitelist" | "S is healthy"; "S is down"; "users are affected"; "root cause is application" |
| `dns_then_http_split` | `http_2xx` (combined with `dns_a`) | linode | "DNS resolved name N; subsequent HTTP probe to the resolved address from vantage V returned status C" | "DNS is correct"; "service is reachable"; "endpoint is broken" |
| `tls_handshake_app_body_split` | `http_strict` with TLS | linode | "TLS handshake to endpoint E succeeded; subsequent HTTP request returned body matching/mismatching declared contract" | "TLS is valid for all clients"; "application is functioning"; "user-facing experience is intact" |
| `process_listener_vs_http` | (composed with NQ services_current) | local | "NQ reports service S process present and listener bound; HTTP probe from same host to same listener returned status C" | "S is up"; "S is down"; "listener is the accept loop"; "the daemon is responsive" |

The last row is composed cross-tool: NQ's internal observation of process + listener presence vs. a local HTTP probe of the same listener. That composition belongs to NQ's SQL workbench, not to blackbox itself — see `nq/docs/coverage/sql-composed-checks.md`.

## Bucket 3 — New vantage probes

Coverage NQ does not have today. Each adds an external observation surface.

| Candidate | Module | Vantage | Honestly testifies to | Inadmissible claims |
|---|---|---|---|---|
| `external_http_nq_neutralzone` | `http_2xx` | linode | "HTTP probe of nq.neutral.zone from linode vantage returned 2xx at T" | "NQ is reachable for users"; "all clients see the same response"; "CDN behavior is consistent" |
| `tls_expiry_nq_neutralzone` | `tls_connect` | linode | "TLS certificate observed at nq.neutral.zone has not_after T; expires within window W" | "TLS is valid for all clients"; "trust chain is verified"; "renewal pipeline is healthy" |
| `dns_external_resolver` | `dns_a` | linode | "External resolver R returned answer A for name N at T" | "DNS is correct globally"; "all resolvers agree"; "authoritative-zone correctness" |
| `tcp_connect_only` | `tcp_connect` | linode | "TCP three-way handshake to host:port succeeded at T" | "service accepts real protocol"; "listener is the accept loop"; "application is up" |

## Out of scope (explicit non-goals)

- **ICMP probes** as a default surface — useful but often blocked by middleboxes, policy-shaped, and easily over-interpreted. Park unless a forcing case appears.
- **gRPC probes** without a concrete gRPC target. Decorative without a real service.
- **Body regex probes** without an explicit endpoint contract. "Health" vibes-checks dressed up as assertions.
- **Authentication probes**. Authenticated endpoints are policy surfaces; this repo stays at the protocol layer.
- **Security probes** (vulnerability scans, port enumeration, etc.). Adjacent discipline, separate corpus.
- **Performance benchmarks**. Probe latency is testimony about probe latency, not about user-perceived performance.

## Promotion path

A probe candidate moves from this catalog to a working `blackbox.yml` module + `targets/*.yml` entry + smoke harness step when:

1. The module's success criteria are explicit enough to land in `blackbox.yml`.
2. The target's `name` is operator-legible and stable.
3. The `scripts/smoke_probe.sh` step that exercises it is implemented. **(Done 2026-06-12** — the harness implements the full 5-step contract from `docs/NQ_INTEGRATION.md` with distinct exit codes per incident class. Its failure-discrimination is verified; the live-exporter pass-path needs a deploy session.)
4. NQ on the receiving side actually ingests `probe_*` samples with provenance intact. **Precondition now genuinely satisfied:** `1ea2000` stamped provenance on the wire struct only; it was dropped before persistence. nq **migration 058** (2026-06-12) persists `scrape_target_name`/`scrape_target_url` onto the `series` dictionary, queryable via `v_metrics`, so `smoke_probe.sh` step 4 can actually check it. **Caveat:** series identity is still `(metric_name, labels_json)`, so two probes emitting identical bare `probe_success` from different targets collapse to one series and are flagged `scrape_target_collision=1` (ambiguous, not laundered). Distinguishing them is the deferred identity migration (`nq/docs/working/decisions/NQ_SCRAPE_TARGET_IDENTITY_SCOPE.md`). Bucket-1 probes that carry a distinguishing `instance`/`job` label avoid the collapse; bare-metric multi-target promotion waits on the identity migration.
5. The honestly-testifies-to / inadmissible-claims rows above survive contact with the real exporter output.

Until all five are true, the candidate stays in this document and nowhere else. **As of 2026-06-12:** criteria 3 and 4 are met; criteria 1, 2, 5 (and the live run of 4) need a deployed `blackbox_exporter` + an NQ scrape loop — a deploy-session task, no longer a missing data path.
