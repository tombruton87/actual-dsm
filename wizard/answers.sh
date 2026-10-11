    echo "TLS='$(if [ "${wizard_tls_self:-false}" = true ]; then echo self; elif [ "${wizard_tls_off:-false}" = true ]; then echo off; else echo dsm; fi)'"
