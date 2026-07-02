#!/usr/bin/env bash
# install.sh — ubuntils setup wizard

set -euo pipefail

# ── colours ──────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    R="\033[0;31m" G="\033[0;32m" Y="\033[0;33m"
    B="\033[0;34m" C="\033[0;36m" W="\033[1;37m" N="\033[0m"
else
    R="" G="" Y="" B="" C="" W="" N=""
fi

# ── helpers ───────────────────────────────────────────────────────────────────
die()  { echo -e "${R}ERROR:${N} $*" >&2; exit 1; }
ok()   { echo -e "${G}  ✔${N}  $*"; }
warn() { echo -e "${Y}  !${N}  $*"; }
info() { echo -e "${C}  →${N}  $*"; }
hdr()  { echo -e "\n${W}── $* ──${N}"; }
ask()  {
    # ask <varname> <prompt> [default]
    # If default is provided (even ""), blank input accepts the default.
    # If no default provided, a value is required.
    local __var="$1" __prompt="$2"
    local __has_default=0 __default=""
    if [[ $# -ge 3 ]]; then
        __has_default=1
        __default="${3}"
    fi
    local __hint=""
    [[ -n "$__default" ]] && __hint=" [${__default}]"
    while true; do
        printf "${B}  ?${N}  %s%s: " "$__prompt" "$__hint"
        read -r __input
        __input="${__input:-$__default}"
        if [[ -n "$__input" ]]; then
            printf -v "$__var" '%s' "$__input"
            return
        fi
        if [[ "$__has_default" -eq 1 ]]; then
            printf -v "$__var" '%s' ""
            return
        fi
        warn "Please enter a value."
    done
}
ask_opt() {
    # ask_opt <varname> <prompt> <default> [y/n]
    local __var="$1" __prompt="$2" __default="${3:-y}"
    local __hint; [[ "$__default" == "y" ]] && __hint="Y/n" || __hint="y/N"
    printf "${B}  ?${N}  %s [%s]: " "$__prompt" "$__hint"
    read -r __input
    __input="${__input:-$__default}"
    if [[ "${__input,,}" =~ ^y ]]; then
        printf -v "$__var" '%s' "y"
    else
        printf -v "$__var" '%s' "n"
    fi
}

# ── root check ────────────────────────────────────────────────────────────────
[[ "$EUID" -eq 0 ]] || die "Run this as root (sudo ./install.sh)"

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─────────────────────────────────────────────────────────────────────────────
echo -e "${W}"
cat <<'BANNER'
 _   _                  _   _ _
| | | |                | | (_) |
| | | |__  _   _ _ __ | |_ _| |___
| | | '_ \| | | | '_ \| __| | / __|
| |_| | |_) | |_| | | | |_| | \__ \
 \___/|_.__/ \__,_|_| |_|\__|_|_|___/
BANNER
echo -e "${N}"
echo -e "${C}Ubuntu server toolkit — setup wizard${N}"
echo -e "This script will check dependencies, configure ubuntils,"
echo -e "and optionally set up a monitor cron job.\n"

# ── 1. Ubuntu check ───────────────────────────────────────────────────────────
hdr "System check"

if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    if [[ "${ID:-}" == "ubuntu" ]]; then
        ok "Ubuntu ${VERSION_ID:-} detected"
    else
        warn "This toolkit targets Ubuntu. Detected: ${PRETTY_NAME:-unknown}."
        ask_opt CONTINUE_ANYWAY "Continue anyway?" "n"
        [[ "$CONTINUE_ANYWAY" == "y" ]] || die "Aborted."
    fi
else
    warn "/etc/os-release not found — cannot confirm OS."
    ask_opt CONTINUE_ANYWAY "Continue anyway?" "n"
    [[ "$CONTINUE_ANYWAY" == "y" ]] || die "Aborted."
fi

# ── 2. bash version ───────────────────────────────────────────────────────────
bash_major="${BASH_VERSINFO[0]}"
if (( bash_major < 4 )); then
    die "bash 4.0+ required (found ${BASH_VERSION})."
fi
ok "bash ${BASH_VERSION}"

# ── 3. whiptail / dialog ─────────────────────────────────────────────────────
hdr "TUI dependency"

TUI_CMD=""
if command -v whiptail &>/dev/null; then
    ok "whiptail found ($(whiptail --version 2>/dev/null | head -1))"
    TUI_CMD="whiptail"
elif command -v dialog &>/dev/null; then
    ok "dialog found (used as whiptail fallback)"
    TUI_CMD="dialog"
else
    warn "Neither whiptail nor dialog is installed."
    ask_opt INSTALL_WHIPTAIL "Install whiptail now?" "y"
    if [[ "$INSTALL_WHIPTAIL" == "y" ]]; then
        echo ""
        info "Running: apt-get install -y whiptail"
        apt-get update -qq || die "apt-get update failed."
        apt-get install -y whiptail || die "Failed to install whiptail."
        ok "whiptail installed."
        TUI_CMD="whiptail"
    else
        die "whiptail or dialog is required. Install one and re-run."
    fi
fi

# ── 4. optional tools check ───────────────────────────────────────────────────
hdr "Optional tools"

for cmd in curl openssl ss systemctl logrotate; do
    if command -v "$cmd" &>/dev/null; then
        ok "$cmd found"
    else
        warn "$cmd not found — some checks will be skipped at runtime"
    fi
done

# ── 5. directory structure ────────────────────────────────────────────────────
hdr "Directory setup"

for d in "${BASE_DIR}/logs/runs" "${BASE_DIR}/logs/state" /var/backups/ubuntils; do
    mkdir -p "$d"
    ok "Created: $d"
done
chmod 700 /var/backups/ubuntils

# ── 6. config: thresholds ─────────────────────────────────────────────────────
hdr "Thresholds"

echo -e "Set alert thresholds (press Enter to accept defaults).\n"
ask LOAD_WARN   "Load avg WARN threshold"  "4"
ask LOAD_CRIT   "Load avg CRIT threshold"  "8"
ask DISK_WARN   "Disk usage WARN %"        "80"
ask DISK_CRIT   "Disk usage CRIT %"        "90"
ask RATE_4XX    "4xx rate WARN (per ~min)" "50"
ask SLOW_Q      "Slow queries WARN (per ~min)" "10"
ask FAILED_SSH  "Failed SSH logins WARN (per min)" "5"
ask LOG_DAYS    "Log rotation stale threshold (days)" "30"
ask MIN_BACKUP  "Minimum backup file size (KB)" "1"

# ── 7. config: notifications ──────────────────────────────────────────────────
hdr "Notifications"

NOTIFY_EMAIL=0; NOTIFY_TELEGRAM=0; NOTIFY_SLACK=0
EMAIL_TO=""; EMAIL_FROM="ubuntils@localhost"
TELEGRAM_BOT_TOKEN=""; TELEGRAM_CHAT_ID=""
SLACK_WEBHOOK_URL=""

ask_opt WANT_EMAIL    "Enable email notifications?" "n"
if [[ "$WANT_EMAIL" == "y" ]]; then
    if command -v sendmail &>/dev/null || command -v msmtp &>/dev/null; then
        ok "sendmail/msmtp found"
    else
        warn "Neither sendmail nor msmtp found — email will fail at runtime unless you install one."
    fi
    ask EMAIL_TO   "Recipient email address" ""
    ask EMAIL_FROM "Sender address"          "ubuntils@$(hostname -f 2>/dev/null || echo localhost)"
    NOTIFY_EMAIL=1
fi

ask_opt WANT_TELEGRAM "Enable Telegram notifications?" "n"
if [[ "$WANT_TELEGRAM" == "y" ]]; then
    ask TELEGRAM_BOT_TOKEN "Telegram bot token" ""
    ask TELEGRAM_CHAT_ID   "Telegram chat ID"   ""
    NOTIFY_TELEGRAM=1
fi

ask_opt WANT_SLACK    "Enable Slack notifications?" "n"
if [[ "$WANT_SLACK" == "y" ]]; then
    ask SLACK_WEBHOOK_URL "Slack webhook URL" ""
    NOTIFY_SLACK=1
fi

# ── 8. config: security baselines ────────────────────────────────────────────
hdr "Security baselines"

echo -e "These baselines are used by the security module to detect drift.\n"

info "Current sudo-capable users:"
getent group sudo 2>/dev/null | awk -F: '{print "    ",$4}' || true
getent group admin 2>/dev/null | awk -F: '{print "    ",$4}' || true
echo ""
ask SUDO_BASELINE "Sudo baseline (space-separated usernames, or Enter to skip)" ""

info "Commonly expected open ports: 22 80 443"
ask PORTS_BASELINE "Port baseline (space-separated)" "22 80 443"

# ── 9. config: report format ──────────────────────────────────────────────────
hdr "Report format"

echo -e "Formats: ${W}text${N}, ${W}html${N}, ${W}json${N} (comma-separated for multiple)\n"
ask REPORT_FORMAT "Report format" "text"

# ── 10. write ubuntils.conf ───────────────────────────────────────────────────
hdr "Writing config/ubuntils.conf"

CONF_FILE="${BASE_DIR}/config/ubuntils.conf"
# Back up existing
if [[ -f "$CONF_FILE" ]]; then
    cp "$CONF_FILE" "${CONF_FILE}.bak.$(date +%Y%m%d-%H%M%S)"
    info "Existing config backed up."
fi

cat > "$CONF_FILE" <<CONF
# ubuntils global configuration — generated by install.sh on $(date)

# Paths
LOG_DIR="\$(dirname "\$(realpath "\${BASH_SOURCE[0]:-\$0}")")/../logs"
BACKUP_DIR="/var/backups/ubuntils"
DETECT_CACHE="/tmp/ubuntils-detect.cache"
DETECT_CACHE_TTL=3600

# Report format: text, html, json (comma-separated)
REPORT_FORMAT="${REPORT_FORMAT}"

# Notification channels
NOTIFY_EMAIL=${NOTIFY_EMAIL}
NOTIFY_TELEGRAM=${NOTIFY_TELEGRAM}
NOTIFY_SLACK=${NOTIFY_SLACK}

EMAIL_TO="${EMAIL_TO}"
EMAIL_FROM="${EMAIL_FROM}"

TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID}"

SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL}"

# Monitor thresholds
LOAD_AVG_WARN=${LOAD_WARN}
LOAD_AVG_CRIT=${LOAD_CRIT}
DISK_WARN=${DISK_WARN}
DISK_CRIT=${DISK_CRIT}
RATE_4XX_WARN=${RATE_4XX}
SLOW_QUERIES_WARN=${SLOW_Q}
FAILED_SSH_WARN=${FAILED_SSH}

# Maintenance thresholds
DISK_INODE_WARN=80
DISK_INODE_CRIT=90
APT_PENDING_WARN=10
LOG_ROTATE_DAYS=${LOG_DAYS}
BACKUP_MIN_SIZE_KB=${MIN_BACKUP}

# CVE lookup (requires network, off by default)
CVE_LOOKUP=0
CONF

ok "config/ubuntils.conf written."

# ── 11. write modules.conf (preserve any existing customisation) ──────────────
hdr "Writing config/modules.conf"

MCONF_FILE="${BASE_DIR}/config/modules.conf"
if [[ -f "$MCONF_FILE" ]]; then
    # Update only the baseline lines, leave everything else intact
    # sudo baseline
    sed -i "s|^SUDO_BASELINE_USERS=.*|SUDO_BASELINE_USERS=\"${SUDO_BASELINE}\"|" "$MCONF_FILE"
    sed -i "s|^PORTS_BASELINE=.*|PORTS_BASELINE=\"${PORTS_BASELINE}\"|" "$MCONF_FILE"
    ok "config/modules.conf baselines updated (all other toggles preserved)."
