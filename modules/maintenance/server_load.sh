#!/usr/bin/env bash
# modules/maintenance/server_load.sh

_MDIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
source "${_MDIR}/../../lib/report.sh"

check_server_load() {
    report_section "Server Load"
    local warn="${LOAD_AVG_WARN:-4}" crit="${LOAD_AVG_CRIT:-8}"

    local load1 load5 load15
    read -r load1 load5 load15 _ < /proc/loadavg

    local load1_int; load1_int=$(printf '%.0f' "$load1")

    if (( load1_int >= crit )); then
        report_fail "Load avg: ${load1} ${load5} ${load15} (1m/5m/15m) — CRITICAL"
    elif (( load1_int >= warn )); then
        report_warn "Load avg: ${load1} ${load5} ${load15} (1m/5m/15m) — WARNING"
    else
        report_pass "Load avg: ${load1} ${load5} ${load15} (1m/5m/15m)"
    fi

    local cpu_count; cpu_count=$(nproc 2>/dev/null || echo 1)
    report_info "CPU cores: ${cpu_count}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    SCRIPT_DIR="$(dirname "$(realpath "$0")")"
    source "${SCRIPT_DIR}/../../config/ubuntils.conf" 2>/dev/null || true
    source "${SCRIPT_DIR}/../../config/modules.conf" 2>/dev/null || true
    [[ "${maintenance_server_load:-1}" -eq 1 ]] || exit 0
    report_start "server_load"
    check_server_load
    report_finish
fi
