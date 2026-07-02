#!/usr/bin/env bash
# modules/optimize/sysctl.sh — sysctl tuning suggestions

_MDIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
source "${_MDIR}/../../lib/report.sh"
source "${_MDIR}/../../lib/backup.sh"

_SYSCTL_CONF="/etc/sysctl.d/99-ubuntils.conf"

_suggest_sysctl() {
    local key="$1" suggested="$2" reason="$3" auto="${4:-}"
    local current; current=$(sysctl -n "$key" 2>/dev/null || echo "unknown")

    if [[ "$current" == "$suggested" ]]; then
        report_pass "sysctl ${key}=${current} (already optimal)"
        return
    fi

    report_warn "sysctl ${key}: current=${current}, suggested=${suggested} — ${reason}"

    local do_apply=0
    if [[ "$auto" == "--auto" ]]; then
        do_apply=1
    elif command -v whiptail &>/dev/null; then
        whiptail --title "Apply sysctl change?" \
            --yesno "Set ${key} = ${suggested}?\n(currently: ${current})\n${reason}" 12 70
        [[ $? -eq 0 ]] && do_apply=1
    else
        read -rp "Set ${key} = ${suggested}? [y/N] " ans
        [[ "$ans" =~ ^[Yy]$ ]] && do_apply=1
    fi

    if [[ "$do_apply" -eq 1 ]]; then
        sysctl -w "${key}=${suggested}" &>/dev/null
        grep -q "^${key} " "$_SYSCTL_CONF" 2>/dev/null && sed -i "\|^${key} |d" "$_SYSCTL_CONF"
        echo "${key} = ${suggested}" >> "$_SYSCTL_CONF"
        report_info "Applied: ${key}=${suggested}"
    fi
}

optimize_sysctl() {
    report_section "Sysctl Tuning"
    local auto="${1:-}"
    [[ "${optimize_sysctl:-1}" -eq 1 ]] || return

    local ram_kb; ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local ram_gb=$(( ram_kb / 1024 / 1024 ))

    # Swappiness (handled separately, but include here for completeness)
    _suggest_sysctl "vm.swappiness" "10" "reduce swap usage for server workloads" "$auto"

    # Network tuning
    _suggest_sysctl "net.core.somaxconn" "1024" "increase listen backlog for high-traffic servers" "$auto"
    _suggest_sysctl "net.ipv4.tcp_max_syn_backlog" "2048" "protect against SYN flood" "$auto"
    _suggest_sysctl "net.ipv4.ip_local_port_range" "1024 65535" "increase ephemeral port range" "$auto"

    # File descriptors
    _suggest_sysctl "fs.file-max" "100000" "max open files" "$auto"

    if [[ "$auto" == "--auto" ]]; then
        sysctl -p "$_SYSCTL_CONF" &>/dev/null
        report_pass "sysctl settings persisted to ${_SYSCTL_CONF}"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    SCRIPT_DIR="$(dirname "$(realpath "$0")")"
    source "${SCRIPT_DIR}/../../config/ubuntils.conf" 2>/dev/null || true
    source "${SCRIPT_DIR}/../../config/modules.conf" 2>/dev/null || true
    [[ "${optimize_sysctl:-1}" -eq 1 ]] || exit 0
    AUTO="${1:-}"
    report_start "sysctl"
    optimize_sysctl "$AUTO"
    report_finish
fi
