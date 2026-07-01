#!/usr/bin/env bash
# modules/security/php_security.sh — PHP version EOL, dangerous config, phpinfo exposure

_MDIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
source "${_MDIR}/../../lib/report.sh"

# EOL PHP versions (update as needed)
_PHP_EOL_VERSIONS="5.6 7.0 7.1 7.2 7.3 7.4 8.0 8.1"

check_php_versions() {
    report_section "PHP Version EOL Check"
    [[ "${PHP_INSTALLED:-0}" -ne 0 || -n "${PHP_VERSIONS:-}" ]] || {
        report_info "PHP not detected"
        return
    }
    [[ "${security_php_versions:-1}" -eq 1 ]] || return

    IFS=',' read -ra versions <<< "${PHP_VERSIONS:-}"
    for v in "${versions[@]}"; do
        [[ -z "$v" ]] && continue
        if echo "$_PHP_EOL_VERSIONS" | grep -qw "$v"; then
            report_fail "PHP ${v} is EOL — upgrade immediately"
        else
            report_pass "PHP ${v} is supported"
        fi
    done
}

check_php_config() {
    report_section "PHP Configuration"
    [[ "${security_php_config:-1}" -eq 1 ]] || return
    [[ -n "${PHP_VERSIONS:-}" ]] || { report_info "PHP not detected"; return; }

    IFS=',' read -ra versions <<< "${PHP_VERSIONS:-}"
    for v in "${versions[@]}"; do
        [[ -z "$v" ]] && continue
        local ini_files=()
        while IFS= read -r f; do ini_files+=("$f"); done \
            < <(find /etc/php/"$v" -name 'php.ini' 2>/dev/null)
        [[ ${#ini_files[@]} -eq 0 ]] && continue

        for ini in "${ini_files[@]}"; do
            local ctx; ctx=$(echo "$ini" | grep -oP '(fpm|cli|apache2|cgi)' | head -1)
            ctx="${ctx:-unknown}"

            # display_errors in prod
            local disp; disp=$(grep -iE '^\s*display_errors\s*=' "$ini" 2>/dev/null | awk -F= '{print $2}' | tr -d ' ' | tail -1)
            if [[ "${disp,,}" == "on" || "$disp" == "1" ]]; then
                [[ "$ctx" != "cli" ]] && report_warn "PHP ${v} (${ctx}): display_errors=On — disable in production"
            else
                report_pass "PHP ${v} (${ctx}): display_errors off"
            fi

            # expose_php
            local expose; expose=$(grep -iE '^\s*expose_php\s*=' "$ini" 2>/dev/null | awk -F= '{print $2}' | tr -d ' ' | tail -1)
            if [[ "${expose,,}" == "on" || "$expose" == "1" ]]; then
                report_warn "PHP ${v} (${ctx}): expose_php=On — leaks version info"
            fi

            # dangerous disabled_functions
            local disabled; disabled=$(grep -iE '^\s*disable_functions\s*=' "$ini" 2>/dev/null | awk -F= '{$1=""; print}' | tail -1)
            local dangerous=(exec passthru shell_exec system popen proc_open)
            local missing=()
            for fn in "${dangerous[@]}"; do
                echo "$disabled" | grep -qw "$fn" || missing+=("$fn")
            done
            if [[ ${#missing[@]} -gt 0 ]]; then
                report_warn "PHP ${v} (${ctx}): dangerous functions not disabled: ${missing[*]}"
            else
                report_pass "PHP ${v} (${ctx}): dangerous functions disabled"
            fi
        done
    done
}

check_phpinfo_exposure() {
    report_section "phpinfo() Exposure"
    [[ "${security_php_phpinfo:-1}" -eq 1 ]] || return

    local doc_roots="${DOC_ROOTS:-/var/www/html}"
    IFS=',' read -ra roots <<< "$doc_roots"
    local found=0
    for root in "${roots[@]}"; do
        [[ -d "$root" ]] || continue
        while IFS= read -r f; do
            if grep -qiE 'phpinfo\s*\(' "$f" 2>/dev/null; then
                report_fail "phpinfo() found in: ${f}"
                found=1
            fi
        done < <(find "$root" -maxdepth 4 -name '*.php' -type f 2>/dev/null | head -200)
    done
    [[ $found -eq 0 ]] && report_pass "No exposed phpinfo() files found"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    SCRIPT_DIR="$(dirname "$(realpath "$0")")"
    source "${SCRIPT_DIR}/../../config/ubuntils.conf" 2>/dev/null || true
    source "${SCRIPT_DIR}/../../config/modules.conf" 2>/dev/null || true
    source "${SCRIPT_DIR}/../../lib/detect.sh"
    detect_load
    report_start "php_security"
    check_php_versions
    check_php_config
    check_phpinfo_exposure
    report_finish
fi
