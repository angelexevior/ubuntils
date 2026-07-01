#!/usr/bin/env bash
# modules/maintenance/log_rotation.sh

_MDIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
source "${_MDIR}/../../lib/report.sh"

check_log_rotation() {
    report_section "Log Rotation"
    local max_days="${LOG_ROTATE_DAYS:-30}"

    local found_stale=0
    while IFS= read -r logfile; do
        local age_days
        age_days=$(( ( $(date +%s) - $(stat -c %Y "$logfile") ) / 86400 ))
        if (( age_days > max_days )); then
            report_warn "Stale log (${age_days}d old, not rotated): ${logfile}"
            found_stale=1
        fi
    done < <(find /var/log -maxdepth 2 -name '*.log' -type f 2>/dev/null | head -100)

    [[ $found_stale -eq 0 ]] && report_pass "All logs in /var/log rotated within ${max_days} days"

    # Check logrotate config exists
    if command -v logrotate &>/dev/null; then
        report_pass "logrotate is installed"
    else
        report_warn "logrotate not installed"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    SCRIPT_DIR="$(dirname "$(realpath "$0")")"
    source "${SCRIPT_DIR}/../../config/ubuntils.conf" 2>/dev/null || true
    source "${SCRIPT_DIR}/../../config/modules.conf" 2>/dev/null || true
    [[ "${maintenance_log_rotation:-1}" -eq 1 ]] || exit 0
    report_start "log_rotation"
    check_log_rotation
    report_finish
fi
