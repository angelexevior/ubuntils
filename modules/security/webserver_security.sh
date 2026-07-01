#!/usr/bin/env bash
# modules/security/webserver_security.sh — server_tokens, TLS config

_MDIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
source "${_MDIR}/../../lib/report.sh"

check_webserver_security() {
    report_section "Web Server Security"

    # Nginx
    if [[ "${NGINX_INSTALLED:-0}" -eq 1 ]]; then
        report_info "nginx ${NGINX_VERSION:-} detected"

        [[ "${security_webserver_tokens:-1}" -eq 1 ]] && {
            local server_tokens; server_tokens=$(grep -rh 'server_tokens' /etc/nginx/ 2>/dev/null | grep -v '#' | awk '{print $2}' | tr -d ';' | head -1)
            if [[ "${server_tokens}" == "off" ]]; then
                report_pass "nginx: server_tokens off"
            else
                report_warn "nginx: server_tokens not set to off (exposes version)"
            fi
        }

        [[ "${security_webserver_tls:-1}" -eq 1 ]] && {
            # Check for weak protocols
            if grep -rh 'ssl_protocols' /etc/nginx/ 2>/dev/null | grep -qiE 'SSLv[23]|TLSv1[^.]|TLSv1\.0|TLSv1\.1'; then
                report_fail "nginx: weak SSL/TLS protocols enabled (SSLv2/3, TLSv1.0/1.1)"
            else
                report_pass "nginx: no weak SSL/TLS protocols detected"
            fi
            # Check for weak ciphers
            if grep -rh 'ssl_ciphers' /etc/nginx/ 2>/dev/null | grep -qiE 'RC4|MD5|DES|NULL|EXPORT|anon'; then
                report_fail "nginx: weak SSL ciphers configured"
            else
                report_pass "nginx: no obviously weak SSL ciphers"
            fi
        }
    fi

    # Apache
    if [[ "${APACHE_INSTALLED:-0}" -eq 1 ]]; then
        report_info "apache ${APACHE_VERSION:-} detected"

        [[ "${security_webserver_tokens:-1}" -eq 1 ]] && {
            local server_tokens_a; server_tokens_a=$(grep -rh 'ServerTokens' /etc/apache2/ 2>/dev/null | grep -v '#' | awk '{print $2}' | head -1)
            if [[ "${server_tokens_a,,}" =~ ^(prod|minimal)$ ]]; then
                report_pass "apache: ServerTokens ${server_tokens_a}"
            else
                report_warn "apache: ServerTokens=${server_tokens_a:-not set} — set to Prod"
            fi
            local server_sig; server_sig=$(grep -rh 'ServerSignature' /etc/apache2/ 2>/dev/null | grep -v '#' | awk '{print $2}' | head -1)
            if [[ "${server_sig,,}" == "off" ]]; then
                report_pass "apache: ServerSignature Off"
            else
                report_warn "apache: ServerSignature not Off"
            fi
        }

        [[ "${security_webserver_tls:-1}" -eq 1 ]] && {
            if grep -rh 'SSLProtocol' /etc/apache2/ 2>/dev/null | grep -qiE 'SSLv[23]|\+TLSv1$|\+TLSv1\.0|\+TLSv1\.1'; then
                report_fail "apache: weak SSL/TLS protocols enabled"
            else
                report_pass "apache: no weak SSL protocols detected"
            fi
        }
    fi

    if [[ "${NGINX_INSTALLED:-0}" -eq 0 && "${APACHE_INSTALLED:-0}" -eq 0 ]]; then
        report_info "No web server detected"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    SCRIPT_DIR="$(dirname "$(realpath "$0")")"
    source "${SCRIPT_DIR}/../../config/ubuntils.conf" 2>/dev/null || true
    source "${SCRIPT_DIR}/../../config/modules.conf" 2>/dev/null || true
    source "${SCRIPT_DIR}/../../lib/detect.sh"
    detect_load
    report_start "webserver_security"
    check_webserver_security
    report_finish
fi
