#!/usr/bin/env bash
# modules/security/fail2ban.sh

_MDIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
source "${_MDIR}/../../lib/report.sh"

check_fail2ban() {
    report_section "fail2ban"

    if [[ "${FAIL2BAN_INSTALLED:-0}" -eq 0 ]]; then
        report_warn "fail2ban not installed"
        return
    fi

    if ! systemctl is-active --quiet fail2ban 2>/dev/null; then
        report_fail "fail2ban installed but not running"
        return
    fi

    report_pass "fail2ban is active"

    local jails="${FAIL2BAN_JAILS:-}"
    if [[ -z "$jails" ]]; then
        report_warn "No fail2ban jails active"
        return
    fi

    IFS=',' read -ra jail_list <<< "$jails"
    for jail in "${jail_list[@]}"; do
        jail="${jail// /}"
        [[ -z "$jail" ]] && continue
        local banned; banned=$(fail2ban-client status "$jail" 2>/dev/null | grep 'Currently banned' | awk '{print $NF}' || echo "?")
        report_pass "Jail '${jail}': ${banned} currently banned"
    done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    SCRIPT_DIR="$(dirname "$(realpath "$0")")"
    source "${SCRIPT_DIR}/../../config/ubuntils.conf" 2>/dev/null || true
    source "${SCRIPT_DIR}/../../config/modules.conf" 2>/dev/null || true
    source "${SCRIPT_DIR}/../../lib/detect.sh"
    detect_load
    [[ "${security_fail2ban:-1}" -eq 1 ]] || exit 0
    report_start "fail2ban"
    check_fail2ban
    report_finish
fi
