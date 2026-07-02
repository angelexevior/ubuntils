#!/usr/bin/env bash
# ubuntils.sh — main entrypoint

set -uo pipefail

BASE_DIR="$(dirname "$(realpath "$0")")"

source "${BASE_DIR}/config/ubuntils.conf"
source "${BASE_DIR}/config/modules.conf"
source "${BASE_DIR}/lib/tui.sh"
source "${BASE_DIR}/lib/detect.sh"
source "${BASE_DIR}/lib/backup.sh"

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

_run_module_tui() {
    local title="$1" outfile="$2"; shift 2
    # Run module, capture to file, then display with textbox (reads file, not stdin)
    "$@" > "$outfile" 2>&1 || true
    if [[ -s "$outfile" ]]; then
        "$_TUI_CMD" --title "$title" --textbox "$outfile" 30 80 3>&1 1>&2 2>&3 || true
    else
        tui_msgbox "$title" "No output produced. Check logs in ${LOG_DIR}/runs/"
    fi
}

_run_maintenance() {
    _run_module_tui "Maintenance" /tmp/ubuntils-maintenance.txt \
        bash "${BASE_DIR}/modules/maintenance/run.sh" "$AUTO"
}

_run_security() {
    _run_module_tui "Security" /tmp/ubuntils-security.txt \
        bash "${BASE_DIR}/modules/security/run.sh"
}

_run_optimize() {
    local mode
    mode=$(tui_menu "Optimize" "Choose optimization mode:" \
        "interactive" "Show current → suggested → confirm each change" \
        "auto"        "Apply all suggestions without prompting (--auto)") || return
    local opt_auto=""
    [[ "$mode" == "auto" ]] && opt_auto="--auto"
    if [[ "$opt_auto" == "--auto" ]]; then
        _run_module_tui "Optimize" /tmp/ubuntils-optimize.txt \
            bash "${BASE_DIR}/modules/optimize/run.sh" "--auto"
    else
        # Interactive mode: run directly so confirm prompts (read/whiptail) work on the real terminal
        bash "${BASE_DIR}/modules/optimize/run.sh"
        echo
        read -rp "Press Enter to return to the menu..." _
    fi
}

_run_install() {
    bash "${BASE_DIR}/modules/install/run.sh"
}

_run_monitor() {
    local choice
    choice=$(tui_menu "Monitor" "Monitor options:" \
        "status"  "Run monitor checks now and show output" \
        "cron"    "Install/remove cron job (runs every 5 min)" \
        "config"  "Edit thresholds in ubuntils.conf") || return

    case "$choice" in
        status)
            _run_module_tui "Monitor" /tmp/ubuntils-monitor.txt \
                bash "${BASE_DIR}/modules/monitor/run.sh"
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
    # .out, not .log — a "monitor-*.log" name here would collide with report_finish's
    # own diff glob and get picked up as a fake "previous run" to diff against.
    local cron_line="*/5 * * * * root bash ${BASE_DIR}/modules/monitor/run.sh >> ${LOG_DIR}/runs/monitor-cron.out 2>&1"
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

_conf_get() {
    local file="$1" key="$2"
    grep "^${key}=" "$file" | tail -1 | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//'
}

_conf_set() {
    local file="$1" key="$2" val="$3" quoted="$4"
    backup_file "$file" >/dev/null
    if [[ "$quoted" == "yes" ]]; then
        sed -i "s|^${key}=.*|${key}=\"${val}\"|" "$file"
    else
        sed -i "s|^${key}=.*|${key}=${val}|" "$file"
    fi
}

