#!/usr/bin/env bash
# modules/maintenance/apt_updates.sh

_MDIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
source "${_MDIR}/../../lib/report.sh"

check_apt_updates() {
    report_section "APT Updates"
    local warn="${APT_PENDING_WARN:-10}"

    if ! command -v apt-get &>/dev/null; then
        report_info "apt not available on this system"
        return
    fi

    # Use apt-check or count from apt list
    local count=0
    if command -v /usr/lib/update-notifier/apt-check &>/dev/null; then
        local apt_out; apt_out=$(/usr/lib/update-notifier/apt-check 2>&1 || true)
        count=$(echo "$apt_out" | cut -d';' -f1)
        local security_count; security_count=$(echo "$apt_out" | cut -d';' -f2)
        count="${count:-0}"
        security_count="${security_count:-0}"
    else
        count=$(apt list --upgradable 2>/dev/null | grep -c upgradable || true)
        security_count=0
    fi

    if (( count == 0 )); then
        report_pass "No pending updates"
    elif (( count >= warn )); then
        report_warn "${count} pending updates (${security_count:-?} security)"
    else
        report_warn "${count} pending updates (${security_count:-?} security)"
    fi

    # Security-only count as fail if non-zero
    if [[ -n "${security_count:-}" ]] && (( security_count > 0 )); then
        report_fail "${security_count} security updates pending — apply immediately"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    SCRIPT_DIR="$(dirname "$(realpath "$0")")"
    source "${SCRIPT_DIR}/../../config/ubuntils.conf" 2>/dev/null || true
    source "${SCRIPT_DIR}/../../config/modules.conf" 2>/dev/null || true
    [[ "${maintenance_apt_updates:-1}" -eq 1 ]] || exit 0
    report_start "apt_updates"
    check_apt_updates
    report_finish
fi
