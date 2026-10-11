# Actual Budget's steps for the chassis harness (chassis/tests/e2e.sh <appdir> act).
# There's no DSM here, so "DSM's certificate" falls back to a self-signed one — HTTPS from the start.
app_e2e_answers() { printf "TLS='dsm'\n"; }
wait_for() { local i; for i in $(seq 1 "$2"); do touch "$VAR/watching"; jq -e "$1" "$VAR/status.json" >/dev/null 2>&1 && return 0; sleep 1; done; return 1; }
secret() { local s; s=$(jq -r 'select(.kind == "signin") | .password' "$VAR/secret.json" 2>/dev/null); rm -f "$VAR/secret.json"; printf '%s' "$s"; }
login() {   # url password → a session token, or nothing
  curl -sk -H 'Content-Type: application/json' -d "$(jq -cn --arg p "$2" '{loginMethod: "password", password: $p}')" "$1/account/login" | jq -r '.data.token // empty'
}
token_ok() { [[ "$(curl -sk -H "x-actual-token: $2" "$1/sync/list-user-files" | jq -r .status)" == ok ]]; }
upload() {   # url token id name → a small budget file, as a device uploads one
  local z; z=$(mktemp -d); printf '{"id":"%s","budgetName":"%s"}' "$3" "$4" > "$z/metadata.json"; head -c 4096 /dev/urandom > "$z/db.sqlite"
  (cd "$z" && python3 -c "import zipfile; z = zipfile.ZipFile('b.zip', 'w'); z.write('metadata.json'); z.write('db.sqlite'); z.close()")
  curl -sk -X POST -H "x-actual-token: $2" -H "x-actual-file-id: $3" -H "x-actual-name: $4" -H 'x-actual-format: 2' -H 'Content-Type: application/encrypted-file' \
    --data-binary @"$z/b.zip" "$1/sync/upload-user-file" | jq -r .status; rm -rf "$z"
}
app_e2e_act() {
  local fail=0 url="https://127.0.0.1:$PORT" pw pw2 tok tok2
  log "actual"
  echo "  (health: $(curl -sk "$url/health" | jq -r .status), version $(jq -r .version "$VAR/status.json"))"
  [[ "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/health")" != 200 ]] && echo "  ok   HTTPS from the start (plain HTTP isn't served)" || { echo "  FAIL plain http answers"; fail=1; }
  jq -e '.app.tls.mode == "dsm" and .app.tls.source == "self" and .app.tls.cert.self_signed == true' "$VAR/status.json" >/dev/null && echo "  ok   no DSM certificate here: self-signed instead, and the window says so" || { echo "  FAIL tls: $(jq -c .app.tls "$VAR/status.json")"; fail=1; }
  # The server's password: set at the first start, shown once.
  pw=$(secret)
  [[ ${#pw} -ge 20 ]] && echo "  ok   a one-time password was left for the window" || { echo "  FAIL no password secret"; fail=1; }
  tok=$(login "$url" "$pw"); [[ -n "$tok" ]] && echo "  ok   it signs in to Actual" || { echo "  FAIL sign-in"; fail=1; }
  # A budget, as a device uploads one; the window lists it.
  [[ "$(upload "$url" "$tok" e2e-budget-1 'Household & "Bills"')" == ok ]] && echo "  ok   a device uploaded a budget" || { echo "  FAIL upload"; fail=1; }
  wait_for '.app.budgets | length == 1 and .[0].name == "Household & \"Bills\"" and .[0].size > 4000 and (.[0].encrypted | not)' 30 && echo "  ok   listed: name intact, size, not encrypted" || { echo "  FAIL budgets: $(jq -c .app.budgets "$VAR/status.json")"; fail=1; }
  wait_for '.app.sessions >= 1' 20 && echo "  ok   devices signed in: $(jq .app.sessions "$VAR/status.json")" || { echo "  FAIL sessions"; fail=1; }
  # Quiet syncing: the budget's files look 10 days old; a 3-day warning goes to DSM.
  docker exec actual-server sh -c 'touch -d "@$(( $(date +%s) - 864000 ))" /data/user-files/*' >/dev/null 2>&1
  request "ACTION='stale'" "STALE_DAYS='3'" || fail=1
  local i; for i in $(seq 1 90); do grep -qE "notification \(actualstale\)|told DSM: actualstale" "$VAR/package.log" && break; touch "$VAR/watching"; sleep 1; done
  grep -qE "notification \(actualstale\)|told DSM: actualstale" "$VAR/package.log" && echo "  ok   no sync for 10 days went to DSM's notifications (only attempted: no DSM here)" || { echo "  FAIL no stale notification"; fail=1; }
  # Upload size.
  request "ACTION='limit'" "LIMIT_MB='50'" || fail=1
  [[ "$(docker exec actual-server printenv ACTUAL_UPLOAD_FILE_SIZE_LIMIT_MB)" == 50 ]] && echo "  ok   upload limit 50 MB in Actual's environment" || { echo "  FAIL limit"; fail=1; }
  tok=$(login "$url" "$pw")
  # A new password that also signs every device out.
  request "ACTION='newpw'" "SIGNOUT='1'" || fail=1; pw2=$(secret)
  [[ -n "$(login "$url" "$pw2")" && -z "$(login "$url" "$pw")" ]] && echo "  ok   new password signs in, the old one doesn't" || { echo "  FAIL newpw"; fail=1; }
  token_ok "$url" "$tok" && { echo "  FAIL a device stayed signed in"; fail=1; } || echo "  ok   …and devices signed in before were signed out"
  tok2=$(login "$url" "$pw2"); token_ok "$url" "$tok2" || { echo "  FAIL fresh token"; fail=1; }
  request "ACTION='signout'" || fail=1
  token_ok "$url" "$tok2" && { echo "  FAIL signout"; fail=1; } || echo "  ok   sign out every device"
  # HTTPS can't simply be switched off: only behind DSM's reverse proxy.
  request "ACTION='settings'" "TLS='off'" >/dev/null
  [[ "$(curl -sk "$url/health" | jq -r .status)" == UP ]] && jq -e '.app.tls.mode == "dsm"' "$VAR/status.json" >/dev/null && echo "  ok   HTTPS off without DSM's reverse proxy: HTTPS stays on" || { echo "  FAIL https after off: $(jq -c .app.tls.mode "$VAR/status.json")"; fail=1; }
  request "ACTION='settings'" "TLS='self'" || fail=1
  jq -e '.app.tls.mode == "self" and .app.tls.cert.self_signed == true' "$VAR/status.json" >/dev/null && [[ "$(curl -sk "$url/health" | jq -r .status)" == UP ]] && echo "  ok   self-signed by choice" || { echo "  FAIL self"; fail=1; }
  (( fail )) && { echo "  actual: something FAILED"; return 1; }; echo "  actual: all passed"
}
