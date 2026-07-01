#!/usr/bin/env bash
# modules/maintenance/run.sh — runs all enabled maintenance checks

set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
BASE_DIR="${SCRIPT_DIR}/../.."

source "${BASE_DIR}/config/ubuntils.conf"
source "${BASE_DIR}/config/modules.conf"
source "${BASE_DIR}/lib/report.sh"

AUTO="${1:-}"
report_start "maintenance"

[[ "${maintenance_disk_space:-1}"      -eq 1 ]] && source "${SCRIPT_DIR}/disk_space.sh"      && check_disk_space
[[ "${maintenance_inode_usage:-1}"     -eq 1 ]] && source "${SCRIPT_DIR}/inode_usage.sh"     && check_inode_usage
[[ "${maintenance_server_load:-1}"     -eq 1 ]] && source "${SCRIPT_DIR}/server_load.sh"     && check_server_load
[[ "${maintenance_apt_updates:-1}"     -eq 1 ]] && source "${SCRIPT_DIR}/apt_updates.sh"     && check_apt_updates
[[ "${maintenance_failed_units:-1}"    -eq 1 ]] && source "${SCRIPT_DIR}/failed_units.sh"    && check_failed_units
[[ "${maintenance_zombie_processes:-1}" -eq 1 ]] && source "${SCRIPT_DIR}/zombie_processes.sh" && check_zombie_processes
[[ "${maintenance_swap_oom:-1}"        -eq 1 ]] && source "${SCRIPT_DIR}/swap_oom.sh"        && check_swap_oom
[[ "${maintenance_log_rotation:-1}"    -eq 1 ]] && source "${SCRIPT_DIR}/log_rotation.sh"    && check_log_rotation
[[ "${maintenance_cron_scripts:-1}"    -eq 1 ]] && source "${SCRIPT_DIR}/cron_scripts.sh"    && check_cron_scripts
[[ "${maintenance_backup_verify:-1}"   -eq 1 ]] && source "${SCRIPT_DIR}/backup_verify.sh"   && check_backup_verify

report_finish
