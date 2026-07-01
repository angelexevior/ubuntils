#!/usr/bin/env bash
# modules/security/run.sh — runs all enabled security checks

set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
BASE_DIR="${SCRIPT_DIR}/../.."

source "${BASE_DIR}/config/ubuntils.conf"
source "${BASE_DIR}/config/modules.conf"
source "${BASE_DIR}/lib/report.sh"
source "${BASE_DIR}/lib/detect.sh"
detect_load

report_start "security"

[[ "${security_ssh_config:-1}"       -eq 1 ]] && source "${SCRIPT_DIR}/ssh_config.sh"        && check_ssh_config
[[ "${security_sudo_users:-1}"       -eq 1 ]] && source "${SCRIPT_DIR}/sudo_users.sh"         && check_sudo_users
[[ "${security_open_ports:-1}"       -eq 1 ]] && source "${SCRIPT_DIR}/open_ports.sh"         && check_open_ports
[[ "${security_fail2ban:-1}"         -eq 1 ]] && source "${SCRIPT_DIR}/fail2ban.sh"            && check_fail2ban
[[ "${security_ssl_expiry:-1}"       -eq 1 ]] && source "${SCRIPT_DIR}/ssl_expiry.sh"         && check_ssl_expiry

if [[ -n "${PHP_VERSIONS:-}" ]]; then
    source "${SCRIPT_DIR}/php_security.sh"
    check_php_versions
    check_php_config
    check_phpinfo_exposure
fi

if [[ -n "${DB_TYPE:-}" ]]; then
    source "${SCRIPT_DIR}/mysql_security.sh"
    check_mysql_security
fi

if [[ "${NGINX_INSTALLED:-0}" -eq 1 || "${APACHE_INSTALLED:-0}" -eq 1 ]]; then
    source "${SCRIPT_DIR}/webserver_security.sh"
    check_webserver_security
fi

report_finish
