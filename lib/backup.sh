#!/usr/bin/env bash
# lib/backup.sh — config backup + diff-before-apply helper

[[ -n "${_UBUNTILS_BACKUP_LOADED:-}" ]] && return 0
_UBUNTILS_BACKUP_LOADED=1

BACKUP_DIR="${BACKUP_DIR:-/var/backups/ubuntils}"

backup_file() {
    local src="$1"
    [[ -f "$src" ]] || { echo "backup: source not found: $src" >&2; return 1; }

    mkdir -p "$BACKUP_DIR"
    local ts; ts=$(date '+%Y%m%d-%H%M%S')
    local bak="${BACKUP_DIR}/$(basename "$src").${ts}.bak"
    cp -a "$src" "$bak"
    echo "Backed up: $src → $bak"
    echo "$bak"
}

# Show diff between original and proposed new content, then optionally apply.
# Usage: backup_diff_apply <file> <new_content_or_tmpfile> [--auto]
#   if --auto is set, apply without prompting.
backup_diff_apply() {
    local target="$1"
    local new_content_file="$2"
    local auto="${3:-}"

    # Backup original
    local bak; bak=$(backup_file "$target") || return 1

    # Show diff
    local diff_out; diff_out=$(diff -u "$target" "$new_content_file" 2>/dev/null || true)
    if [[ -z "$diff_out" ]]; then
        echo "No changes to apply for $target"
        return 0
    fi

    echo ""
    echo "=== Proposed changes to: $target ==="
    echo "$diff_out"
    echo ""

    if [[ "$auto" == "--auto" ]]; then
        cp "$new_content_file" "$target"
        echo "Applied."
        return 0
    fi

    # Interactive confirm
    if command -v whiptail &>/dev/null; then
        whiptail --title "Apply changes?" \
            --yesno "Apply the shown changes to:\n${target}\n\n(backup saved to ${bak})" 12 70 3>&1 1>&2 2>&3
        local rc=$?
        if [[ $rc -eq 0 ]]; then
            cp "$new_content_file" "$target"
            echo "Applied."
        else
            echo "Aborted — original restored from backup."
            cp "$bak" "$target"
        fi
    else
        read -rp "Apply changes? [y/N] " ans
        if [[ "$ans" =~ ^[Yy]$ ]]; then
            cp "$new_content_file" "$target"
            echo "Applied."
        else
            echo "Aborted."
        fi
    fi
}
