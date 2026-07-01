#!/usr/bin/env bash
# modules/maintenance/cron_scripts.sh

_MDIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
source "${_MDIR}/../../lib/report.sh"

check_cron_scripts() {
    report_section "Cron Job Script Validity"

    local broken=0

    # Check system crontabs
    local cron_dirs=(/etc/cron.d /etc/cron.daily /etc/cron.weekly /etc/cron.monthly /etc/cron.hourly)
    for dir in "${cron_dirs[@]}"; do
        [[ -d "$dir" ]] || continue
        while IFS= read -r f; do
            # Extract script paths from crontab entries
            while IFS= read -r line; do
                [[ "$line" =~ ^#   ]] && continue
                [[ "$line" =~ ^[[:space:]]*$ ]] && continue
                # Get the command part (after time fields for cron.d, or just the command for run-parts dirs)
                local cmd
                cmd=$(echo "$line" | awk '{
                    # skip env assignments
                    if ($0 ~ /=/) next
                    # cron.d format: min hr dom mon dow user cmd
                    # try to get a script path
                    for(i=1;i<=NF;i++) if($i ~ /^\//) {print $i; exit}
                }')
                [[ -z "$cmd" ]] && continue
                # Strip arguments
                local script="${cmd%% *}"
                if [[ -n "$script" ]] && ! [[ -e "$script" ]]; then
                    report_warn "Cron entry references missing file: ${script} (in ${f})"
                    broken=1
                fi
            done < "$f"
        done < <(find "$dir" -maxdepth 1 -type f 2>/dev/null)
    done

    # Check root's crontab
    local root_crontab; root_crontab=$(crontab -l -u root 2>/dev/null || true)
    while IFS= read -r line; do
        [[ "$line" =~ ^# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        local script
        script=$(echo "$line" | awk '{for(i=6;i<=NF;i++) if($i ~ /^\//) {print $i; exit}}')
        [[ -z "$script" ]] && continue
        script="${script%% *}"
        if [[ -n "$script" ]] && ! [[ -e "$script" ]]; then
            report_warn "Root crontab references missing file: ${script}"
            broken=1
        fi
    done <<< "$root_crontab"

    [[ $broken -eq 0 ]] && report_pass "All cron job scripts exist"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    SCRIPT_DIR="$(dirname "$(realpath "$0")")"
    source "${SCRIPT_DIR}/../../config/ubuntils.conf" 2>/dev/null || true
    source "${SCRIPT_DIR}/../../config/modules.conf" 2>/dev/null || true
    [[ "${maintenance_cron_scripts:-1}" -eq 1 ]] || exit 0
    report_start "cron_scripts"
    check_cron_scripts
    report_finish
fi
