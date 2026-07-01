#!/usr/bin/env bash
# lib/report.sh — shared output formatting: text/html/json, pass/warn/fail

[[ -n "${_UBUNTILS_REPORT_LOADED:-}" ]] && return 0
_UBUNTILS_REPORT_LOADED=1

REPORT_FORMAT="${REPORT_FORMAT:-text}"
_REPORT_RESULTS=()

# Colors (text mode only, disabled if not a tty)
if [[ -t 1 ]]; then
    _C_PASS="\033[0;32m"
    _C_WARN="\033[0;33m"
    _C_FAIL="\033[0;31m"
    _C_INFO="\033[0;36m"
    _C_RESET="\033[0m"
else
    _C_PASS="" _C_WARN="" _C_FAIL="" _C_INFO="" _C_RESET=""
fi

report_pass() { _report_line "PASS" "$*" "${_C_PASS}"; }
report_warn() { _report_line "WARN" "$*" "${_C_WARN}"; }
report_fail() { _report_line "FAIL" "$*" "${_C_FAIL}"; }
report_info() { _report_line "INFO" "$*" "${_C_INFO}"; }

_report_line() {
    local level="$1" msg="$2" color="$3"
    _REPORT_RESULTS+=("${level}|${msg}")
    if [[ "$REPORT_FORMAT" == *"text"* ]]; then
        printf "${color}[%s]${_C_RESET} %s\n" "$level" "$msg"
    fi
}

report_section() {
    local title="$1"
    if [[ "$REPORT_FORMAT" == *"text"* ]]; then
        printf "\n${_C_INFO}=== %s ===${_C_RESET}\n" "$title"
    fi
}

report_start() {
    _REPORT_RESULTS=()
    _REPORT_MODULE="${1:-check}"
    _REPORT_TS=$(date '+%Y-%m-%dT%H:%M:%S')
}

report_finish() {
    local pass=0 warn=0 fail=0
    for r in "${_REPORT_RESULTS[@]}"; do
        case "${r%%|*}" in
            PASS) (( pass++ )) ;;
            WARN) (( warn++ )) ;;
            FAIL) (( fail++ )) ;;
        esac
    done

    if [[ "$REPORT_FORMAT" == *"text"* ]]; then
        printf "\n%s — PASS:%d  WARN:%d  FAIL:%d\n" "$_REPORT_MODULE" "$pass" "$warn" "$fail"
    fi

    if [[ "$REPORT_FORMAT" == *"json"* ]]; then
        _report_json "$pass" "$warn" "$fail"
    fi

    if [[ "$REPORT_FORMAT" == *"html"* ]]; then
        _report_html "$pass" "$warn" "$fail"
    fi

    # Save run log for diffing
    local log_dir="${LOG_DIR:-$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../logs}"
    local runs_dir="${log_dir}/runs"
    mkdir -p "$runs_dir"
    local run_file="${runs_dir}/${_REPORT_MODULE}-${_REPORT_TS}.log"
    {
        echo "module=${_REPORT_MODULE}"
        echo "timestamp=${_REPORT_TS}"
        echo "pass=${pass} warn=${warn} fail=${fail}"
        for r in "${_REPORT_RESULTS[@]}"; do
            echo "$r"
        done
    } > "$run_file"

    # Diff against previous run
    local prev
    prev=$(ls -t "${runs_dir}/${_REPORT_MODULE}-"*.log 2>/dev/null | sed -n '2p')
    if [[ -n "$prev" ]]; then
        local diff_out; diff_out=$(diff "$prev" "$run_file" 2>/dev/null || true)
        if [[ -n "$diff_out" ]]; then
            printf "\n${_C_INFO}Changes since last run:${_C_RESET}\n%s\n" "$diff_out"
        fi
    fi

    (( fail > 0 )) && return 2
    (( warn > 0 )) && return 1
    return 0
}

_report_json() {
    local pass="$1" warn="$2" fail="$3"
    printf '{"module":"%s","timestamp":"%s","pass":%d,"warn":%d,"fail":%d,"results":[' \
        "$_REPORT_MODULE" "$_REPORT_TS" "$pass" "$warn" "$fail"
    local first=1
    for r in "${_REPORT_RESULTS[@]}"; do
        local lvl="${r%%|*}" msg="${r#*|}"
        [[ "$first" -eq 1 ]] && first=0 || printf ','
        printf '{"level":"%s","message":"%s"}' "$lvl" "${msg//\"/\\\"}"
    done
    printf ']}\n'
}

_report_html() {
    local pass="$1" warn="$2" fail="$3"
    local log_dir="${LOG_DIR:-$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../logs}"
    local html_file="${log_dir}/runs/${_REPORT_MODULE}-${_REPORT_TS}.html"
    {
        cat <<HTML
<!DOCTYPE html><html><head><meta charset="utf-8">
<title>ubuntils — ${_REPORT_MODULE}</title>
<style>
body{font-family:monospace;background:#1e1e1e;color:#d4d4d4;padding:20px}
h1{color:#9cdcfe}.pass{color:#4ec9b0}.warn{color:#dcdcaa}.fail{color:#f44747}.info{color:#9cdcfe}
table{border-collapse:collapse;width:100%}td{padding:4px 8px;border-bottom:1px solid #333}
.summary{margin:16px 0;font-size:1.1em}
</style></head><body>
<h1>ubuntils — ${_REPORT_MODULE}</h1>
<div class="summary">
  <span class="pass">PASS: ${pass}</span> &nbsp;
  <span class="warn">WARN: ${warn}</span> &nbsp;
  <span class="fail">FAIL: ${fail}</span>
  &nbsp;&mdash;&nbsp; ${_REPORT_TS}
</div>
<table>
HTML
        for r in "${_REPORT_RESULTS[@]}"; do
            local lvl="${r%%|*}" msg="${r#*|}"
            local cls; cls=$(echo "$lvl" | tr '[:upper:]' '[:lower:]')
            printf '<tr><td class="%s">%s</td><td>%s</td></tr>\n' "$cls" "$lvl" "${msg//</&lt;}"
        done
        echo '</table></body></html>'
    } > "$html_file"
    printf "HTML report: %s\n" "$html_file"
}
