#!/usr/bin/env bash
# modules/maintenance/failed_units.sh

_MDIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
source "${_MDIR}/../../lib/report.sh"

check_failed_units() {
    report_section "Failed systemd Units"

    if ! command -v systemctl &>/dev/null; then
        report_info "systemctl not available"
        return
    fi

    local failed_units
    failed_units=$(systemctl list-units --state=failed --no-legend --no-pager 2>/dev/null | awk '{print $1}')

    if [[ -z "$failed_units" ]]; then
        report_pass "No failed systemd units"
    else
        while IFS= read -r unit; do
            [[ -n "$unit" ]] && report_fail "Failed unit: ${unit}"
        done <<< "$failed_units"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    SCRIPT_DIR="$(dirname "$(realpath "$0")")"
    source "${SCRIPT_DIR}/../../config/ubuntils.conf" 2>/dev/null || true
    source "${SCRIPT_DIR}/../../config/modules.conf" 2>/dev/null || true
    [[ "${maintenance_failed_units:-1}" -eq 1 ]] || exit 0
    report_start "failed_units"
    check_failed_units
    report_finish
fi
