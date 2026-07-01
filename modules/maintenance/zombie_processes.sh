#!/usr/bin/env bash
# modules/maintenance/zombie_processes.sh

_MDIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
source "${_MDIR}/../../lib/report.sh"

check_zombie_processes() {
    report_section "Zombie / Orphaned Processes"

    local zombies
    zombies=$(ps aux 2>/dev/null | awk '$8=="Z" {print $2, $11}')

    if [[ -z "$zombies" ]]; then
        report_pass "No zombie processes"
    else
        while IFS= read -r line; do
            report_warn "Zombie PID: ${line}"
        done <<< "$zombies"
    fi

    # Orphaned processes: PPID=1 but not expected system processes
    local orphans
    orphans=$(ps -eo pid,ppid,comm 2>/dev/null | awk '$2==1 && $3!~/systemd|init|kthreadd|rcu|migration|watchdog|cpuhp/' | head -20)
    local orphan_count; orphan_count=$(echo "$orphans" | grep -c . || true)
    if (( orphan_count <= 5 )); then
        report_pass "Orphaned processes: ${orphan_count} (within normal range)"
    else
        report_warn "Orphaned processes: ${orphan_count} (more than expected)"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    SCRIPT_DIR="$(dirname "$(realpath "$0")")"
    source "${SCRIPT_DIR}/../../config/ubuntils.conf" 2>/dev/null || true
    source "${SCRIPT_DIR}/../../config/modules.conf" 2>/dev/null || true
    [[ "${maintenance_zombie_processes:-1}" -eq 1 ]] || exit 0
    report_start "zombie_processes"
    check_zombie_processes
    report_finish
fi
