#!/usr/bin/env bash
# modules/maintenance/swap_oom.sh

_MDIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
source "${_MDIR}/../../lib/report.sh"

check_swap_oom() {
    report_section "Swap & OOM"

    # Swap usage
    local swap_total swap_used swap_pct
    swap_total=$(free -k 2>/dev/null | awk '/Swap:/{print $2}')
    swap_used=$(free -k  2>/dev/null | awk '/Swap:/{print $3}')

    if (( swap_total == 0 )); then
        report_warn "No swap configured"
    else
        swap_pct=$(( swap_used * 100 / swap_total ))
        if (( swap_pct >= 80 )); then
            report_fail "Swap: ${swap_pct}% used (${swap_used}k / ${swap_total}k)"
        elif (( swap_pct >= 50 )); then
            report_warn "Swap: ${swap_pct}% used (${swap_used}k / ${swap_total}k)"
        else
            report_pass "Swap: ${swap_pct}% used (${swap_used}k / ${swap_total}k)"
        fi
    fi

    # OOM kill history from kernel log
    local oom_count=0
    if command -v journalctl &>/dev/null; then
        oom_count=$(journalctl -k --since "7 days ago" 2>/dev/null | grep -c 'Out of memory' || true)
    elif [[ -f /var/log/kern.log ]]; then
        oom_count=$(grep -c 'Out of memory' /var/log/kern.log 2>/dev/null || true)
    fi

    if (( oom_count > 0 )); then
        report_fail "OOM kills in last 7 days: ${oom_count}"
    else
        report_pass "No OOM kills detected in last 7 days"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    SCRIPT_DIR="$(dirname "$(realpath "$0")")"
    source "${SCRIPT_DIR}/../../config/ubuntils.conf" 2>/dev/null || true
    source "${SCRIPT_DIR}/../../config/modules.conf" 2>/dev/null || true
    [[ "${maintenance_swap_oom:-1}" -eq 1 ]] || exit 0
    report_start "swap_oom"
    check_swap_oom
    report_finish
fi