else
    # Write fresh (should already exist from git, but handle edge case)
    warn "modules.conf missing — writing defaults."
    cat > "$MCONF_FILE" <<MCONF
# Per-module and per-check enable/disable (1=on, 0=off)

maintenance_disk_space=1
maintenance_inode_usage=1
maintenance_server_load=1
maintenance_apt_updates=1
maintenance_failed_units=1
maintenance_zombie_processes=1
maintenance_swap_oom=1
maintenance_log_rotation=1
maintenance_cron_scripts=1
maintenance_backup_verify=1

security_ssh_config=1
security_sudo_users=1
security_open_ports=1
security_fail2ban=1
security_ssl_expiry=1
security_php_versions=1
security_php_config=1
security_php_phpinfo=1
security_mysql_remote_root=1
security_mysql_anonymous=1
security_mysql_grants=1
security_webserver_tokens=1
security_webserver_tls=1
security_cve_lookup=0

optimize_sysctl=1
optimize_swappiness=1
optimize_unattended_upgrades=1
optimize_nginx=1
optimize_php_fpm=1
optimize_mysql=1

install_php=1
install_mysql=1
install_nginx=1
install_apache=1
install_phpmyadmin=1
install_fail2ban=1
install_certbot=1

monitor_load=1
monitor_disk=1
monitor_4xx_rate=1
monitor_slow_queries=1
monitor_failed_ssh=1

