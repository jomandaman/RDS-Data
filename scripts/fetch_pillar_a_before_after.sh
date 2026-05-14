#!/bin/bash
# Pillar A: side-by-side BEFORE / AFTER attack-vector code-pattern counts.
#
# Pre-Phase-0 baseline = commit eaf0956 (Feb 3 2026, last commit before Phase 0).
# Post-Phase-0 = current HEAD.
#
# For each attack class, count vulnerable code patterns in both checkouts.
# Long-form CSV: one row per (version, attack_category, metric_name).

set -e
SRC="/Users/josiahzacharias/Library/Mobile Documents/com~apple~CloudDocs/School/UWB/CSS 595 (Final Project)/source/rep5_0209"
DEST="/Users/josiahzacharias/Library/Mobile Documents/com~apple~CloudDocs/School/UWB/CSS 595 (Final Project)/Final Paper/RDS Data/data/pillar_a"
PRE_COMMIT="eaf0956"
WORKTREE="/tmp/rep5_pre_phase0"

cleanup() {
  if [[ -d "$WORKTREE" ]]; then
    cd "$SRC"
    git worktree remove --force "$WORKTREE" 2>/dev/null || rm -rf "$WORKTREE"
  fi
}
trap cleanup EXIT

echo "Setting up pre-Phase-0 worktree at $PRE_COMMIT ..."
cd "$SRC"
[[ -d "$WORKTREE" ]] && git worktree remove --force "$WORKTREE" 2>/dev/null
git worktree add --detach "$WORKTREE" "$PRE_COMMIT" >/dev/null 2>&1
echo "  worktree at $WORKTREE"

# Per-version, per-attack-class scan. One row per (version, category, metric).
emit_rows() {
  local version="$1" dir="$2"
  cd "$dir"

  local sqli_raw sqli_concat xss_echo lfi protect_calls jq1 hardcoded prep_calls jq37 dotenv

  # Count helper: pipe through wc -l so a zero result doesn't trigger set -e
  cnt() { ( "$@" 2>/dev/null || true ) | wc -l | tr -d ' '; }
  cnt_nocomment() { ( "$@" 2>/dev/null || true ) | grep -v '^[^:]*:[[:space:]]*//' | wc -l | tr -d ' '; }

  sqli_raw=$(cnt_nocomment    grep -rE 'mysqli_query' --include='*.php' .)
  sqli_concat=$(cnt_nocomment grep -rE '(mysqli_query|mysql_query).*\$_(GET|POST|REQUEST|COOKIE)' --include='*.php' .)
  xss_echo=$(cnt_nocomment    grep -rE '(echo|print)[[:space:]]+\$_(GET|POST|REQUEST|COOKIE)' --include='*.php' .)
  lfi=$(cnt_nocomment         grep -rE '(include|require)(_once)?[^a-zA-Z0-9_].*\$_(GET|POST|REQUEST|COOKIE)' --include='*.php' .)
  protect_calls=$(cnt_nocomment grep -rE 'protect\(' --include='*.php' .)
  jq1=$(cnt grep -rlE 'jquery[-_.]?1\.(7|12|[0-9]+)\.[0-9]+' --include='*.php' --include='*.html' .)
  hardcoded=$(cnt_nocomment grep -rE '(password|api_key|secret)[[:space:]]*=[[:space:]]*["'"'"'][^[:space:]"'"'"'$]+' --include='*.php' .)

  prep_calls=$(cnt grep -rE 'db_(query|execute|select_one|select_all|insert|count)\(' --include='*.php' .)
  jq37=$(cnt grep -rlE 'jquery-3\.7\.1|jquery/3\.7\.1' --include='*.php' --include='*.html' .)
  dotenv=$(cnt grep -rl 'Dotenv' --include='*.php' .)

  echo "$version,SQL injection,Raw mysqli_query references,$sqli_raw"
  echo "$version,SQL injection,Direct \$_GET/POST in SQL string,$sqli_concat"
  echo "$version,XSS reflection,Echo/print of \$_GET/POST,$xss_echo"
  echo "$version,File inclusion,include/require with \$_GET/POST,$lfi"
  echo "$version,SQL injection (legacy escape),protect() escape calls,$protect_calls"
  echo "$version,Outdated client lib (CVE),Files referencing jQuery 1.x,$jq1"
  echo "$version,Hardcoded credentials,password/secret literal assignments,$hardcoded"
  echo "$version,Protection introduced,Prepared-statement call sites,$prep_calls"
  echo "$version,Protection introduced,Files referencing jQuery 3.7.1,$jq37"
  echo "$version,Protection introduced,Files loading Dotenv (.env),$dotenv"
}

{
  echo "version,attack_category,metric,count"
  emit_rows "pre_phase_0"  "$WORKTREE"
  emit_rows "post_phase_0" "$SRC"
} > "$DEST/pillar_a_before_after.csv"

echo
echo "Result:"
cat "$DEST/pillar_a_before_after.csv"
echo
echo "  -> $DEST/pillar_a_before_after.csv"
