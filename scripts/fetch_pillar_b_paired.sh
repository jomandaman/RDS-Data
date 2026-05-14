#!/bin/bash
# Pillar B: paired old-vs-new endpoint timings, AUTHENTICATED when possible.
# Logs in once with dev creds, then times pairs of legacy PHP vs new REST/SPA
# endpoints that fetch the same logical data. Plus a bounded concurrent burst.
set -e
EC2="https://13.222.3.49"
DEST="/Users/josiahzacharias/Library/Mobile Documents/com~apple~CloudDocs/School/UWB/CSS 595 (Final Project)/Final Paper/RDS Data/data/pillar_b"
RUNS=30

# Dev credentials (override via env if rotated)
DEV_USER="${DEV_USER:-josiahzacharias@gmail.com}"
DEV_PASS="${DEV_PASS:-Dev2025!}"

echo "1. Logging in as $DEV_USER..."
COOKIES="/tmp/pillar_b_cookies.txt"
rm -f "$COOKIES"
curl -ksL -c "$COOKIES" "$EC2/public/httpdocs/about/NearVisionInstitute/Company/signin.php" -o /dev/null
curl -ksL -c "$COOKIES" -b "$COOKIES" \
  -d "username=$DEV_USER&password=$DEV_PASS" \
  "$EC2/login/functions/login_sb.php" -o /tmp/login_res.html

auth_check=$(curl -ks -b "$COOKIES" -o /dev/null -w "%{http_code}" "$EC2/api/v1/dashboard/messages")
if [[ "$auth_check" != "200" ]]; then
  echo "  ERROR: login did not produce a valid session (got HTTP $auth_check)"
  exit 1
fi
echo "  Login OK"

# Discover a real student ID for the per-patient pair
STUDENT_ID=$(curl -ks -b "$COOKIES" "$EC2/api/v1/students" 2>/dev/null \
  | python3 -c "import sys,json
try:
    d = json.loads(sys.stdin.read())
    items = d.get('students') or d.get('data') or []
    if isinstance(items, list) and items:
        print(items[0].get('StudentID') or items[0].get('id') or '')
except: pass" 2>/dev/null)
if [[ -z "$STUDENT_ID" ]]; then
  STUDENT_ID="1"
fi
echo "  Using student id: $STUDENT_ID"

# side|auth|label|path|description
declare -a PAIRS=(
  "old|public|legacy_signin|/public/httpdocs/about/NearVisionInstitute/Company/signin.php|Login form (legacy PHP, full HTML)"
  "new|public|api_health|/api/v1/health|REST first-touch (JSON)"
  "old|auth|legacy_patient_list|/Professional/prof_home1.php|Patient roster (legacy PHP)"
  "new|auth|api_students|/api/v1/students|Patient roster (REST JSON)"
  "old|auth|legacy_dashboard_msgs|/Professional/prof_home.php|Clinician home (legacy PHP)"
  "new|auth|api_dashboard_msgs|/api/v1/dashboard/messages|Dashboard messages (REST JSON)"
  "old|auth|legacy_patient_profile|/Professional/prof_profile1.php?id=$STUDENT_ID|Patient profile (legacy PHP)"
  "new|auth|api_patient_profile|/api/v1/students/$STUDENT_ID/profile|Patient profile (REST JSON)"
  "old|auth|legacy_toolbox|/MAPs/maps_toolbox.php|Content library (legacy PHP)"
  "new|auth|api_toolbox|/api/v1/toolbox|Content library (REST JSON)"
)

echo
echo "2. Running $RUNS timed requests per endpoint..."
{
  echo "side,auth,label,endpoint,description,run,total_ms,ttfb_ms,size_bytes,http_code"
  for spec in "${PAIRS[@]}"; do
    side="${spec%%|*}"; rest="${spec#*|}"
    auth="${rest%%|*}"; rest="${rest#*|}"
    label="${rest%%|*}"; rest="${rest#*|}"
    path="${rest%%|*}"; description="${rest#*|}"
    cookie_arg=""
    [[ "$auth" == "auth" ]] && cookie_arg="-b $COOKIES"
    for i in $(seq 1 $RUNS); do
      out=$(curl -ks $cookie_arg -o /dev/null -w "%{time_total}|%{time_starttransfer}|%{size_download}|%{http_code}" "$EC2$path")
      total="${out%%|*}"; rest2="${out#*|}"
      ttfb="${rest2%%|*}"; rest2="${rest2#*|}"
      size="${rest2%%|*}"; code="${rest2##*|}"
      total_ms=$(awk "BEGIN {printf \"%.1f\", $total * 1000}")
      ttfb_ms=$(awk "BEGIN {printf \"%.1f\", $ttfb * 1000}")
      desc_q="\"${description//\"/\"\"}\""
      echo "$side,$auth,$label,$path,$desc_q,$i,$total_ms,$ttfb_ms,$size,$code"
    done
  done
} > "$DEST/pillar_b_paired_timings.csv"
echo "  -> pillar_b_paired_timings.csv ($(wc -l < "$DEST/pillar_b_paired_timings.csv") rows)"

echo
echo "3. Bounded concurrent burst on /api/v1/health (n=100, c=10) ..."
ab -k -n 100 -c 10 -e "$DEST/pillar_b_ab_concurrent.csv" "$EC2/api/v1/health" 2>&1 \
  | tee "$DEST/pillar_b_ab_summary.txt" \
  | grep -E "Requests per second|Time per request|Transfer rate|Failed requests|Complete requests"

echo
echo "Done."
