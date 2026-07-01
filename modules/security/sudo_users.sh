#!/usr/bin/env bash
# modules/security/sudo_users.sh

_MDIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
source "${_MDIR}/../../lib/report.sh"

check_sudo_users() {
    report_section "Sudo Users"

    local actual_sudoers=()
    # Users in sudo group
    while IFS=: read -r _ _ _ members; do
        IFS=',' read -ra actual_sudoers <<< "$members"
    done < <(getent group sudo 2>/dev/null || grep '^sudo:' /etc/group 2>/dev/null || true)
    # Also check admin group (Ubuntu)
    while IFS=: read -r _ _ _ members; do
        local admin_members; IFS=',' read -ra admin_members <<< "$members"
        for m in "${admin_members[@]}"; do
            [[ -n "$m" ]] && actual_sudoers+=("$m")
        done
    done < <(getent group admin 2>/dev/null || grep '^admin:' /etc/group 2>/dev/null || true)

    # Deduplicate
    local -A seen=()
    local unique=()
    for u in "${actual_sudoers[@]}"; do
        [[ -z "$u" ]] && continue
        [[ -z "${seen[$u]:-}" ]] && { seen[$u]=1; unique+=("$u"); }
    done

    report_info "Sudo-capable users: ${unique[*]:-none}"

    # Flag users not in baseline
    local baseline="${SUDO_BASELINE_USERS:-}"
    if [[ -n "$baseline" ]]; then
        for u in "${unique[@]}"; do
            if ! echo " $baseline " | grep -qw "$u"; then
                report_warn "Unexpected sudo user: ${u} (not in SUDO_BASELINE_USERS)"
            else
                report_pass "Sudo user in baseline: ${u}"
            fi
        done
    else
        report_info "SUDO_BASELINE_USERS not set — set it in modules.conf to enable drift detection"
    fi

    # Check /etc/sudoers for NOPASSWD
    if grep -qE '^\s*[^#].*NOPASSWD' /etc/sudoers 2>/dev/null; then
        report_warn "NOPASSWD found in /etc/sudoers — review manually"
    fi
    if ls /etc/sudoers.d/ 2>/dev/null | xargs -I{} grep -lE 'NOPASSWD' /etc/sudoers.d/{} 2>/dev/null | grep -q .; then
        report_warn "NOPASSWD found in /etc/sudoers.d/ — review manually"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    SCRIPT_DIR="$(dirname "$(realpath "$0")")"
    source "${SCRIPT_DIR}/../../config/ubuntils.conf" 2>/dev/null || true
    source "${SCRIPT_DIR}/../../config/modules.conf" 2>/dev/null || true
    [[ "${security_sudo_users:-1}" -eq 1 ]] || exit 0
    report_start "sudo_users"
    check_sudo_users
    report_finish
fi
