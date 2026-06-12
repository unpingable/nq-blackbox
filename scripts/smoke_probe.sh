#!/usr/bin/env bash
# nq-blackbox: smoke harness for blackbox_exporter + NQ ingestion path.
#
# Validates the full path (per docs/NQ_INTEGRATION.md "Smoke test contract"):
#   1. blackbox_exporter reachable on its port.
#   2. a /probe for a known-good module+target returns HTTP 200 with
#      `probe_success 1` in the exposition body.
#   3. NQ ingests the sample (next pulse, or already pulsed).
#   4. the stored sample carries the expected scrape_target_name (provenance —
#      queryable since notquery migration 058).
#   5. the probe content survives unaltered.
#
# Each failure is a DISTINCT incident class, reported as such. Conflating
# "blackbox is broken" / "NQ isn't ingesting" / "the probe target is
# legitimately failing" is the bug this harness exists to refuse.
#
# Config via env (defaults suit the single-host demo):
#   BB_HOST          blackbox exporter host           (default 127.0.0.1)
#   BB_PORT          blackbox exporter port           (default 9115)
#   BB_MODULE        probe module                     (default http_2xx)
#   BB_TARGET        probe target                     (default http://127.0.0.1:9848/)
#   NQ_DB            path to NQ sqlite db             (default ./nq.db)
#   NQ_TARGET_NAME   expected scrape_target_name      (default smoke_probe)
#   PULSE_WAIT_S     seconds to wait for an NQ pulse  (default 0 = assume pulsed)
#
# Exit codes: 0 PASS; 1 exporter down; 2 probe failing; 3 NQ not ingesting;
#             4 provenance regression; 5 content regression; 9 usage/env error.

set -uo pipefail

BB_HOST="${BB_HOST:-127.0.0.1}"
BB_PORT="${BB_PORT:-9115}"
BB_MODULE="${BB_MODULE:-http_2xx}"
BB_TARGET="${BB_TARGET:-http://127.0.0.1:9848/}"
NQ_DB="${NQ_DB:-./nq.db}"
NQ_TARGET_NAME="${NQ_TARGET_NAME:-smoke_probe}"
PULSE_WAIT_S="${PULSE_WAIT_S:-0}"

probe_url="http://${BB_HOST}:${BB_PORT}/probe?module=${BB_MODULE}&target=${BB_TARGET}"

fail() { echo "SMOKE FAIL [$2]: $1" >&2; exit "$2"; }

command -v curl >/dev/null 2>&1 || fail "curl not found" 9

# --- Step 1: exporter reachable -------------------------------------------
if ! curl -fsS -m 5 "http://${BB_HOST}:${BB_PORT}/-/healthy" >/dev/null 2>&1; then
    fail "blackbox_exporter not reachable at ${BB_HOST}:${BB_PORT} (exporter not running or misconfigured)" 1
fi

# --- Step 2: /probe returns 200 + probe_success 1 -------------------------
body="$(curl -fsS -m 15 "${probe_url}" 2>/dev/null)" \
    || fail "/probe request failed (exporter up but module/target rejected): ${probe_url}" 2
if ! grep -qE '^probe_success[[:space:]]+1(\.0+)?$' <<<"${body}"; then
    got="$(grep -E '^probe_success' <<<"${body}" || echo 'probe_success absent')"
    fail "probe target legitimately failing OR module misconfigured (${got})" 2
fi

# --- Step 3: NQ has the db --------------------------------------------------
command -v sqlite3 >/dev/null 2>&1 || fail "sqlite3 not found (cannot verify NQ ingestion)" 9
[ -f "${NQ_DB}" ] || fail "NQ db not found at ${NQ_DB} (scraper not deployed here?)" 3
if [ "${PULSE_WAIT_S}" -gt 0 ]; then sleep "${PULSE_WAIT_S}"; fi

# --- Step 4: provenance is persisted and queryable -------------------------
# Migration 058 put scrape_target_name on the series dictionary. A sample with
# our target name must exist and be attributable (collision flag clear).
prov="$(sqlite3 "${NQ_DB}" \
    "SELECT COUNT(*) FROM series
      WHERE metric_name='probe_success'
        AND scrape_target_name='${NQ_TARGET_NAME}'
        AND scrape_target_collision=0;" 2>/dev/null)" \
    || fail "NQ db query failed (schema older than migration 058? run nq migrations)" 4
if [ "${prov:-0}" -lt 1 ]; then
    ambig="$(sqlite3 "${NQ_DB}" \
        "SELECT COUNT(*) FROM series
          WHERE metric_name='probe_success' AND scrape_target_collision=1;" 2>/dev/null || echo 0)"
    if [ "${ambig:-0}" -gt 0 ]; then
        fail "provenance AMBIGUOUS for probe_success (multi-target collapse; identity migration needed before composition)" 4
    fi
    fail "NQ not ingesting probe_success with scrape_target_name='${NQ_TARGET_NAME}' (scraper not configured for this target, or stamp regression)" 3
fi

# --- Step 5: probe content survives unaltered ------------------------------
val="$(sqlite3 "${NQ_DB}" \
    "SELECT m.value FROM metrics_current m
       JOIN series s ON s.series_id=m.series_id
      WHERE s.metric_name='probe_success'
        AND s.scrape_target_name='${NQ_TARGET_NAME}' LIMIT 1;" 2>/dev/null)"
case "${val}" in
    1|1.0|1.000000) : ;;
    *) fail "probe content altered in ingest: probe_success value='${val:-<none>}' (parse regression)" 5 ;;
esac

echo "SMOKE PASS: ${BB_MODULE}/${BB_TARGET} -> probe_success=1 ingested as scrape_target_name='${NQ_TARGET_NAME}' (provenance queryable, content intact)"
exit 0