SUDO_BASELINE_USERS="${SUDO_BASELINE}"
PORTS_BASELINE="${PORTS_BASELINE}"
MCONF
    ok "config/modules.conf written."
fi

# ── 12. permissions ───────────────────────────────────────────────────────────
hdr "Setting permissions"

chmod +x "${BASE_DIR}/ubuntils.sh"
find "${BASE_DIR}/lib" "${BASE_DIR}/modules" -name '*.sh' -exec chmod +x {} +
ok "All scripts marked executable."

# ── 13. smoke test ────────────────────────────────────────────────────────────
hdr "Smoke test"

info "Running stack detection..."
if bash "${BASE_DIR}/lib/detect.sh" 2>/dev/null && bash -c "source '${BASE_DIR}/lib/detect.sh'; detect_run" 2>/dev/null; then
    ok "Stack detection passed."
else
    warn "Stack detection had errors (may be fine — some services simply aren't installed)."
fi

info "Syntax-checking all scripts..."
ERRORS=0
while IFS= read -r f; do
    if ! bash -n "$f" 2>/tmp/ubuntils-syntax-err; then
        warn "Syntax error in: $f"
        cat /tmp/ubuntils-syntax-err
        (( ERRORS++ ))
    fi
done < <(find "$BASE_DIR" -name '*.sh' -not -path '*/\.*')

if (( ERRORS == 0 )); then
    ok "All scripts pass syntax check."
else
    die "${ERRORS} script(s) have syntax errors — fix before running."
fi

# ── 14. monitor cron ──────────────────────────────────────────────────────────
hdr "Monitor cron"

CRON_FILE="/etc/cron.d/ubuntils-monitor"
CRON_LINE="*/5 * * * * root bash ${BASE_DIR}/modules/monitor/run.sh >> ${BASE_DIR}/logs/runs/monitor-cron.out 2>&1"

if [[ -f "$CRON_FILE" ]]; then
    ok "Monitor cron already installed at ${CRON_FILE}."
    ask_opt UPDATE_CRON "Update it to current path?" "y"
    if [[ "$UPDATE_CRON" == "y" ]]; then
        echo "$CRON_LINE" > "$CRON_FILE"
        chmod 644 "$CRON_FILE"
        ok "Cron updated."
    fi
else
    ask_opt INSTALL_CRON "Install monitor cron job (runs every 5 minutes)?" "y"
    if [[ "$INSTALL_CRON" == "y" ]]; then
        echo "$CRON_LINE" > "$CRON_FILE"
        chmod 644 "$CRON_FILE"
        ok "Cron installed: ${CRON_FILE}"
    else
        info "Skipped. You can add it later from the TUI (Monitor → Install cron)."
    fi
fi

# ── 15. symlink (optional) ────────────────────────────────────────────────────
hdr "System-wide command"

ask_opt INSTALL_LINK "Create symlink so 'ubuntils' works from anywhere?" "y"
if [[ "$INSTALL_LINK" == "y" ]]; then
    ln -sf "${BASE_DIR}/ubuntils.sh" /usr/local/bin/ubuntils
    ok "Symlink created: /usr/local/bin/ubuntils"
fi

# ── done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${G}╔══════════════════════════════════════╗${N}"
echo -e "${G}║   ubuntils is ready to use!          ║${N}"
echo -e "${G}╚══════════════════════════════════════╝${N}"
echo ""

if [[ "$INSTALL_LINK" == "y" ]]; then
    echo -e "  Run the TUI:     ${W}sudo ubuntils${N}"
    echo -e "  Quick check:     ${W}sudo ubuntils maintenance${N}"
    echo -e "  Security scan:   ${W}sudo ubuntils security${N}"
else
    echo -e "  Run the TUI:     ${W}sudo ${BASE_DIR}/ubuntils.sh${N}"
    echo -e "  Quick check:     ${W}sudo ${BASE_DIR}/ubuntils.sh maintenance${N}"
    echo -e "  Security scan:   ${W}sudo ${BASE_DIR}/ubuntils.sh security${N}"
fi
echo ""
