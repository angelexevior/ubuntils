#!/usr/bin/env bash
# lib/notify.sh — email/telegram/slack notification senders

[[ -n "${_UBUNTILS_NOTIFY_LOADED:-}" ]] && return 0
_UBUNTILS_NOTIFY_LOADED=1

notify_all() {
    local subject="$1"
    local body="$2"
    [[ "${NOTIFY_EMAIL:-0}" -eq 1 ]]    && notify_email "$subject" "$body"
    [[ "${NOTIFY_TELEGRAM:-0}" -eq 1 ]] && notify_telegram "$subject" "$body"
    [[ "${NOTIFY_SLACK:-0}" -eq 1 ]]    && notify_slack "$subject" "$body"
}

notify_email() {
    local subject="$1"
    local body="$2"
    [[ -z "${EMAIL_TO:-}" ]] && { echo "notify_email: EMAIL_TO not set" >&2; return 1; }

    local sender=""
    if command -v msmtp &>/dev/null; then
        sender="msmtp"
    elif command -v sendmail &>/dev/null; then
        sender="sendmail"
    else
        echo "notify_email: no sendmail or msmtp found" >&2; return 1
    fi

    {
        printf "To: %s\n" "$EMAIL_TO"
        printf "From: %s\n" "${EMAIL_FROM:-ubuntils@localhost}"
        printf "Subject: %s\n\n" "$subject"
        printf "%s\n" "$body"
    } | "$sender" -t
}

notify_telegram() {
    local subject="$1"
    local body="$2"
    [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]] && {
        echo "notify_telegram: TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID not set" >&2; return 1
    }
    local text; text=$(printf "*%s*\n%s" "$subject" "$body")
    curl -sS -X POST \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d chat_id="${TELEGRAM_CHAT_ID}" \
        -d parse_mode="Markdown" \
        --data-urlencode text="$text" \
        -o /dev/null
}

notify_slack() {
    local subject="$1"
    local body="$2"
    [[ -z "${SLACK_WEBHOOK_URL:-}" ]] && {
        echo "notify_slack: SLACK_WEBHOOK_URL not set" >&2; return 1
    }
    local payload; payload=$(printf '{"text":"*%s*\n%s"}' "$subject" "${body//\"/\\\"}")
    curl -sS -X POST "$SLACK_WEBHOOK_URL" \
        -H 'Content-Type: application/json' \
        -d "$payload" \
        -o /dev/null
}
