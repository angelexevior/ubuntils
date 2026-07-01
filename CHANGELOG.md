# Changelog

## [1.0.0] — 2025-07-01

Initial release.

### Added

**Core**
- `lib/detect.sh` — stack autodetection (PHP, MySQL/MariaDB, nginx, Apache, fail2ban, Redis, Node, Composer, certbot); result cached to `/tmp/ubuntils-detect.cache`, auto-invalidated when script is updated
- `lib/report.sh` — pass/warn/fail output to stdout; optional HTML and JSON file output; run diffing against previous run
- `lib/backup.sh` — backup-before-write + diff-before-apply for all config changes
- `lib/notify.sh` — email (sendmail/msmtp), Telegram bot, Slack webhook notifications
- `lib/tui.sh` — whiptail (fallback: dialog) wrapper functions
- `config/ubuntils.conf` — global thresholds and notification settings
- `config/modules.conf` — per-check enable/disable toggles

**Maintenance module** — 10 checks
- Disk space usage with growth-delta detection vs previous run
- Inode usage per filesystem
- Server load average (1m/5m/15m)
- Pending APT updates with security-update separation
- Failed systemd units
- Zombie and orphaned processes
- Swap usage and OOM kill history
- Log rotation staleness check
- Cron jobs pointing to missing scripts
- Backup file existence and size-sanity check

**Security module** — 14 checks
- SSH config audit (PermitRootLogin, PasswordAuthentication, Protocol, Port)
- Sudo user list vs configurable baseline
- Open ports vs configurable baseline
- fail2ban status and active jails
- SSL certificate expiry per detected vhost
- PHP version EOL check
- PHP config audit (display_errors, expose_php, disable_functions)
- Exposed phpinfo() files in doc roots
- MySQL/MariaDB: remote root access, anonymous users, wildcard grants
- nginx/Apache: server_tokens, TLS protocol/cipher grade

**Optimize module** — 4 areas
- sysctl tuning (swappiness, somaxconn, tcp backlog, file-max)
- nginx worker_processes, worker_connections, gzip
- PHP-FPM pm.max_children calculated from RAM ÷ avg process footprint
- MySQL innodb_buffer_pool_size and max_connections from RAM

**Install module**
- Whiptail checklist for PHP (version picker), MySQL, nginx, Apache, phpMyAdmin, fail2ban, certbot
- Idempotent — already-installed components pre-unchecked
- Offers to run optimize immediately after install

**Monitor module**
- Cron-driven threshold monitoring (load, disk, 4xx rate, slow queries, failed SSH)
- State-based alerting — notifies only on threshold cross and recovery, no repeat spam
- Notifications via email, Telegram, Slack (any combination, all opt-in)

**Entrypoint**
- `ubuntils.sh` — whiptail main menu TUI
- Full CLI passthrough: `ubuntils maintenance`, `ubuntils security`, `ubuntils optimize --auto`, etc.
- Settings menu with TUI-based sudo/port baseline editor and force-redetect

**Setup**
- `install.sh` — interactive setup wizard: dependency checks, whiptail install prompt, threshold configuration, notification setup, security baselines, cron install, system-wide symlink
