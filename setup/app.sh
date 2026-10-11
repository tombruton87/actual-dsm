# Actual Budget's hooks for the chassis core (sourced by run-core.sh). The core
# gives: say, env_get/env_set, rand, compose, in_volume, cname, svc_up,
# leave_secret, notify, fresh, now, qr_png_b64, MSG, VAR, APP, LOG, PKG_NAME,
# PKG_TITLE, and the tls_* helpers (chassis tls.sh).
#
# Actual's server has one password (or OpenID) and no admin API. The package
# works through Actual's own account functions and SQLite files, with
# setup/ab.mjs piped to node inside its container (passwords on stdin). The
# password is set at the first start and shown once; it is never stored.

AB=""; ABJS=/pkg/setup/ab.mjs

app_validate() {   # key value → 0 if the value has the key's shape
  case "$1" in
    TLS)        [[ "$2" =~ ^(dsm|self|off)$ ]] ;;
    SIGNOUT)    [[ "$2" =~ ^[01]$ ]] ;;
    STALE_DAYS) [[ "$2" =~ ^(0|3|7|14|30)$ ]] ;;
    LIMIT_MB)   [[ "$2" =~ ^(20|50|100|200)$ ]] ;;
    *) return 1 ;;
  esac
}

# ------------------------------------------------------------ talking to Actual
ab_node() {   # action [arg-json] → ab.mjs's JSON line in AB_OUT; 0 when it says ok
  local a=$1 arg=${2:-"{}"}
  AB_OUT=$({ printf 'const ACT = %s; const ARG = JSON.parse(Buffer.from(%s, "base64").toString());\n' "$(jq -Rn --arg v "$a" '$v')" "$(jq -Rn --arg v "$(printf '%s' "$arg" | base64 -w0)" '$v')"; cat "$ABJS"; } \
    | docker exec -i -w /app "$AB" node --input-type=module - 2>>"$LOG" | tail -n 1)
  jq -e '.ok == true' <<< "$AB_OUT" >/dev/null 2>&1
}
ab_msg() { jq -r '.msg // empty' <<< "${AB_OUT:-}" 2>/dev/null | head -c 300; }
scheme() { [[ "$(env_get TLS_SOURCE)" =~ ^(dsm|self)$ ]] && echo https || echo http; }
ab_url() { echo "$(scheme)://127.0.0.1:$(env_get HTTP_PORT)"; }
strong_password() { echo "$(rand 5)-$(rand 5)-$(rand 5)-$(rand 5)"; }

# ------------------------------------------------------------ lifecycle hooks
app_first_env() {
  env_set AB_IMAGE actualbudget/actual-server:latest
  env_set TLS "${TLS:-dsm}"; env_set LIMIT_MB 20; env_set STALE_DAYS 14
  tls_fix_scheme || true
  touch "$VAR/.needs-password"
}
app_load_env() { AB=$(cname server); }
app_before_up() {
  [[ -n "$(env_get TLS)" ]] || env_set TLS dsm
  setup_tls || say "✗ HTTPS couldn't be set up: $MSG"
}
setup_tls() {
  tls_fix_scheme || true
  tls_prepare data || return 1
  if [[ "$(env_get TLS_SOURCE)" =~ ^(dsm|self)$ ]]; then env_set TLS_CERT /data/tls/fullchain.pem; env_set TLS_KEY /data/tls/privkey.pem
  else env_set TLS_CERT ""; env_set TLS_KEY ""; fi
  qr_png_b64 "$(env_get APP_URL)" > "$VAR/qr.b64.tmp" && mv "$VAR/qr.b64.tmp" "$VAR/qr.b64"
}
app_health() { [[ "$(curl -sk --max-time 5 "$(ab_url)/health" 2>/dev/null | jq -r '.status // empty' 2>/dev/null)" == UP ]]; }
app_version() { curl -sk --max-time 5 "$(ab_url)/info" 2>/dev/null | jq -r '.build.version // empty' 2>/dev/null | tr -cd '0-9A-Za-z.-' | head -c 30; }
app_after_up() { make_password 60; }
make_password() {   # [tries] — the first time: the server's password, shown once
  [[ -f "$VAR/.needs-password" ]] || return 0
  local i pw
  for i in $(seq 1 "${1:-1}"); do app_health && break; sleep 2; done
  app_health || { say "Actual isn't answering yet — its password is set when it does"; return 0; }
  pw=$(strong_password)
  if ab_node bootstrap "$(jq -cn --arg p "$pw" '{password: $p}')"; then
    leave_secret "Actual Budget (server password)" "$pw" signin; say "first start: Actual's server password was set; it's shown once in the window"
  elif [[ "$(ab_msg)" == already ]]; then say "Actual already has a password — left as it is (Sign-in tab → New password if it's lost)"
  else say "✗ Actual's password couldn't be set: $(ab_msg) — trying again shortly"; return 0; fi
  rm -f "$VAR/.needs-password"
}

