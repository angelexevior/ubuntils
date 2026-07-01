#!/usr/bin/env bash
# modules/monitor/run.sh — cron-driven monitor; alerts only on threshold cross

set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
BASE_DIR="${SCRIPT_DIR}/../.."

source "${BASE_DIR}/config/ubuntils.conf"
source "${BASE_DIR}/config/modules.conf"
source "${BASE_DIR}/lib/report.sh"
source "${BASE_DIR}/lib/notify.sh"
source "${BASE_DIR}/lib/detect.sh"
detect_load

STATE_DIR="${LOG_DIR}/state"
mkdir -p "$STATE_DIR"

_get_state()  { cat "${STATE_DIR}/${1}.state" 2>/dev/null || echo "0"; }
_set_state()  { echo "$2" > "${STATE_DIR}/${1}.state"; }

# Alert only on threshold cross (0=ok, 1=alerted)
_check_threshold() {
    local name="$1" value="$2" warn="$3" crit="$4" label="$5"
    local prev_state; prev_state=$(_get_state "$name")

    local new_state=0 msg="" severity=""
    if (( $(echo "$value >= $crit" | bc -l 2>/dev/null || echo 0) )); then
        new_state=2; severity="CRITICAL"; msg="${label}: ${value} (threshold: ${crit})"
    elif (( $(echo "$value >= $warn" | bc -l 2>/dev/null || echo 0) )); then
        new_state=1; severity="WARNING"; msg="${label}: ${value} (threshold: ${warn})"
    fi

    if [[ "$new_state" -gt 0 && "$prev_state" -ne "$new_state" ]]; then
        report_warn "[${severity}] ${msg}"
        notify_all "[ubuntils ${severity}] ${label}" "$msg"
    elif [[ "$new_state" -eq 0 && "$prev_state" -gt 0 ]]; then
        report_pass "${label} recovered: ${value}"
        notify_all "[ubuntils RECOVERED] ${label}" "${label} is back to normal: ${value}"
    fi

    _set_state "$name" "$new_state"
}

# Load average
if [[ "${monitor_load:-1}" -eq 1 ]]; then
    load1=$(awk '{print $1}' /proc/loadavg)
    _check_threshold "load" "$load1" "${LOAD_AVG_WARN:-4}" "${LOAD_AVG_CRIT:-8}" "Load average (1m)"
fi

# Disk usage
if [[ "${monitor_disk:-1}" -eq 1 ]]; then
    while IFS= read -r line; do
        use_pct=$(echo "$line" | awk '{print $5}' | tr -d '%')
        mount=$(echo "$line" | awk '{print $6}')
        [[ "$use_pct" =~ ^[0-9]+$ ]] || continue
        _check_threshold "disk_${mount//\//_}" "$use_pct" "${DISK_WARN:-80}" "${DISK_CRIT:-90}" "Disk ${mount}"
    done < <(df -h --output=source,size,used,avail,pcent,target 2>/dev/null | grep -v '^tmpfs\|^devtmpfs\|^udev\|Filesystem')
fi

# 4xx rate from nginx/apache logs
if [[ "${monitor_4xx_rate:-1}" -eq 1 ]]; then
    rate_4xx=0
    for log in /var/log/nginx/access.log /var/log/apache2/access.log; do
        [[ -f "$log" ]] || continue
        # Count 4xx in last minute (use log lines with recent timestamps is hard without awk+date)
        # Approximate: last 100 lines
        rate_4xx=$(tail -200 "$log" 2>/dev/null | awk '$9 ~ /^4[0-9][0-9]$/' | wc -l || echo 0)
        break
    done
    warn_rate="${RATE_4XX_WARN:-50}"
    if (( rate_4xx >= warn_rate )); then
        prev=$(_get_state "rate_4xx")
        if [[ "$prev" -eq 0 ]]; then
            notify_all "[ubuntils WARNING] High 4xx rate" "4xx error rate: ${rate_4xx} (last 200 requests, threshold: ${warn_rate}/min)"
        fi
        _set_state "rate_4xx" "1"
        report_warn "4xx rate: ${rate_4xx} (last 200 requests)"
    else
        _set_state "rate_4xx" "0"
    fi
fi

# Slow queries
if [[ "${monitor_slow_queries:-1}" -eq 1 && -n "${DB_TYPE:-}" ]]; then
    slow_log_file=$(mysql --defaults-file=/etc/mysql/debian.cnf -N -e "SHOW VARIABLES LIKE 'slow_query_log_file';" 2>/dev/null | awk '{print $2}' || true)
    if [[ -f "${slow_log_file:-}" ]]; then
        slow_count=$(tail -200 "$slow_log_file" 2>/dev/null | grep -c '^# Query_time' || echo 0)
        warn_slow="${SLOW_QUERIES_WARN:-10}"
        if (( slow_count >= warn_slow )); then
            prev=$(_get_state "slow_queries")
            [[ "$prev" -eq 0 ]] && notify_all "[ubuntils WARNING] Slow queries" "Slow query count: ${slow_count} (last 200 log entries)"
            _set_state "slow_queries" "1"
        else
            _set_state "slow_queries" "0"
        fi
    fi
fi

# Failed SSH attempts
if [[ "${monitor_failed_ssh:-1}" -eq 1 ]]; then
    failed_ssh=0
    if command -v journalctl &>/dev/null; then
        failed_ssh=$(journalctl -u ssh --since "1 minute ago" 2>/dev/null | grep -c 'Failed password\|Invalid user' || echo 0)
    elif [[ -f /var/log/auth.log ]]; then
        failed_ssh=$(awk -v d="$(date '+%b %e %H:%M' --date='1 minute ago')" '$0>d' /var/log/auth.log 2>/dev/null | grep -c 'Failed password\|Invalid user' || echo 0)
    fi
    _check_threshold "failed_ssh" "$failed_ssh" "${FAILED_SSH_WARN:-5}" "999" "Failed SSH logins (last minute)"
fi

report_finish 2>/dev/null || true
