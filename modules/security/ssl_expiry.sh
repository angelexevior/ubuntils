#!/usr/bin/env bash
# modules/security/ssl_expiry.sh

_MDIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
source "${_MDIR}/../../lib/report.sh"

check_ssl_expiry() {
    report_section "SSL Certificate Expiry"

    local vhosts="${VHOSTS:-}"
    if [[ -z "$vhosts" ]]; then
        report_info "No vhosts detected — skipping SSL expiry check"
        return
    fi

    IFS=',' read -ra vhost_list <<< "$vhosts"
    for vhost in "${vhost_list[@]}"; do
        vhost="${vhost// /}"
        [[ -z "$vhost" || "$vhost" == "_" || "$vhost" == "localhost" ]] && continue

        # Check via openssl
        if ! command -v openssl &>/dev/null; then
            report_warn "openssl not available — cannot check SSL for ${vhost}"
            continue
        fi

        local expiry_raw
        expiry_raw=$(echo | timeout 5 openssl s_client -servername "$vhost" -connect "${vhost}:443" 2>/dev/null \
            | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)

        if [[ -z "$expiry_raw" ]]; then
            report_warn "Could not get SSL cert for ${vhost}"
            continue
        fi

        local expiry_epoch; expiry_epoch=$(date -d "$expiry_raw" +%s 2>/dev/null || true)
        local now_epoch; now_epoch=$(date +%s)
        local days_left=$(( (expiry_epoch - now_epoch) / 86400 ))

        if (( days_left <= 0 )); then
            report_fail "${vhost}: SSL cert EXPIRED ${days_left#-} days ago"
        elif (( days_left <= 7 )); then
            report_fail "${vhost}: SSL cert expires in ${days_left} days"
        elif (( days_left <= 30 )); then
            report_warn "${vhost}: SSL cert expires in ${days_left} days"
        else
            report_pass "${vhost}: SSL cert valid for ${days_left} days"
        fi
    done

    # Also check certbot certs on disk
    if [[ -d /etc/letsencrypt/live ]]; then
        while IFS= read -r cert; do
            local domain; domain=$(basename "$cert")
            local cert_file="${cert}/cert.pem"
            [[ -f "$cert_file" ]] || continue
            local expiry_raw; expiry_raw=$(openssl x509 -noout -enddate -in "$cert_file" 2>/dev/null | cut -d= -f2)
            local expiry_epoch; expiry_epoch=$(date -d "$expiry_raw" +%s 2>/dev/null || true)
            local days_left=$(( (expiry_epoch - $(date +%s)) / 86400 ))
            if (( days_left <= 14 )); then
                report_warn "certbot cert for ${domain}: ${days_left} days left — auto-renew may have failed"
            fi
        done < <(find /etc/letsencrypt/live -maxdepth 1 -mindepth 1 -type d 2>/dev/null)
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    SCRIPT_DIR="$(dirname "$(realpath "$0")")"
    source "${SCRIPT_DIR}/../../config/ubuntils.conf" 2>/dev/null || true
    source "${SCRIPT_DIR}/../../config/modules.conf" 2>/dev/null || true
    source "${SCRIPT_DIR}/../../lib/detect.sh"
    detect_load
    [[ "${security_ssl_expiry:-1}" -eq 1 ]] || exit 0
    report_start "ssl_expiry"
    check_ssl_expiry
    report_finish
fi
