#!/usr/bin/env bash
# modules/security/open_ports.sh

_MDIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
source "${_MDIR}/../../lib/report.sh"

check_open_ports() {
    report_section "Open Ports"

    local baseline="${PORTS_BASELINE:-22 80 443}"
    local listening_ports=()

    if command -v ss &>/dev/null; then
        while IFS= read -r line; do
            # ss -tlnp: State Recv-Q Send-Q Local-Addr:Port Peer-Addr:Port [Process]
            local port; port=$(echo "$line" | awk '{print $4}' | grep -oP ':\K[0-9]+$' | head -1)
            [[ -n "$port" ]] && listening_ports+=("$port")
        done < <(ss -tlnp 2>/dev/null | grep LISTEN)
    elif command -v netstat &>/dev/null; then
        while IFS= read -r line; do
            local port; port=$(echo "$line" | awk '{print $4}' | grep -oP ':\K[0-9]+$' | head -1)
            [[ -n "$port" ]] && listening_ports+=("$port")
        done < <(netstat -tlnp 2>/dev/null | grep LISTEN)
    else
        report_warn "Neither ss nor netstat available — cannot check ports"
        return
    fi

    # Deduplicate and sort
    local -A seen=()
    local unique_ports=()
    for p in "${listening_ports[@]}"; do
        [[ -z "${seen[$p]:-}" ]] && { seen[$p]=1; unique_ports+=("$p"); }
    done
    IFS=$'\n' unique_ports=($(sort -n <<<"${unique_ports[*]}")); unset IFS

    for port in "${unique_ports[@]}"; do
        if echo " $baseline " | grep -qw "$port"; then
            report_pass "Port ${port}: in baseline"
        else
            report_warn "Port ${port}: open but NOT in PORTS_BASELINE"
        fi
    done

    # Flag baseline ports that are closed
    for bp in $baseline; do
        if ! printf '%s\n' "${unique_ports[@]}" | grep -qx "$bp"; then
            report_info "Baseline port ${bp} is NOT listening"
        fi
    done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    SCRIPT_DIR="$(dirname "$(realpath "$0")")"
    source "${SCRIPT_DIR}/../../config/ubuntils.conf" 2>/dev/null || true
    source "${SCRIPT_DIR}/../../config/modules.conf" 2>/dev/null || true
    [[ "${security_open_ports:-1}" -eq 1 ]] || exit 0
    report_start "open_ports"
    check_open_ports
    report_finish
fi