# ------------------------------------------------------------ what the window shows
app_status() {
  svc_up server || { echo '{"up": false}'; return 0; }
  local data='{}'
  ab_node status && data=$AB_OUT
  [[ -s "$VAR/cert.json" ]] || tls_info data
  jq -c --arg url "$(env_get APP_URL)" --arg qr "$(cat "$VAR/qr.b64" 2>/dev/null)" --arg stale "$(env_get STALE_DAYS)" --arg limit "$(env_get LIMIT_MB)" \
     --arg tls "$(env_get TLS)" --arg tls_source "$(env_get TLS_SOURCE)" --argjson cert "$(cat "$VAR/cert.json" 2>/dev/null || echo null)" \
     'del(.ok) + {up: true, url: $url, qr: $qr, stale_days: ($stale | tonumber? // 14), limit_mb: ($limit | tonumber? // 20),
                  tls: {mode: $tls, source: $tls_source, cert: $cert}}' <<< "$data" 2>/dev/null || echo '{"up": true}'
}

# ------------------------------------------------------------ the quiet-sync warning
check_stale() {   # no budget has changed on the server for STALE_DAYS → a DSM notification (again a week later if still so)
  local days last n
  days=$(env_get STALE_DAYS); [[ "$days" =~ ^[0-9]+$ ]] && (( days > 0 )) || return 0
  ab_node status || return 0
  n=$(jq '[.budgets[] | select(.deleted | not)] | length' <<< "$AB_OUT"); (( n )) || return 0
  last=$(jq '[.budgets[] | select(.deleted | not) | .changed] | max // 0' <<< "$AB_OUT")
  (( $(now) - last > days * 86400 )) || return 0
  notify actualstale 168 "$(( ($(now) - last) / 86400 ))"
}
app_tick() {
  make_password 1
  svc_up server || return 0
  fresh "$VAR/.stale-check" 3600 || { touch "$VAR/.stale-check"; check_stale || true; }
  fresh "$VAR/.cert-check" 86400 && return 0; touch "$VAR/.cert-check"
  tls_refresh_dsm data
  [[ "$CERT_REFRESH" == changed ]] && { docker restart "$AB" >> "$LOG" 2>&1 || true; }
  return 0
}

