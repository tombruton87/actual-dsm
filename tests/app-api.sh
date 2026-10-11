# Actual Budget's CGI checks (sourced by chassis/tests/test-api.sh).
expect "newpw" 202 "$(post "$me" newpw 'action=newpw&signout=1')"; request_is "newpw request" "ACTION='newpw'
SIGNOUT='1'
BY='$me'"
expect "newpw bad" 400 "$(post "$me" newpw 'action=newpw&signout=yes')"
expect "signout" 202 "$(post "$me" signout 'action=signout')"; rm -f "$CHASSIS_VAR/request"
expect "stale good" 202 "$(post "$me" stale 'action=stale&days=7')"; request_is "stale request" "ACTION='stale'
STALE_DAYS='7'
BY='$me'"
expect "stale bad" 400 "$(post "$me" stale 'action=stale&days=5')"
expect "limit good" 202 "$(post "$me" limit 'action=limit&mb=100')"; rm -f "$CHASSIS_VAR/request"
expect "limit bad" 400 "$(post "$me" limit 'action=limit&mb=1000000')"
expect "https off without a proxy" 400 "$(post "$me" settings 'action=settings&url=https%3A%2F%2F192.168.1.10%3A5006&port=5006&ssl_proxy=0&tz=Europe%2FLondon&tls=off')"
expect "https off behind the proxy" 202 "$(post "$me" settings 'action=settings&url=https%3A%2F%2Fbudget.example.com&port=5006&ssl_proxy=1&tz=Europe%2FLondon&tls=off')"; rm -f "$CHASSIS_VAR/request"
