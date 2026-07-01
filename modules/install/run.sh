#!/usr/bin/env bash
# modules/install/run.sh — interactive whiptail install menu

set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
BASE_DIR="${SCRIPT_DIR}/../.."

source "${BASE_DIR}/config/ubuntils.conf"
source "${BASE_DIR}/config/modules.conf"
source "${BASE_DIR}/lib/report.sh"
source "${BASE_DIR}/lib/tui.sh"
source "${BASE_DIR}/lib/detect.sh"
detect_load

tui_init

# Build checklist items: tag description status
_items=()

# PHP
if [[ "${install_php:-1}" -eq 1 ]]; then
    if [[ -n "${PHP_VERSIONS:-}" ]]; then
        _items+=("php" "PHP (installed: ${PHP_VERSIONS})" "OFF")
    else
        _items+=("php" "PHP (not installed)" "ON")
    fi
fi

# MySQL
if [[ "${install_mysql:-1}" -eq 1 ]]; then
    if [[ -n "${DB_TYPE:-}" ]]; then
        _items+=("mysql" "MySQL/MariaDB (installed: ${DB_TYPE} ${DB_VERSION})" "OFF")
    else
        _items+=("mysql" "MySQL/MariaDB (not installed)" "ON")
    fi
fi

# nginx
if [[ "${install_nginx:-1}" -eq 1 ]]; then
    if [[ "${NGINX_INSTALLED:-0}" -eq 1 ]]; then
        _items+=("nginx" "nginx (installed: ${NGINX_VERSION})" "OFF")
    else
        _items+=("nginx" "nginx (not installed)" "ON")
    fi
fi

# Apache
if [[ "${install_apache:-1}" -eq 1 ]]; then
    if [[ "${APACHE_INSTALLED:-0}" -eq 1 ]]; then
        _items+=("apache" "Apache (installed: ${APACHE_VERSION})" "OFF")
    else
        _items+=("apache" "Apache (not installed)" "ON")
    fi
fi

# phpMyAdmin
if [[ "${install_phpmyadmin:-1}" -eq 1 ]]; then
    if [[ "${PMA_INSTALLED:-0}" -eq 1 ]]; then
        _items+=("phpmyadmin" "phpMyAdmin (installed at ${PMA_PATH})" "OFF")
    else
        _items+=("phpmyadmin" "phpMyAdmin (not installed)" "ON")
    fi
fi

# fail2ban
if [[ "${install_fail2ban:-1}" -eq 1 ]]; then
    if [[ "${FAIL2BAN_INSTALLED:-0}" -eq 1 ]]; then
        _items+=("fail2ban" "fail2ban (installed)" "OFF")
    else
        _items+=("fail2ban" "fail2ban (not installed)" "ON")
    fi
fi

# certbot
if [[ "${install_certbot:-1}" -eq 1 ]]; then
    if [[ "${CERTBOT_INSTALLED:-0}" -eq 1 ]]; then
        _items+=("certbot" "certbot (installed: ${CERTBOT_VERSION})" "OFF")
    else
        _items+=("certbot" "certbot (not installed)" "ON")
    fi
fi

selected=$(tui_checklist "Install Components" "Select components to install (already-installed are pre-unchecked):" "${_items[@]}") || exit 0

[[ -z "$selected" ]] && { tui_msgbox "Install" "Nothing selected."; exit 0; }

# Install each selected
for item in $selected; do
    item="${item//\"/}"
    case "$item" in
        php)
            _install_php
            ;;
        mysql)
            apt-get install -y mysql-server 2>&1 | tail -5
            report_pass "MySQL installed"
            ;;
        nginx)
            apt-get install -y nginx 2>&1 | tail -5
            systemctl enable --now nginx
            report_pass "nginx installed and enabled"
            ;;
        apache)
            apt-get install -y apache2 2>&1 | tail -5
            systemctl enable --now apache2
            report_pass "Apache installed and enabled"
            ;;
        phpmyadmin)
            apt-get install -y phpmyadmin 2>&1 | tail -5
            report_pass "phpMyAdmin installed"
            ;;
        fail2ban)
            apt-get install -y fail2ban 2>&1 | tail -5
            systemctl enable --now fail2ban
            report_pass "fail2ban installed and enabled"
            ;;
        certbot)
            apt-get install -y certbot python3-certbot-nginx 2>&1 | tail -5
            report_pass "certbot installed"
            ;;
    esac
done

# Offer to run optimize on newly installed components
tui_yesno "Optimize" "Run optimize module with sane defaults on newly installed components?" && \
    bash "${BASE_DIR}/modules/optimize/run.sh" "--auto" || true

tui_msgbox "Install Complete" "Installation finished. Run Security check to verify configuration."

_install_php() {
    local php_ver
    php_ver=$(tui_inputbox "PHP Version" "Enter PHP version to install (e.g. 8.3):" "8.3")
    [[ -z "$php_ver" ]] && return
    apt-get install -y "php${php_ver}" "php${php_ver}-fpm" "php${php_ver}-cli" \
        "php${php_ver}-mysql" "php${php_ver}-curl" "php${php_ver}-mbstring" \
        "php${php_ver}-xml" "php${php_ver}-zip" 2>&1 | tail -5
    systemctl enable --now "php${php_ver}-fpm"
    report_pass "PHP ${php_ver} + FPM installed"
}