# Menu-driven editor for simple KEY=VALUE config files. Booleans (0/1) get a
# yes/no prompt; everything else gets a text inputbox. Skips computed/path
# entries listed in $3 (space-separated key names).
_edit_config_file() {
    local title="$1" file="$2" skip_keys=" ${3:-} "
    while true; do
        local keys=() items=()
        while IFS= read -r k; do
            [[ -z "$k" ]] && continue
            [[ "$skip_keys" == *" ${k} "* ]] && continue
            keys+=("$k")
        done < <(grep -oP '^[A-Za-z_][A-Za-z0-9_]*(?==)' "$file")

        for k in "${keys[@]}"; do
            local v; v=$(_conf_get "$file" "$k")
            items+=("$k" "= ${v}")
        done
        items+=("back" "Back")

        local sel
        sel=$(tui_menu "$title" "Select a setting to edit:" "${items[@]}") || return
        [[ "$sel" == "back" ]] && return

        local cur; cur=$(_conf_get "$file" "$sel")
        local quoted="no"
        grep -qP "^${sel}=\"" "$file" && quoted="yes"

        if [[ "$cur" == "0" || "$cur" == "1" ]]; then
            if tui_yesno "$sel" "Enable ${sel}? (currently: ${cur})"; then
                _conf_set "$file" "$sel" "1" "$quoted"
            else
                _conf_set "$file" "$sel" "0" "$quoted"
            fi
        else
            local newval
            newval=$(tui_inputbox "$sel" "Enter new value for ${sel}:" "$cur") || continue
            _conf_set "$file" "$sel" "$newval" "$quoted"
        fi
    done
}

_edit_module_toggles() {
    local file="${BASE_DIR}/config/modules.conf"
    local keys=()
    while IFS= read -r line; do
        keys+=("${line%%=*}")
    done < <(grep -oP '^(maintenance|security|optimize|install|monitor)_[a-z0-9_]+=[01]$' "$file")

    if [[ "${#keys[@]}" -eq 0 ]]; then
        tui_msgbox "Module Toggles" "No toggles found in modules.conf"
        return
    fi

    local items=()
    for k in "${keys[@]}"; do
        local v; v=$(_conf_get "$file" "$k")
        local status="OFF"; [[ "$v" == "1" ]] && status="ON"
        items+=("$k" "${k//_/ }" "$status")
    done

    local selected
    selected=$(tui_checklist "Module Toggles" "Space to toggle a check on/off, Enter to save:" "${items[@]}") || return

    backup_file "$file" >/dev/null
    for k in "${keys[@]}"; do
        if [[ "$selected" == *"\"$k\""* ]]; then
            sed -i "s|^${k}=.*|${k}=1|" "$file"
        else
            sed -i "s|^${k}=.*|${k}=0|" "$file"
        fi
    done
    tui_msgbox "Saved" "Module toggles updated."
}

_run_settings() {
    local choice
    choice=$(tui_menu "Settings" "Settings:" \
        "sudo"     "Set sudo user baseline" \
        "ports"    "Set expected open ports baseline" \
        "global"   "Edit global config (ubuntils.conf)" \
        "modules"  "Enable/disable module toggles (modules.conf)" \
        "detect"   "Re-run stack detection (force refresh)" \
        "back"     "Back to main menu") || return

    case "$choice" in
        sudo)
            local current; current=$(grep '^SUDO_BASELINE_USERS=' "${BASE_DIR}/config/modules.conf" | cut -d= -f2 | tr -d '"')
            local cur_sudo; cur_sudo=$(getent group sudo 2>/dev/null | cut -d: -f4)
            local cur_admin; cur_admin=$(getent group admin 2>/dev/null | cut -d: -f4)
            local new_val
            new_val=$(tui_inputbox "Sudo Baseline" \
                "Space-separated list of expected sudo users.\nCurrently in sudo/admin groups: ${cur_sudo} ${cur_admin}" \
                "${current}") || return
            sed -i "s|^SUDO_BASELINE_USERS=.*|SUDO_BASELINE_USERS=\"${new_val}\"|" "${BASE_DIR}/config/modules.conf"
            tui_msgbox "Saved" "Sudo baseline set to: ${new_val}"
            ;;
        ports)
            local current; current=$(grep '^PORTS_BASELINE=' "${BASE_DIR}/config/modules.conf" | cut -d= -f2 | tr -d '"')
            local new_val
            new_val=$(tui_inputbox "Ports Baseline" \
                "Space-separated list of expected listening ports." \
                "${current}") || return
            sed -i "s|^PORTS_BASELINE=.*|PORTS_BASELINE=\"${new_val}\"|" "${BASE_DIR}/config/modules.conf"
            tui_msgbox "Saved" "Port baseline set to: ${new_val}"
            ;;
        global)  _edit_config_file "Global Config" "${BASE_DIR}/config/ubuntils.conf" "LOG_DIR" ;;
        modules) _edit_module_toggles ;;
        detect)
            rm -f "$DETECT_CACHE"
            detect_load "--force" 2>/dev/null || true
            tui_msgbox "Detect" "Detection cache refreshed."
            ;;
    esac
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
