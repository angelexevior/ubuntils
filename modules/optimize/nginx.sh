#!/usr/bin/env bash
# modules/optimize/nginx.sh — nginx tuning suggestions

_MDIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
source "${_MDIR}/../../lib/report.sh"
source "${_MDIR}/../../lib/backup.sh"

optimize_nginx() {
    report_section "Nginx Optimization"
    local auto="${1:-}"
    [[ "${optimize_nginx:-1}" -eq 1 ]] || return

    if [[ "${NGINX_INSTALLED:-0}" -eq 0 ]]; then
        report_info "nginx not detected — skipping"
        return
    fi

    local nginx_conf="/etc/nginx/nginx.conf"
    [[ -f "$nginx_conf" ]] || { report_warn "nginx.conf not found"; return; }

    local cpu_cores; cpu_cores=$(nproc 2>/dev/null || echo 1)

    # worker_processes
    local current_wp; current_wp=$(grep -E '^\s*worker_processes' "$nginx_conf" | awk '{print $2}' | tr -d ';' | head -1)
    if [[ "$current_wp" != "$cpu_cores" && "$current_wp" != "auto" ]]; then
        report_warn "nginx worker_processes: current=${current_wp:-not set}, suggested=${cpu_cores} (or auto)"
    else
        report_pass "nginx worker_processes: ${current_wp} (optimal)"
    fi

    # worker_connections
    local current_wc; current_wc=$(grep -E '^\s*worker_connections' "$nginx_conf" | awk '{print $2}' | tr -d ';' | head -1)
    local suggested_wc=1024
    if (( ${current_wc:-0} < suggested_wc )); then
        report_warn "nginx worker_connections: current=${current_wc:-not set}, suggested>=${suggested_wc}"
    else
        report_pass "nginx worker_connections: ${current_wc}"
    fi

    # gzip
    if grep -qE '^\s*gzip\s+on' "$nginx_conf" 2>/dev/null; then
        report_pass "nginx gzip: enabled"
    else
        report_warn "nginx gzip: not enabled — enable for better compression"
    fi

    if [[ "$auto" == "--auto" ]]; then
        local tmp; tmp=$(mktemp)
        cp "$nginx_conf" "$tmp"
        # worker_processes
        sed -i "s/^\s*worker_processes\s.*/worker_processes auto;/" "$tmp"
        # worker_connections
        sed -i "s/^\s*worker_connections\s.*/    worker_connections 1024;/" "$tmp"
        # gzip on if not present
        if ! grep -q 'gzip on' "$tmp"; then
            sed -i '/http\s*{/a\    gzip on;\n    gzip_types text/plain text/css application/json application/javascript text/xml application/xml;' "$tmp"
        fi
        backup_diff_apply "$nginx_conf" "$tmp" "--auto"
        nginx -t &>/dev/null && systemctl reload nginx &>/dev/null && report_info "nginx reloaded"
        rm -f "$tmp"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    SCRIPT_DIR="$(dirname "$(realpath "$0")")"
    source "${SCRIPT_DIR}/../../config/ubuntils.conf" 2>/dev/null || true
    source "${SCRIPT_DIR}/../../config/modules.conf" 2>/dev/null || true
    source "${SCRIPT_DIR}/../../lib/detect.sh"
    detect_load
    [[ "${optimize_nginx:-1}" -eq 1 ]] || exit 0
    AUTO="${1:-}"
    report_start "nginx_optimize"
    optimize_nginx "$AUTO"
    report_finish
fi
