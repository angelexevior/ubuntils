#!/usr/bin/env bash
# modules/security/mysql_security.sh

_MDIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
source "${_MDIR}/../../lib/report.sh"

_mysql_query() {
    local q="$1"
    mysql --defaults-file=/etc/mysql/debian.cnf -N -e "$q" 2>/dev/null \
        || mysql -u root -N -e "$q" 2>/dev/null \
        || true
}

check_mysql_security() {
    report_section "MySQL/MariaDB Security"

    if [[ -z "${DB_TYPE:-}" ]]; then
        report_info "MySQL/MariaDB not detected"
        return
    fi

    report_info "Detected: ${DB_TYPE} ${DB_VERSION:-}"

    # Remote root access
    [[ "${security_mysql_remote_root:-1}" -eq 1 ]] && {
        local remote_root; remote_root=$(_mysql_query "SELECT user,host FROM mysql.user WHERE user='root' AND host NOT IN ('localhost','127.0.0.1','::1');")
        if [[ -n "$remote_root" ]]; then
            report_fail "Root user has remote access: ${remote_root}"
        else
            report_pass "Root user has no remote access"
        fi
    }

    # Anonymous users
    [[ "${security_mysql_anonymous:-1}" -eq 1 ]] && {
        local anon; anon=$(_mysql_query "SELECT user,host FROM mysql.user WHERE user='';")
        if [[ -n "$anon" ]]; then
            report_fail "Anonymous MySQL users exist — run mysql_secure_installation"
        else
            report_pass "No anonymous MySQL users"
        fi
    }

    # Overly broad grants
    [[ "${security_mysql_grants:-1}" -eq 1 ]] && {
        local broad; broad=$(_mysql_query "SELECT user,host,Select_priv,Insert_priv,Update_priv,Delete_priv FROM mysql.user WHERE host='%' AND user!='root';")
        if [[ -n "$broad" ]]; then
            report_warn "Users with wildcard host (%): ${broad}"
        else
            report_pass "No non-root users with wildcard host"
        fi

        # Check for ALL PRIVILEGES on *.*
        local all_privs; all_privs=$(_mysql_query "SHOW GRANTS FOR CURRENT_USER" 2>/dev/null || true)
        # A broader check via information_schema
        local broad_grants; broad_grants=$(_mysql_query \
            "SELECT GRANTEE,PRIVILEGE_TYPE FROM information_schema.USER_PRIVILEGES WHERE GRANTEE NOT LIKE '%root%' AND IS_GRANTABLE='YES';" 2>/dev/null || true)
        if [[ -n "$broad_grants" ]]; then
            report_warn "Users with GRANT OPTION (can delegate privileges): check manually"
        fi
    }
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    SCRIPT_DIR="$(dirname "$(realpath "$0")")"
    source "${SCRIPT_DIR}/../../config/ubuntils.conf" 2>/dev/null || true
    source "${SCRIPT_DIR}/../../config/modules.conf" 2>/dev/null || true
    source "${SCRIPT_DIR}/../../lib/detect.sh"
    detect_load
    report_start "mysql_security"
    check_mysql_security
    report_finish
fi
