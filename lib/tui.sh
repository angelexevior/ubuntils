#!/usr/bin/env bash
# lib/tui.sh — shared whiptail/dialog helper functions

[[ -n "${_UBUNTILS_TUI_LOADED:-}" ]] && return 0
_UBUNTILS_TUI_LOADED=1

_TUI_CMD=""

tui_init() {
    if command -v whiptail &>/dev/null; then
        _TUI_CMD="whiptail"
    elif command -v dialog &>/dev/null; then
        _TUI_CMD="dialog"
    else
        echo "ERROR: neither whiptail nor dialog is installed." >&2
        exit 1
    fi
}

tui_cmd() { echo "$_TUI_CMD"; }

tui_msgbox() {
    local title="$1" msg="$2"
    "$_TUI_CMD" --title "$title" --msgbox "$msg" 12 70 3>&1 1>&2 2>&3
}

tui_yesno() {
    local title="$1" msg="$2"
    "$_TUI_CMD" --title "$title" --yesno "$msg" 12 70 3>&1 1>&2 2>&3
}

# Returns selected item via stdout
tui_menu() {
    local title="$1" prompt="$2"
    shift 2
    local items=("$@")
    "$_TUI_CMD" --title "$title" --menu "$prompt" 20 70 12 "${items[@]}" 3>&1 1>&2 2>&3
}

# Returns newline-separated checked items
tui_checklist() {
    local title="$1" prompt="$2"
    shift 2
    local items=("$@")
    "$_TUI_CMD" --title "$title" --checklist "$prompt" 20 70 12 "${items[@]}" 3>&1 1>&2 2>&3
}

tui_inputbox() {
    local title="$1" prompt="$2" default="${3:-}"
    "$_TUI_CMD" --title "$title" --inputbox "$prompt" 10 70 "$default" 3>&1 1>&2 2>&3
}

tui_gauge() {
    local title="$1" prompt="$2" pct="${3:-0}"
    echo "$pct" | "$_TUI_CMD" --title "$title" --gauge "$prompt" 7 70 0
}

tui_progress() {
    local title="$1"
    local -n _steps=$2  # nameref to array of step names
    local total="${#_steps[@]}"
    local i=0
    for step in "${_steps[@]}"; do
        local pct=$(( i * 100 / total ))
        echo "$pct" | "$_TUI_CMD" --title "$title" --gauge "Running: $step" 7 70 0
        (( i++ ))
    done
}
