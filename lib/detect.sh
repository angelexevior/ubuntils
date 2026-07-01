#!/usr/bin/env bash
# lib/detect.sh — autodetect installed stack, writes /tmp/ubuntils-detect.cache

[[ -n "${_UBUNTILS_DETECT_LOADED:-}" ]] && return 0
_UBUNTILS_DETECT_LOADED=1

DETECT_CACHE="${DETECT_CACHE:-/tmp/ubuntils-detect.cache}"
DETECT_CACHE_TTL="${DETECT_CACHE_TTL:-3600}"

_detect_cache_fresh() {
    [[ -f "$DETECT_CACHE" ]] || return 1
    # Invalidate if detect.sh itself is newer than the cache (e.g. after git pull)
    local script; script="$(realpath "${BASH_SOURCE[0]}")"
    [[ "$script" -nt "$DETECT_CACHE" ]] && return 1
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
    [[ -f /etc/os-release ]] && ubuntu_version=$(. /etc/os-release 2>/dev/null; echo "${VERSION_ID:-}")
    out+="UBUNTU_VERSION=${ubuntu_version}\n"

    # PHP — via update-alternatives + binary scan
    local all_phps=()
    while IFS= read -r line; do
        local v; v=$(echo "$line" | grep -oP 'php\K[0-9]+\.[0-9]+' 2>/dev/null | head -1 || true)
        [[ -n "$v" ]] && all_phps+=("$v")
    done < <(update-alternatives --list php 2>/dev/null || true)

    for bin in /usr/bin/php[0-9].[0-9] /usr/bin/php[0-9][0-9].[0-9]; do
        [[ -x "$bin" ]] || continue
        local v; v=$(basename "$bin" | grep -oP '[0-9]+\.[0-9]+' || true)
        [[ -n "$v" ]] && all_phps+=("$v")
    done

    local -A _seen_php=()
    local unique_phps=()
    for v in "${all_phps[@]+"${all_phps[@]}"}"; do
        [[ -z "${_seen_php[$v]:-}" ]] && { _seen_php[$v]=1; unique_phps+=("$v"); }
    done

    local php_versions=""
    if [[ ${#unique_phps[@]} -gt 0 ]]; then
        php_versions=$(IFS=,; echo "${unique_phps[*]}")
    fi

    local php_default=""
    command -v php &>/dev/null && php_default=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || true)

    local php_mode="unknown"
    if systemctl list-units --type=service --state=loaded 2>/dev/null | grep -q 'php.*-fpm'; then
        php_mode="fpm"
    elif apache2ctl -M 2>/dev/null | grep -q 'php'; then
        php_mode="mod_php"
    fi

    local php_modules=""
    for v in "${unique_phps[@]+"${unique_phps[@]}"}"; do
        local mods=""
        command -v "php${v}" &>/dev/null && mods=$(php${v} -m 2>/dev/null | tr '\n' ',' | sed 's/,$//' || true)
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
        if echo "$db_ver_str" | grep -qi mariadb 2>/dev/null; then
            db_type="mariadb"
        else
            db_type="mysql"
        fi
        db_version=$(echo "$db_ver_str" | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
        db_socket=$(mysql_config --socket 2>/dev/null || true)
        [[ -z "$db_socket" ]] && db_socket=$(mysqladmin variables 2>/dev/null | awk '/\bsocket\b/{print $4}' | head -1 || true)
    fi
    out+="DB_TYPE=${db_type}\n"
    out+="DB_VERSION=${db_version}\n"
    out+="DB_SOCKET=${db_socket}\n"
    out+="DB_PORT=${db_port}\n"

    # Web server — nginx
    local nginx_installed=0 nginx_version="" apache_installed=0 apache_version=""
    local vhosts="" doc_roots=""
    if command -v nginx &>/dev/null; then
        nginx_installed=1
        nginx_version=$(nginx -v 2>&1 | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
        # Collect all nginx config files from every likely location
        local nginx_conf_files=()
        while IFS= read -r f; do
            nginx_conf_files+=("$f")
        done < <(find /etc/nginx -type f -name '*.conf' 2>/dev/null;
                 find /etc/nginx/sites-enabled -maxdepth 1 \( -type f -o -type l \) 2>/dev/null;
                 find /etc/nginx/conf.d -maxdepth 1 \( -type f -o -type l \) 2>/dev/null)
        # Deduplicate
        local -A _seen_f=()
        for f in "${nginx_conf_files[@]+"${nginx_conf_files[@]}"}"; do
            [[ -n "${_seen_f[$f]:-}" ]] && continue
            _seen_f[$f]=1
            # Each server_name line may have multiple names; take first non-underscore one
            local sn; sn=$(grep -h 'server_name' "$f" 2>/dev/null \
                | grep -v '^\s*#' \
                | grep -oP 'server_name\s+\K[^;]+' \
                | tr ' ' '\n' | grep -v '^_$' | grep -v '^$' | head -1 || true)
            local dr; dr=$(grep -h '^\s*root\s' "$f" 2>/dev/null \
                | grep -v '^\s*#' \
                | grep -oP 'root\s+\K[^;]+' | head -1 | xargs 2>/dev/null || true)
            [[ -n "$sn" ]] && { vhosts+="${sn},"; doc_roots+="${dr},"; }
        done
    fi

    # Web server — apache
    local _a=""
    command -v apache2 &>/dev/null && _a="apache2"
    { [[ -z "$_a" ]] && command -v httpd &>/dev/null; } && _a="httpd"
    if [[ -n "$_a" ]]; then
        apache_installed=1
        apache_version=$("$_a" -v 2>/dev/null | grep -oP 'Apache/\K[0-9.]+' | head -1 || true)
        if command -v apache2ctl &>/dev/null; then
            local av; av=$(apache2ctl -S 2>/dev/null | grep 'namevhost' | awk '{print $4}' | tr '\n' ',' || true)
            vhosts+="${av}"
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
        if [[ -d "$p" ]]; then pma_installed=1; pma_path="$p"; break; fi
    done
    out+="PMA_INSTALLED=${pma_installed}\n"
    out+="PMA_PATH=${pma_path}\n"

    # Redis
    local redis_installed=0 redis_version=""
    if command -v redis-server &>/dev/null; then
        redis_installed=1
        redis_version=$(redis-server --version 2>/dev/null | grep -oP 'v=\K[0-9.]+' | head -1 || true)
    fi
    out+="REDIS_INSTALLED=${redis_installed}\n"
    out+="REDIS_VERSION=${redis_version}\n"

    # Node
    local node_installed=0 node_version=""
    if command -v node &>/dev/null; then
        node_installed=1
        node_version=$(node --version 2>/dev/null | tr -d 'v' || true)
    fi
    out+="NODE_INSTALLED=${node_installed}\n"
    out+="NODE_VERSION=${node_version}\n"

    # Composer
    local composer_installed=0 composer_version=""
    if command -v composer &>/dev/null; then
        composer_installed=1
        composer_version=$(composer --version 2>/dev/null | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
    fi
    out+="COMPOSER_INSTALLED=${composer_installed}\n"
    out+="COMPOSER_VERSION=${composer_version}\n"

    # certbot
    local certbot_installed=0 certbot_version=""
    if command -v certbot &>/dev/null; then
        certbot_installed=1
        certbot_version=$(certbot --version 2>/dev/null | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
    fi
    out+="CERTBOT_INSTALLED=${certbot_installed}\n"
    out+="CERTBOT_VERSION=${certbot_version}\n"

    printf '%b' "$out" > "$DETECT_CACHE"
}

detect_load() {
    detect_run "${1:-}" || true
    [[ -f "$DETECT_CACHE" ]] && source "$DETECT_CACHE" || true
}
