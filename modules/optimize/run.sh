#!/usr/bin/env bash
# modules/optimize/run.sh — runs all enabled optimize checks/tuning

set -uo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
BASE_DIR="${SCRIPT_DIR}/../.."

source "${BASE_DIR}/config/ubuntils.conf"
source "${BASE_DIR}/config/modules.conf"
source "${BASE_DIR}/lib/report.sh"
source "${BASE_DIR}/lib/backup.sh"
source "${BASE_DIR}/lib/detect.sh"
detect_load

AUTO="${1:-}"
report_start "optimize"

[[ "${optimize_sysctl:-1}"            -eq 1 ]] && source "${SCRIPT_DIR}/sysctl.sh"   && optimize_sysctl "$AUTO"
[[ "${optimize_nginx:-1}"             -eq 1 ]] && source "${SCRIPT_DIR}/nginx.sh"    && optimize_nginx "$AUTO"
[[ "${optimize_php_fpm:-1}"           -eq 1 ]] && source "${SCRIPT_DIR}/php_fpm.sh"  && optimize_php_fpm "$AUTO"
[[ "${optimize_mysql:-1}"             -eq 1 ]] && source "${SCRIPT_DIR}/mysql.sh"    && optimize_mysql "$AUTO"

report_finish
