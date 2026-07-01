#!/usr/bin/env bash
# modules/maintenance/inode_usage.sh

_MDIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
source "${_MDIR}/../../lib/report.sh"

check_inode_usage() {
    report_section "Inode Usage"
    local warn_pct="${DISK_INODE_WARN:-80}" crit_pct="${DISK_INODE_CRIT:-90}"

    while IFS= read -r line; do
        local use_pct fs mount
        use_pct=$(echo "$line" | awk '{print $5}' | tr -d '%')
        fs=$(echo "$line" | awk '{print $1}')
        mount=$(echo "$line" | awk '{print $6}')
        [[ "$fs" == "Filesystem" ]] && continue
        [[ "$use_pct" =~ ^[0-9]+$ ]] || continue
        [[ "$use_pct" == "-" ]] && continue

        if (( use_pct >= crit_pct )); then
            report_fail "${mount}: inodes ${use_pct}% used"
        elif (( use_pct >= warn_pct )); then
            report_warn "${mount}: inodes ${use_pct}% used"
        else
            report_pass "${mount}: inodes ${use_pct}% used"
        fi
    done < <(df -i 2>/dev/null | grep -v '^tmpfs\|^devtmpfs\|^udev')
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    SCRIPT_DIR="$(dirname "$(realpath "$0")")"
    source "${SCRIPT_DIR}/../../config/ubuntils.conf" 2>/dev/null || true
    source "${SCRIPT_DIR}/../../config/modules.conf" 2>/dev/null || true
    [[ "${maintenance_inode_usage:-1}" -eq 1 ]] || exit 0
    report_start "inode_usage"
    check_inode_usage
    report_finish
fi
