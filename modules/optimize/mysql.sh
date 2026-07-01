#!/usr/bin/env bash
# modules/optimize/mysql.sh — MySQL/MariaDB tuning suggestions

_MDIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
source "${_MDIR}/../../lib/report.sh"
source "${_MDIR}/../../lib/backup.sh"

_mysql_var() {
    mysql --defaults-file=/etc/mysql/debian.cnf -N -e "SHOW VARIABLES LIKE '$1';" 2>/dev/null | awk '{print $2}' \
        || mysql -u root -N -e "SHOW VARIABLES LIKE '$1';" 2>/dev/null | awk '{print $2}' \
        || true
}

optimize_mysql() {
    report_section "MySQL/MariaDB Optimization"
    local auto="${1:-}"
    [[ "${optimize_mysql:-1}" -eq 1 ]] || return

    if [[ -z "${DB_TYPE:-}" ]]; then
        report_info "MySQL/MariaDB not detected — skipping"
        return
    fi

    local ram_kb; ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local ram_mb=$(( ram_kb / 1024 ))

    # innodb_buffer_pool_size — 50-70% of RAM for dedicated DB server
    local suggested_pool_mb=$(( ram_mb * 60 / 100 ))
    local suggested_pool="${suggested_pool_mb}M"
    local current_pool; current_pool=$(_mysql_var innodb_buffer_pool_size)
    local current_pool_mb=$(( ${current_pool:-0} / 1024 / 1024 ))

    if (( current_pool_mb < suggested_pool_mb / 2 )); then
        report_warn "innodb_buffer_pool_size: current=${current_pool_mb}M, suggested=${suggested_pool_mb}M (60% of RAM)"
    else
        report_pass "innodb_buffer_pool_size: ${current_pool_mb}M"
    fi

    # max_connections — rough: 50 + (RAM_MB / 4)
    local suggested_conn=$(( 50 + ram_mb / 4 ))
    local current_conn; current_conn=$(_mysql_var max_connections)
    if (( ${current_conn:-0} < 50 )); then
        report_warn "max_connections: current=${current_conn}, suggested=${suggested_conn}"
    elif (( ${current_conn:-0} > suggested_conn * 3 )); then
        report_warn "max_connections: ${current_conn} may be too high for available RAM (suggested: ${suggested_conn})"
    else
        report_pass "max_connections: ${current_conn}"
    fi

    # slow_query_log
    local slow_log; slow_log=$(_mysql_var slow_query_log)
    if [[ "${slow_log,,}" != "on" && "$slow_log" != "1" ]]; then
        report_warn "slow_query_log is OFF — enable to identify performance issues"
    else
        report_pass "slow_query_log: enabled"
    fi

    if [[ "$auto" == "--auto" ]]; then
        local my_cnf
        for f in /etc/mysql/mysql.conf.d/mysqld.cnf /etc/mysql/my.cnf /etc/my.cnf; do
            [[ -f "$f" ]] && { my_cnf="$f"; break; }
        done
        if [[ -n "${my_cnf:-}" ]]; then
            local tmp; tmp=$(mktemp)
            cp "$my_cnf" "$tmp"
            # Add/update innodb_buffer_pool_size and max_connections under [mysqld]
            python3 - "$tmp" "$suggested_pool" "$suggested_conn" <<'PYEOF'
import sys, re
f, pool, conn = sys.argv[1], sys.argv[2], sys.argv[3]
lines = open(f).readlines()
in_mysqld = False
new_lines = []
keys = {'innodb_buffer_pool_size': pool, 'max_connections': conn}
seen = set()
for line in lines:
    stripped = line.strip()
    if stripped.startswith('['):
        in_mysqld = stripped == '[mysqld]'
    if in_mysqld:
        for k, v in keys.items():
            if re.match(r'^\s*' + k + r'\s*=', line, re.I):
                line = f'{k} = {v}\n'
                seen.add(k)
    new_lines.append(line)
if in_mysqld:
    for k, v in keys.items():
        if k not in seen:
            new_lines.append(f'{k} = {v}\n')
open(f, 'w').writelines(new_lines)
PYEOF
            backup_diff_apply "$my_cnf" "$tmp" "--auto"
            rm -f "$tmp"
            systemctl restart mysql &>/dev/null || systemctl restart mariadb &>/dev/null || true
            report_info "MySQL restarted with new config"
        fi
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    SCRIPT_DIR="$(dirname "$(realpath "$0")")"
    source "${SCRIPT_DIR}/../../config/ubuntils.conf" 2>/dev/null || true
    source "${SCRIPT_DIR}/../../config/modules.conf" 2>/dev/null || true
    source "${SCRIPT_DIR}/../../lib/detect.sh"
    detect_load
    [[ "${optimize_mysql:-1}" -eq 1 ]] || exit 0
    AUTO="${1:-}"
    report_start "mysql_optimize"
    optimize_mysql "$AUTO"
    report_finish
fi
