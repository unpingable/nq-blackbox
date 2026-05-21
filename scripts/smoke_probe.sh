#!/usr/bin/env bash
# nq-blackbox: smoke harness for blackbox exporter + NQ ingestion path
#
# Not yet implemented. This script frames the smoke-test sequence so
# the eventual implementation has somewhere to land.
#
# Expected sequence:
#   1. Verify the local blackbox_exporter is responding on its
#      configured port (default 9115).
#   2. Issue a /probe request for a known-good target + module;
#      confirm HTTP 200 and `probe_success 1` in the exposition body.
#   3. Trigger an NQ scrape pulse (or wait for the next scheduled
#      pulse to complete).
#   4. Query the NQ SQLite database for samples named `probe_success`
#      with the expected `scrape_target_name`; confirm provenance is
#      stamped and the value matches what the exporter emitted.
#   5. Report PASS/FAIL with enough detail to diagnose a half-baked
#      ingestion path (samples present but unstamped → NQ-side
#      regression; samples missing → scraper not configured; samples
#      present but `probe_success=0` → external substrate failure,
#      not a smoke failure).
#
# Each step has its own failure mode. The smoke harness must
# distinguish "blackbox is broken" from "NQ isn't ingesting" from
# "the probe target is legitimately failing" — those are three
# different incidents wearing the same red shirt.

set -euo pipefail
echo "nq-blackbox/scripts/smoke_probe.sh: not yet implemented" >&2
exit 1
