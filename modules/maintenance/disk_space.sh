#!/usr/bin/env bash
# modules/maintenance/disk_space.sh

_MDIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
source "${_MDIR}/../../lib/report.sh"

check_disk_space() {
    report_section "Disk Space"
    local warn_pct="${DISK_WARN:-80}" crit_pct="${DISK_CRIT:-90}"

    # Check usage per filesystem
    while IFS= read -r line; do
        local use_pct fs mount
        use_pct=$(echo "$line" | awk '{print $5}' | tr -d '%')
        fs=$(echo "$line" | awk '{print $1}')
        mount=$(echo "$line" | awk '{print $6}')
        [[ "$fs" == "Filesystem" ]] && continue
        [[ "$use_pct" =~ ^[0-9]+$ ]] || continue

        if (( use_pct >= crit_pct )); then
            report_fail "${mount} (${fs}): ${use_pct}% used"
        elif (( use_pct >= warn_pct )); then
            report_warn "${mount} (${fs}): ${use_pct}% used"
        else
            report_pass "${mount} (${fs}): ${use_pct}% used"
        fi
    done < <(df -h --output=source,size,used,avail,pcent,target 2>/dev/null | grep -v '^tmpfs\|^devtmpfs\|^udev')

    # Largest growth delta vs last run
    local state_dir="${LOG_DIR:-$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../..}/logs/state"
    mkdir -p "$state_dir"
    local state_file="${state_dir}/disk_space.state"
    local current_sizes; current_sizes=$(df -k | awk 'NR>1 && /^\// {print $6,$3}')

    if [[ -f "$state_file" ]]; then
        while IFS= read -r cur_line; do
            local mount used
            mount=$(echo "$cur_line" | awk '{print $1}')
            used=$(echo "$cur_line" | awk '{print $2}')
            local prev_used; prev_used=$(grep "^${mount} " "$state_file" 2>/dev/null | awk '{print $2}')
            if [[ -n "$prev_used" ]] && (( used - prev_used > 1048576 )); then
                local delta_mb=$(( (used - prev_used) / 1024 ))
                report_warn "Large growth on ${mount}: +${delta_mb}MB since last run"
            fi
        done <<< "$current_sizes"
    fi

    echo "$current_sizes" > "$state_file"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    SCRIPT_DIR="$(dirname "$(realpath "$0")")"
    source "${SCRIPT_DIR}/../../config/ubuntils.conf" 2>/dev/null || true
    source "${SCRIPT_DIR}/../../config/modules.conf" 2>/dev/null || true
    [[ "${maintenance_disk_space:-1}" -eq 1 ]] || exit 0
    report_start "disk_space"
    check_disk_space
    report_finish
fi
