#!/usr/bin/env bash
# lib/notify.sh — email/telegram/slack notification senders

[[ -n "${_UBUNTILS_NOTIFY_LOADED:-}" ]] && return 0
_UBUNTILS_NOTIFY_LOADED=1

notify_all() {
    local subject="$1"
    local body="$2"
    local server_id="${SERVER_ID:-$(hostname -s 2>/dev/null || echo server)}"
    local tagged_subject="[${server_id}] ${subject}"
    [[ "${NOTIFY_EMAIL:-0}" -eq 1 ]]    && notify_email "$tagged_subject" "$body"
    [[ "${NOTIFY_TELEGRAM:-0}" -eq 1 ]] && notify_telegram "$tagged_subject" "$body"
    [[ "${NOTIFY_SLACK:-0}" -eq 1 ]]    && notify_slack "$tagged_subject" "$body"
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
    # Sent as plain text (no parse_mode): subject/body can contain arbitrary
    # characters (hostnames, paths, log lines with _ * [ ] etc.), and
    # Telegram's Markdown parser 400s on unbalanced entities, which would
    # otherwise silently drop the alert.
    local text; text=$(printf "%s\n\n%s" "$subject" "$body")
    local response
    response=$(curl -sS -X POST \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d chat_id="${TELEGRAM_CHAT_ID}" \
        --data-urlencode text="$text")
    if [[ "$response" != *'"ok":true'* ]]; then
        echo "notify_telegram: send failed: $response" >&2
        return 1
    fi
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