# ------------------------------------------------------------ settings, logs, storage, backups, report
app_settings() {   # HTTPS (Actual needs it — off only behind DSM's reverse proxy)
  [[ -n "${TLS:-}" ]] && env_set TLS "$TLS"
  if [[ "$(env_get TLS)" == off && "$(env_get SSL_PROXY)" != 1 ]]; then
    say "HTTPS stays on: Actual needs it, and nothing in front provides it (the window refuses this; a request file got here)"; env_set TLS dsm
  fi
  setup_tls || return 1
  return 0
}
app_logs() { :; }
app_storage() {
  in_volume data ro -- 'printf "budgets\t%s\n" "$(du -sm /vol/user-files 2>/dev/null | cut -f1)"; printf "account\t%s\n" "$(du -sm /vol/server-files 2>/dev/null | cut -f1)"; true' </dev/null 2>/dev/null \
    | jq -R -s -c 'split("\n") | map(select(length > 0) | split("\t") | {key: .[0], value: (.[1] | tonumber? // 0)}) | from_entries' 2>/dev/null || echo "{}"
}
app_backup() {   # dir — every SQLite file copied consistently (sqlite3 .backup), the rest as it is
  in_volume data ro -- 'set -e; mkdir -p /tmp/b; cd /vol; tar -cf - --exclude="*.sqlite" --exclude="*.sqlite-journal" . | tar -C /tmp/b -xf -
    for f in $(find . -name "*.sqlite"); do mkdir -p "/tmp/b/$(dirname "$f")"; sqlite3 -readonly "$f" ".backup /tmp/b/$f"; done
    tar -C /tmp/b -czf - .' > "$1/data.tar.gz" 2>>"$LOG" </dev/null \
    && grep -q 'server-files/account.sqlite' < <(tar -tzf "$1/data.tar.gz" 2>/dev/null) || { say "✗ Actual's files didn't copy"; return 1; }   # not a pipe: under pipefail, grep -q stopping early fails tar
}
app_restore() {   # dir — the core has stopped the containers
  [[ -s "$1/data.tar.gz" ]] || { MSG="That backup has no Actual files."; return 1; }
  in_volume data rw -- 'find /vol -mindepth 1 -delete && tar -C /vol -xzf -' < "$1/data.tar.gz" 2>>"$LOG" || { MSG="Actual's files didn't unpack."; return 1; }
  rm -f "$VAR/.needs-password"
}
app_report() {
  local s; ab_node status && s=$AB_OUT || s='{}'
  echo "== server: sign-in by $(jq -r '.method // "?"' <<< "$s"), $(jq -r '.sessions // "?"' <<< "$s") signed-in devices, $(jq -r '.users // "?"' <<< "$s") users"
  echo "== budgets"; jq -r '.budgets[]? | "\(.name)  \(.size) bytes  changed \(.changed | todate)\(if .encrypted then "  encrypted" else "" end)\(if .deleted then "  deleted" else "" end)"' <<< "$s" 2>/dev/null
  echo; echo "== settings: upload limit $(env_get LIMIT_MB) MB, quiet-sync warning after $(env_get STALE_DAYS) days"
  echo; echo "== HTTPS"; echo "mode $(env_get TLS), in use: $(env_get TLS_SOURCE)"; jq -c 'del(.names)' "$VAR/cert.json" 2>/dev/null
  :
}

# ------------------------------------------------------------ the window's actions
app_act() {   # action (request vars are set)
  local pw n
  case "$1" in
    newpw)
      pw=$(strong_password)
      ab_node setpw "$(jq -cn --arg p "$pw" --argjson s "${SIGNOUT:-0}" '{password: $p, signout: ($s == 1)}')" || { MSG=$(ab_msg); MSG=${MSG:-"The password couldn't be changed."}; return 1; }
      leave_secret "Actual Budget (server password)" "$pw" signin; rm -f "$VAR/.needs-password"
      n=$(jq -r '.signedOut // 0' <<< "$AB_OUT")
      MSG="The new password is shown below, once.$([[ "${SIGNOUT:-0}" == 1 ]] && { [[ "$n" == 1 ]] && echo " 1 device was signed out." || echo " $n devices were signed out."; })" ;;
    signout)
      ab_node signout || { MSG=$(ab_msg); return 1; }
      n=$(jq -r '.signedOut // 0' <<< "$AB_OUT"); MSG="Every device was signed out ($n session$([[ "$n" == 1 ]] || echo s)); they sign in again with the password." ;;
    stale) env_set STALE_DAYS "${STALE_DAYS:-14}"; rm -f "$VAR/.stale-check"
      MSG=$([[ "${STALE_DAYS:-14}" == 0 ]] && echo "No warning about quiet syncing." || echo "DSM tells you when no budget has synced for $STALE_DAYS days.") ;;
    limit)
      env_set LIMIT_MB "${LIMIT_MB:-20}"
      compose up -d >> "$LOG" 2>&1 && wait_ready 120 || { MSG="Actual didn't come back — see the log."; return 1; }
      MSG="Devices may now upload budget files up to $LIMIT_MB MB." ;;
    refreshcert)
      tls_refresh_dsm data; setup_tls || return 1; docker restart "$AB" >> "$LOG" 2>&1; wait_ready 120
      MSG=$([[ "$(env_get TLS_SOURCE)" == dsm ]] && echo "DSM's certificate was read again." || echo "A new self-signed certificate is in use.") ;;
    *) MSG="Unknown request."; return 1 ;;
  esac
}
