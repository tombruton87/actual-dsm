# Actual Budget's actions, validated by the CGI before they become a request file.
app_cgi_post() {   # action body → sets $lines, or error
  local a=$1 body=$2 v
  case "$a" in
    signout|refreshcert) lines="ACTION='$a'" ;;
    newpw) v=$(param signout "$body"); [[ "${v:-0}" =~ ^[01]$ ]] || error "400 Bad Request" "Sign out: yes or no."; lines="ACTION='newpw'
SIGNOUT='${v:-0}'" ;;
    stale) v=$(param days "$body"); [[ "$v" =~ ^(0|3|7|14|30)$ ]] || error "400 Bad Request" "Pick how long."; lines="ACTION='stale'
STALE_DAYS='$v'" ;;
    limit) v=$(param mb "$body"); [[ "$v" =~ ^(20|50|100|200)$ ]] || error "400 Bad Request" "Pick a size."; lines="ACTION='limit'
LIMIT_MB='$v'" ;;
  esac
}
app_cgi_settings() {   # body → appends TLS to $lines, or errors
  local tls; tls=$(param tls "$1")
  [[ -z "$tls" ]] && return 0
  [[ "$tls" =~ ^(dsm|self|off)$ ]] || error "400 Bad Request" "HTTPS is DSM's certificate, self-signed, or off."
  [[ "$tls" == off && "$(param ssl_proxy "$1")" != 1 ]] && error "400 Bad Request" "Actual needs HTTPS: turn it off only when DSM's reverse proxy provides it (tick that box too)."
  lines="$lines
TLS='$tls'"
}
