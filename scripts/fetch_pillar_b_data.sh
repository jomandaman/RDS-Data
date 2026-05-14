#!/bin/bash
# Fetch Pillar B live performance data from dev EC2.
# Auth-free benchmark targets only. Re-run any time.
set -e
EC2="https://13.222.3.49"
DEST="/Users/josiahzacharias/Library/Mobile Documents/com~apple~CloudDocs/School/UWB/CSS 595 (Final Project)/Final Paper/RDS Data/data/pillar_b"
RUNS=30  # iterations per endpoint

# Auth-free endpoints we can benchmark
declare -a TARGETS=(
  "react_api|/api/v1/health|REST API health endpoint (JSON response)"
  "legacy_signin|/public/httpdocs/about/NearVisionInstitute/Company/signin.php|Legacy PHP login page (full HTML)"
  "legacy_recover|/public/httpdocs/about/NearVisionInstitute/Company/recover-account.php|Legacy PHP recovery page"
  "legacy_index|/|Site root (redirects)"
)

echo "Running $RUNS timed requests per endpoint..."
{
  echo "label,endpoint,description,run,total_ms,ttfb_ms,size_bytes,http_code"
  for spec in "${TARGETS[@]}"; do
    label="${spec%%|*}"; rest="${spec#*|}"
    path="${rest%%|*}"; description="${rest#*|}"
    for i in $(seq 1 $RUNS); do
      out=$(curl -ks -o /dev/null -w "%{time_total}|%{time_starttransfer}|%{size_download}|%{http_code}" "$EC2$path")
      total="${out%%|*}"; rest="${out#*|}"
      ttfb="${rest%%|*}"; rest="${rest#*|}"
      size="${rest%%|*}"; code="${rest#*|}"
      total_ms=$(awk "BEGIN {printf \"%.1f\", $total * 1000}")
      ttfb_ms=$(awk "BEGIN {printf \"%.1f\", $ttfb * 1000}")
      echo "$label,$path,$description,$i,$total_ms,$ttfb_ms,$size,$code"
    done
  done
} > "$DEST/pillar_b_timings.csv"
echo "  -> pillar_b_timings.csv ($(wc -l < "$DEST/pillar_b_timings.csv") rows)"
echo "Done."
