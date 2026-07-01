#!/usr/bin/env bash
# ubuntils.sh — main entrypoint

set -uo pipefail

BASE_DIR="$(dirname "$(realpath "$0")")"

source "${BASE_DIR}/config/ubuntils.conf"
source "${BASE_DIR}/config/modules.conf"
source "${BASE_DIR}/lib/tui.sh"
source "${BASE_DIR}/lib/detect.sh"

tui_init

# Parse global flags
AUTO=""
FORCE_DETECT=""
for arg in "$@"; do
    case "$arg" in
        --auto)  AUTO="--auto" ;;
        --force) FORCE_DETECT="--force" ;;
    esac
done

# Run detect on startup (cached); non-fatal — some services simply aren't installed
detect_load "${FORCE_DETECT}" 2>/dev/null || true

_main_menu() {
    while true; do
        local choice
        choice=$(tui_menu "ubuntils" "Select a module:" \
            "maintenance" "System Maintenance Checks" \
            "security"    "Security Audit" \
            "optimize"    "Performance Optimization" \
            "install"     "Install Components" \
            "monitor"     "Monitor Status / Setup Cron" \
            "settings"    "Settings" \
            "exit"        "Exit") || break

        case "$choice" in
            maintenance) _run_maintenance ;;
            security)    _run_security ;;
            optimize)    _run_optimize ;;
            install)     _run_install ;;
            monitor)     _run_monitor ;;
            settings)    _run_settings ;;
            exit|"")     break ;;
        esac
    done
}

_run_maintenance() {
    bash "${BASE_DIR}/modules/maintenance/run.sh" "$AUTO" 2>&1 | \
        tee /tmp/ubuntils-maintenance-out.txt | \
        "$(_TUI_CMD_fallback)" --title "Maintenance" --scrolltext 30 80 || true
    tui_msgbox "Maintenance" "$(tail -5 /tmp/ubuntils-maintenance-out.txt)"
}

_run_security() {
    bash "${BASE_DIR}/modules/security/run.sh" 2>&1 | \
        tee /tmp/ubuntils-security-out.txt | \
        "$(_TUI_CMD_fallback)" --title "Security" --scrolltext 30 80 || true
    tui_msgbox "Security" "$(tail -5 /tmp/ubuntils-security-out.txt)"
}

_run_optimize() {
    local mode
    mode=$(tui_menu "Optimize" "Choose optimization mode:" \
        "interactive" "Show current → suggested → confirm each change" \
        "auto"        "Apply all suggestions automatically (--auto)") || return
    local opt_auto=""
    [[ "$mode" == "auto" ]] && opt_auto="--auto"
    bash "${BASE_DIR}/modules/optimize/run.sh" "$opt_auto" 2>&1 | \
        tee /tmp/ubuntils-optimize-out.txt | \
        "$(_TUI_CMD_fallback)" --title "Optimize" --scrolltext 30 80 || true
    tui_msgbox "Optimize" "$(tail -5 /tmp/ubuntils-optimize-out.txt)"
}

_run_install() {
    bash "${BASE_DIR}/modules/install/run.sh"
}

_run_monitor() {
    local choice
    choice=$(tui_menu "Monitor" "Monitor options:" \
        "status"  "Run monitor checks now (preview output)" \
        "cron"    "Install/remove cron job (runs every 5 min)" \
        "config"  "Edit thresholds in ubuntils.conf") || return

    case "$choice" in
        status)
            bash "${BASE_DIR}/modules/monitor/run.sh" 2>&1 | \
                tee /tmp/ubuntils-monitor-out.txt | \
                "$(_TUI_CMD_fallback)" --title "Monitor" --scrolltext 25 80 || true
            ;;
        cron)
            _manage_cron
            ;;
        config)
            "${EDITOR:-nano}" "${BASE_DIR}/config/ubuntils.conf"
            ;;
    esac
}

_manage_cron() {
    local cron_line="*/5 * * * * root bash ${BASE_DIR}/modules/monitor/run.sh >> ${LOG_DIR}/runs/monitor-cron.log 2>&1"
    local cron_file="/etc/cron.d/ubuntils-monitor"

    if [[ -f "$cron_file" ]]; then
        tui_yesno "Cron" "Monitor cron is installed. Remove it?" && {
            rm -f "$cron_file"
            tui_msgbox "Cron" "Monitor cron removed."
        }
    else
        tui_yesno "Cron" "Install monitor cron (every 5 minutes)?\n\n${cron_line}" && {
            echo "$cron_line" > "$cron_file"
            chmod 644 "$cron_file"
            tui_msgbox "Cron" "Monitor cron installed at ${cron_file}"
        }
    fi
}

_run_settings() {
    local choice
    choice=$(tui_menu "Settings" "Settings:" \
        "global"   "Edit global config (ubuntils.conf)" \
        "modules"  "Enable/disable modules (modules.conf)" \
        "detect"   "Re-run stack detection (force refresh)" \
        "back"     "Back to main menu") || return

    case "$choice" in
        global)  "${EDITOR:-nano}" "${BASE_DIR}/config/ubuntils.conf" ;;
        modules) "${EDITOR:-nano}" "${BASE_DIR}/config/modules.conf" ;;
        detect)  detect_run "--force" && tui_msgbox "Detect" "Detection cache refreshed." ;;
    esac
}

_TUI_CMD_fallback() {
    command -v whiptail &>/dev/null && echo "whiptail" || echo "dialog"
}

# Non-interactive / CLI mode
if [[ $# -gt 0 ]]; then
    case "${1:-}" in
        maintenance) shift; bash "${BASE_DIR}/modules/maintenance/run.sh" "$@" ;;
        security)    shift; bash "${BASE_DIR}/modules/security/run.sh" "$@" ;;
        optimize)    shift; bash "${BASE_DIR}/modules/optimize/run.sh" "$@" ;;
        install)     shift; bash "${BASE_DIR}/modules/install/run.sh" "$@" ;;
        monitor)     shift; bash "${BASE_DIR}/modules/monitor/run.sh" "$@" ;;
        --auto|--force) _main_menu ;;
        --help|-h)
            cat <<HELP
Usage: ubuntils.sh [module] [--auto] [--force]

Modules:
  maintenance   Run all maintenance checks
  security      Run security audit
  optimize      Run optimization suggestions [--auto to apply]
  install       Interactive install menu
  monitor       Run monitor checks (for cron use)

Flags:
  --auto        Apply changes without confirmation
  --force       Force re-run of stack detection
  --help        Show this help

No arguments: launch interactive TUI.
HELP
            ;;
        *) echo "Unknown module: $1. Use --help." >&2; exit 1 ;;
    esac
else
    _main_menu
fi
