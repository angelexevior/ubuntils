#!/usr/bin/env bash
# modules/optimize/php_fpm.sh — PHP-FPM pm.max_children tuning

_MDIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
source "${_MDIR}/../../lib/report.sh"
source "${_MDIR}/../../lib/backup.sh"

optimize_php_fpm() {
    report_section "PHP-FPM Optimization"
    local auto="${1:-}"
    [[ "${optimize_php_fpm:-1}" -eq 1 ]] || return

    if [[ "${PHP_MODE:-}" != "fpm" ]]; then
        report_info "PHP-FPM not detected — skipping"
        return
    fi

    local ram_kb; ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local ram_mb=$(( ram_kb / 1024 ))

    # Estimate avg PHP-FPM process memory (sample current processes or use 50MB default)
    local avg_mem_mb=50
    local php_procs; php_procs=$(ps -o rss= -C php-fpm 2>/dev/null | head -20)
    if [[ -n "$php_procs" ]]; then
        local total_rss count
        total_rss=$(echo "$php_procs" | awk '{s+=$1} END{print s}')
        count=$(echo "$php_procs" | wc -l)
        (( count > 0 )) && avg_mem_mb=$(( total_rss / count / 1024 ))
        (( avg_mem_mb < 16 )) && avg_mem_mb=50  # sanity floor
    fi

    # Reserve 256MB for OS/other services
    local usable_mb=$(( ram_mb - 256 ))
    local suggested_max=$(( usable_mb / avg_mem_mb ))
    (( suggested_max < 2 )) && suggested_max=2

    report_info "RAM: ${ram_mb}MB, avg PHP-FPM process: ~${avg_mem_mb}MB"
    report_info "Suggested pm.max_children: ${suggested_max}"

    IFS=',' read -ra versions <<< "${PHP_VERSIONS:-}"
    for v in "${versions[@]}"; do
        [[ -z "$v" ]] && continue
        local pool_dirs=("/etc/php/${v}/fpm/pool.d")
        for pool_dir in "${pool_dirs[@]}"; do
            [[ -d "$pool_dir" ]] || continue
            while IFS= read -r pool_file; do
                local current_max; current_max=$(grep -E '^\s*pm\.max_children\s*=' "$pool_file" | awk -F= '{print $2}' | tr -d ' ' | tail -1)
                if [[ -z "$current_max" ]]; then
                    report_warn "PHP ${v} pool ${pool_file}: pm.max_children not set (suggested: ${suggested_max})"
                elif (( current_max > suggested_max * 2 )); then
                    report_warn "PHP ${v} pool ${pool_file}: pm.max_children=${current_max} too high (suggested: ${suggested_max})"
                elif (( current_max < 2 )); then
                    report_warn "PHP ${v} pool ${pool_file}: pm.max_children=${current_max} too low"
                else
                    report_pass "PHP ${v} pool ${pool_file}: pm.max_children=${current_max}"
                fi

                if [[ "$auto" == "--auto" && -n "$current_max" && "$current_max" != "$suggested_max" ]]; then
                    local tmp; tmp=$(mktemp)
                    sed "s/^\s*pm\.max_children\s*=.*/pm.max_children = ${suggested_max}/" "$pool_file" > "$tmp"
                    backup_diff_apply "$pool_file" "$tmp" "--auto"
                    rm -f "$tmp"
                fi
            done < <(find "$pool_dir" -name '*.conf' -type f 2>/dev/null)
        done
    done

    if [[ "$auto" == "--auto" ]]; then
        IFS=',' read -ra versions2 <<< "${PHP_VERSIONS:-}"
        for v in "${versions2[@]}"; do
            systemctl reload "php${v}-fpm" &>/dev/null && report_info "Reloaded php${v}-fpm" || true
        done
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    SCRIPT_DIR="$(dirname "$(realpath "$0")")"
    source "${SCRIPT_DIR}/../../config/ubuntils.conf" 2>/dev/null || true
    source "${SCRIPT_DIR}/../../config/modules.conf" 2>/dev/null || true
    source "${SCRIPT_DIR}/../../lib/detect.sh"
    detect_load
    [[ "${optimize_php_fpm:-1}" -eq 1 ]] || exit 0
    AUTO="${1:-}"
    report_start "php_fpm_optimize"
    optimize_php_fpm "$AUTO"
    report_finish
fi
