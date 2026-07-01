#!/usr/bin/env bash
# lib/detect.sh — autodetect installed stack, writes /tmp/ubuntils-detect.cache

set -euo pipefail

DETECT_CACHE="${DETECT_CACHE:-/tmp/ubuntils-detect.cache}"
DETECT_CACHE_TTL="${DETECT_CACHE_TTL:-3600}"

_detect_cache_fresh() {
    [[ -f "$DETECT_CACHE" ]] || return 1
    local age=$(( $(date +%s) - $(stat -c %Y "$DETECT_CACHE") ))
    (( age < DETECT_CACHE_TTL ))
}

detect_run() {
    local force="${1:-}"
    if [[ "$force" != "--force" ]] && _detect_cache_fresh; then
        return 0
    fi

    local out=""

    # Ubuntu version
    local ubuntu_version=""
    if [[ -f /etc/os-release ]]; then
        ubuntu_version=$(. /etc/os-release; echo "${VERSION_ID:-}")
    fi
    out+="UBUNTU_VERSION=${ubuntu_version}\n"

    # PHP detection
    local php_versions="" php_default="" php_mode=""
    local all_phps=()
    # via update-alternatives
    while IFS= read -r line; do
        local v; v=$(echo "$line" | grep -oP 'php\K[0-9]+\.[0-9]+' | head -1)
        [[ -n "$v" ]] && all_phps+=("$v")
    done < <(update-alternatives --list php 2>/dev/null || true)
    # also scan binaries
    for bin in /usr/bin/php[0-9].[0-9] /usr/bin/php[0-9][0-9].[0-9]; do
        [[ -x "$bin" ]] || continue
        local v; v=$(basename "$bin" | grep -oP '[0-9]+\.[0-9]+')
        [[ -n "$v" ]] && all_phps+=("$v")
    done
    # deduplicate
    local -A seen_php=()
    local unique_phps=()
    for v in "${all_phps[@]}"; do
        [[ -z "${seen_php[$v]:-}" ]] && { seen_php[$v]=1; unique_phps+=("$v"); }
    done
    php_versions=$(IFS=,; echo "${unique_phps[*]:-}")

    # default php
    if command -v php &>/dev/null; then
        php_default=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || true)
    fi

    # FPM vs mod_php
    if systemctl list-units --type=service --state=loaded 2>/dev/null | grep -q 'php.*-fpm'; then
        php_mode="fpm"
    elif apache2ctl -M 2>/dev/null | grep -q php; then
        php_mode="mod_php"
    else
        php_mode="unknown"
    fi

    # loaded modules per version
    local php_modules=""
    for v in "${unique_phps[@]}"; do
        local mods=""
        if command -v "php${v}" &>/dev/null; then
            mods=$(php${v} -m 2>/dev/null | tr '\n' ',' | sed 's/,$//')
        fi
        php_modules+="${v}:${mods};"
    done

    out+="PHP_VERSIONS=${php_versions}\n"
    out+="PHP_DEFAULT=${php_default}\n"
    out+="PHP_MODE=${php_mode}\n"
    out+="PHP_MODULES=${php_modules}\n"

    # MySQL / MariaDB
    local db_type="" db_version="" db_socket="" db_port="3306"
    if command -v mysql &>/dev/null; then
        local db_ver_str; db_ver_str=$(mysql --version 2>/dev/null || true)
        if echo "$db_ver_str" | grep -qi mariadb; then
            db_type="mariadb"
        else
            db_type="mysql"
        fi
        db_version=$(echo "$db_ver_str" | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        # find socket
        db_socket=$(mysql_config --socket 2>/dev/null || true)
        [[ -z "$db_socket" ]] && db_socket=$(mysqladmin variables 2>/dev/null | awk '/\bsocket\b/{print $4}' | head -1 || true)
    fi
    out+="DB_TYPE=${db_type}\n"
    out+="DB_VERSION=${db_version}\n"
    out+="DB_SOCKET=${db_socket}\n"
    out+="DB_PORT=${db_port}\n"

    # Web server
    local nginx_installed=0 nginx_version="" apache_installed=0 apache_version=""
    local vhosts="" doc_roots=""
    if command -v nginx &>/dev/null; then
        nginx_installed=1
        nginx_version=$(nginx -v 2>&1 | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        # active vhosts: parse server_name directives from enabled configs
        local vhost_dirs=(/etc/nginx/sites-enabled /etc/nginx/conf.d)
        for d in "${vhost_dirs[@]}"; do
            [[ -d "$d" ]] || continue
            while IFS= read -r f; do
                local sn; sn=$(grep -h 'server_name' "$f" 2>/dev/null | grep -oP 'server_name\s+\K[^;]+' | head -1 | xargs || true)
                local dr; dr=$(grep -h 'root' "$f" 2>/dev/null | grep -oP 'root\s+\K[^;]+' | head -1 | xargs || true)
                [[ -n "$sn" ]] && { vhosts+="${sn},"; doc_roots+="${dr},"; }
            done < <(find "$d" -maxdepth 1 -type f -o -type l 2>/dev/null)
        done
    fi
    if command -v apache2 &>/dev/null || command -v httpd &>/dev/null; then
        apache_installed=1
        local _a; _a=$(command -v apache2 || command -v httpd)
        apache_version=$("$_a" -v 2>/dev/null | grep -oP 'Apache/\K[0-9.]+' | head -1)
        if command -v apache2ctl &>/dev/null; then
            local apache_vhosts; apache_vhosts=$(apache2ctl -S 2>/dev/null | grep 'namevhost' | awk '{print $4}' | tr '\n' ',' || true)
            vhosts+="${apache_vhosts}"
        fi
    fi
    out+="NGINX_INSTALLED=${nginx_installed}\n"
    out+="NGINX_VERSION=${nginx_version}\n"
    out+="APACHE_INSTALLED=${apache_installed}\n"
    out+="APACHE_VERSION=${apache_version}\n"
    out+="VHOSTS=${vhosts%,}\n"
    out+="DOC_ROOTS=${doc_roots%,}\n"

    # fail2ban
    local fail2ban_installed=0 fail2ban_jails=""
    if command -v fail2ban-client &>/dev/null; then
        fail2ban_installed=1
        fail2ban_jails=$(fail2ban-client status 2>/dev/null | grep 'Jail list' | sed 's/.*Jail list:\s*//' | tr -d ' ' || true)
    fi
    out+="FAIL2BAN_INSTALLED=${fail2ban_installed}\n"
    out+="FAIL2BAN_JAILS=${fail2ban_jails}\n"

    # phpMyAdmin
    local pma_installed=0 pma_path=""
    for p in /usr/share/phpmyadmin /var/www/phpmyadmin /var/www/html/phpmyadmin; do
        if [[ -d "$p" ]]; then
            pma_installed=1; pma_path="$p"; break
        fi
    done
    out+="PMA_INSTALLED=${pma_installed}\n"
    out+="PMA_PATH=${pma_path}\n"

    # Redis
    local redis_installed=0 redis_version=""
    if command -v redis-server &>/dev/null; then
        redis_installed=1
        redis_version=$(redis-server --version 2>/dev/null | grep -oP 'v=\K[0-9.]+' | head -1)
    fi
    out+="REDIS_INSTALLED=${redis_installed}\n"
    out+="REDIS_VERSION=${redis_version}\n"

    # Node
    local node_installed=0 node_version=""
    if command -v node &>/dev/null; then
        node_installed=1
        node_version=$(node --version 2>/dev/null | tr -d 'v')
    fi
    out+="NODE_INSTALLED=${node_installed}\n"
    out+="NODE_VERSION=${node_version}\n"

    # Composer
    local composer_installed=0 composer_version=""
    if command -v composer &>/dev/null; then
        composer_installed=1
        composer_version=$(composer --version 2>/dev/null | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    fi
    out+="COMPOSER_INSTALLED=${composer_installed}\n"
    out+="COMPOSER_VERSION=${composer_version}\n"

    # certbot
    local certbot_installed=0 certbot_version=""
    if command -v certbot &>/dev/null; then
        certbot_installed=1
        certbot_version=$(certbot --version 2>/dev/null | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    fi
    out+="CERTBOT_INSTALLED=${certbot_installed}\n"
    out+="CERTBOT_VERSION=${certbot_version}\n"

    # Write cache
    printf '%b' "$out" > "$DETECT_CACHE"
}

detect_load() {
    detect_run "${1:-}"
    # shellcheck source=/dev/null
    source "$DETECT_CACHE"
}
