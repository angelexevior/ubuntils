#!/usr/bin/env bash
# modules/security/ssh_config.sh

_MDIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
source "${_MDIR}/../../lib/report.sh"

check_ssh_config() {
    report_section "SSH Configuration"
    local sshd_config="/etc/ssh/sshd_config"

    if [[ ! -f "$sshd_config" ]]; then
        report_info "SSH not configured (/etc/ssh/sshd_config missing)"
        return
    fi

    # Root login
    local permit_root; permit_root=$(grep -iE '^\s*PermitRootLogin' "$sshd_config" | awk '{print $2}' | tail -1)
    case "${permit_root,,}" in
        no|prohibit-password) report_pass "PermitRootLogin: ${permit_root:-not set (default: prohibit-password)}" ;;
        yes) report_fail "PermitRootLogin: yes — root can SSH in with password" ;;
        "")  report_warn "PermitRootLogin not explicitly set (check default)" ;;
        *)   report_warn "PermitRootLogin: ${permit_root}" ;;
    esac

    # Password auth
    local password_auth; password_auth=$(grep -iE '^\s*PasswordAuthentication' "$sshd_config" | awk '{print $2}' | tail -1)
    case "${password_auth,,}" in
        no)  report_pass "PasswordAuthentication: no" ;;
        yes) report_warn "PasswordAuthentication: yes — prefer key-based auth" ;;
        "")  report_warn "PasswordAuthentication not set (default: yes)" ;;
        *)   report_info "PasswordAuthentication: ${password_auth}" ;;
    esac

    # Protocol (SSHv1 is deprecated)
    local protocol; protocol=$(grep -iE '^\s*Protocol' "$sshd_config" | awk '{print $2}' | tail -1)
    if [[ "${protocol}" == "1" ]]; then
        report_fail "SSH Protocol 1 enabled — insecure, use Protocol 2"
    elif [[ -n "$protocol" ]]; then
        report_pass "SSH Protocol: ${protocol}"
    fi

    # Port
    local port; port=$(grep -iE '^\s*Port ' "$sshd_config" | awk '{print $2}' | tail -1)
    [[ -z "$port" ]] && port="22"
    if [[ "$port" == "22" ]]; then
        report_warn "SSH on default port 22 (consider changing to reduce scan noise)"
    else
        report_pass "SSH on non-default port: ${port}"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    SCRIPT_DIR="$(dirname "$(realpath "$0")")"
    source "${SCRIPT_DIR}/../../config/ubuntils.conf" 2>/dev/null || true
    source "${SCRIPT_DIR}/../../config/modules.conf" 2>/dev/null || true
    [[ "${security_ssh_config:-1}" -eq 1 ]] || exit 0
    report_start "ssh_config"
    check_ssh_config
    report_finish
fi
