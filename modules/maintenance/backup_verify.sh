#!/usr/bin/env bash
# modules/maintenance/backup_verify.sh

_MDIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
source "${_MDIR}/../../lib/report.sh"

check_backup_verify() {
    report_section "Backup Verification"
    local min_size_kb="${BACKUP_MIN_SIZE_KB:-1}"

    # Common backup locations to scan
    local backup_dirs=(/var/backups /backup /backups /home/*/backup /root/backup)
    local found_any=0

    for dir in "${backup_dirs[@]}"; do
        [[ -d "$dir" ]] || continue
        # Look for files modified in last 7 days
        while IFS= read -r f; do
            found_any=1
            local size_kb; size_kb=$(du -k "$f" 2>/dev/null | awk '{print $1}')
            local age_days=$(( ( $(date +%s) - $(stat -c %Y "$f") ) / 86400 ))
            if (( size_kb < min_size_kb )); then
                report_fail "Backup suspiciously small (${size_kb}k): ${f}"
            elif (( age_days > 1 )); then
                report_warn "Backup is ${age_days} days old: ${f}"
            else
                report_pass "Backup ok (${size_kb}k, ${age_days}d old): ${f}"
            fi

            # Size sanity vs previous
            local state_dir="${LOG_DIR:-$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../..}/logs/state"
            mkdir -p "$state_dir"
            local state_file="${state_dir}/backup_verify.state"
            local fname; fname=$(basename "$f")
            local prev_size; prev_size=$(grep "^${fname} " "$state_file" 2>/dev/null | awk '{print $2}' || true)
            if [[ -n "$prev_size" ]] && (( prev_size > 0 )); then
                local ratio=$(( size_kb * 100 / prev_size ))
                if (( ratio < 50 )); then
                    report_fail "Backup shrank >50% vs last check: ${f} (was ${prev_size}k, now ${size_kb}k)"
                fi
            fi
            # Update state
            grep -v "^${fname} " "$state_file" 2>/dev/null > "${state_file}.tmp" || true
            echo "${fname} ${size_kb}" >> "${state_file}.tmp"
            mv "${state_file}.tmp" "$state_file"
        done < <(find "$dir" -maxdepth 3 -type f \( -name '*.tar.gz' -o -name '*.tar.bz2' -o -name '*.sql.gz' -o -name '*.bak' -o -name '*.dump' \) 2>/dev/null)
    done

    [[ $found_any -eq 0 ]] && report_warn "No backup files found in common locations"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    SCRIPT_DIR="$(dirname "$(realpath "$0")")"
    source "${SCRIPT_DIR}/../../config/ubuntils.conf" 2>/dev/null || true
    source "${SCRIPT_DIR}/../../config/modules.conf" 2>/dev/null || true
    [[ "${maintenance_backup_verify:-1}" -eq 1 ]] || exit 0
    report_start "backup_verify"
    check_backup_verify
    report_finish
fi
