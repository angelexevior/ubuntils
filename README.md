# ubuntils

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Bash](https://img.shields.io/badge/language-bash-green.svg)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/platform-Ubuntu-orange.svg)](https://ubuntu.com/)
[![CI](https://github.com/angelexevior/ubuntils/actions/workflows/ci.yml/badge.svg)](https://github.com/angelexevior/ubuntils/actions/workflows/ci.yml)

Modular bash toolkit for Ubuntu servers. Covers maintenance checks, security auditing, performance optimization, component installation, and threshold-based monitoring — all driven by a whiptail TUI or usable non-interactively from the CLI.

> **Pure bash. No dependencies beyond standard Ubuntu tools and `whiptail`.**

---

## Screenshots

| Maintenance | Security |
|---|---|
| ![Maintenance](https://raw.githubusercontent.com/angelexevior/ubuntils/master/docs/screenshot_maintenance.png) | ![Security](https://raw.githubusercontent.com/angelexevior/ubuntils/master/docs/screenshot_security.png) |

---

## Features

- **Whiptail TUI** — menu-driven interface, no typing required. Falls back to `dialog` if whiptail isn't available.
- **Autodetection** — detects your installed stack (PHP versions, MySQL/MariaDB, nginx, Apache, fail2ban, Redis, Node, Composer, certbot) once and caches the result. All modules work from that cache.
- **Config-driven** — every check and module can be toggled in `config/modules.conf`. Thresholds and notification channels live in `config/ubuntils.conf`.
- **Safe by default** — any write action (config edits, installs) backs up the original first and shows a diff before applying. Use `--auto` to skip confirmation.
- **Idempotent** — safe to re-run anything, anytime.
- **Run diffing** — each run's output is saved to `logs/runs/` and diffed against the previous run, so you can see what changed.
- **Notifications** — email (sendmail/msmtp), Telegram, and Slack, any combination, all opt-in.

---

## Requirements

- Ubuntu (tested on 20.04+)
- `bash` 4.0+
- `whiptail` (package: `whiptail`) or `dialog`
- Run as root for most checks and all write actions

---

## Installation

```bash
git clone https://github.com/angelexevior/ubuntils.git
cd ubuntils
sudo bash install.sh
```

`install.sh` handles everything:

- Confirms you're on Ubuntu
- Checks for `whiptail` (or `dialog`) and offers to install it if missing
- Checks optional tools (`curl`, `openssl`, `ss`, etc.) and warns if any are absent
- Asks you for thresholds, notification settings, and security baselines, then writes `config/ubuntils.conf` and `config/modules.conf`
- Creates the log and backup directories with correct permissions
- Runs a syntax check across all scripts before finishing
- Optionally installs the monitor cron job (`/etc/cron.d/ubuntils-monitor`)
- Optionally creates a `/usr/local/bin/ubuntils` symlink so you can run it from anywhere

Re-running `install.sh` is safe — existing config is backed up before being overwritten, and module toggles in `modules.conf` are preserved.

---

## Usage

### Interactive TUI

```bash
sudo ./ubuntils.sh
```

Launches the main menu. Navigate with arrow keys, Enter to select, Escape/Cancel to go back.

### CLI (non-interactive)

Run a specific module directly:

```bash
sudo ./ubuntils.sh maintenance
sudo ./ubuntils.sh security
sudo ./ubuntils.sh optimize
sudo ./ubuntils.sh optimize --auto   # apply all suggestions without prompting
sudo ./ubuntils.sh monitor           # single monitor pass (for cron)
```

### Flags

| Flag | Effect |
|---|---|
| `--auto` | Skip confirmation prompts, apply changes automatically |
| `--force` | Force re-run of stack detection (ignores cache) |
| `--help` | Show CLI usage |

---

## Modules

### Maintenance

Runs a suite of read-only health checks and reports pass/warn/fail per item:

| Check | What it does |
|---|---|
| Disk space | Usage % per filesystem, flags large growth vs previous run |
| Inode usage | Inode % per filesystem |
| Server load | 1m/5m/15m load average vs configurable thresholds |
| APT updates | Pending updates, flags security updates separately |
| Failed systemd units | Lists any units in failed state |
| Zombie processes | Detects zombie and orphaned processes |
| Swap / OOM | Swap usage %, OOM kill history from kernel log |
| Log rotation | Flags log files in `/var/log` not rotated within X days |
| Cron scripts | Detects cron entries pointing to missing files |
| Backup verify | Checks backup files exist, are non-empty, and haven't shrunk >50% |

### Security

Reads the detection cache and only runs checks relevant to your stack:

| Check | Requires |
|---|---|
| SSH config audit (PermitRootLogin, PasswordAuthentication, Protocol, Port) | always |
| Sudo user list vs configurable baseline | always |
| Open ports vs baseline | always |
| fail2ban status and active jails | always |
| SSL certificate expiry per vhost | always |
| PHP version EOL check | PHP detected |
| PHP config (display_errors, expose_php, dangerous disabled_functions) | PHP detected |
| Exposed phpinfo() files in doc roots | PHP detected |
| MySQL: remote root access, anonymous users, wildcard grants | MySQL/MariaDB detected |
| nginx/Apache: server tokens, TLS protocol/cipher grade | nginx or Apache detected |

### Optimize

Shows current value → suggested value → diff, then asks to confirm before writing. Pass `--auto` to skip confirmation. Always backs up configs before touching them.

| Optimization | Logic |
|---|---|
| sysctl tuning | vm.swappiness, net.core.somaxconn, tcp backlog, file-max |
| nginx workers/connections/gzip | Based on CPU core count |
| PHP-FPM pm.max_children | Calculated from available RAM ÷ avg process memory footprint |
| MySQL innodb_buffer_pool_size | 60% of total RAM |
| MySQL max_connections | Based on available RAM |

### Install

Whiptail checkbox menu. Already-installed components are shown but pre-unchecked. After installation, offers to immediately run the optimize module with sane defaults.

Installable: PHP (version picker), MySQL, nginx, Apache, phpMyAdmin, fail2ban, certbot.

### Monitor

Designed to run from cron. Checks thresholds and alerts **only on threshold cross** — no repeat notifications if the condition persists.

Checks: load average, disk usage per filesystem, 4xx error rate (from nginx/Apache access log), MySQL slow queries, failed SSH login rate.

State is kept in `logs/state/` so each check knows whether it already alerted.

**Install the cron job from the TUI** (Monitor → Install cron), or add it manually:

```
*/5 * * * * root bash /path/to/ubuntils/modules/monitor/run.sh >> /path/to/ubuntils/logs/runs/monitor-cron.out 2>&1
```

---

## Configuration

### `config/ubuntils.conf`

Global settings: log paths, thresholds, notification channels.

```bash
# Alert thresholds
LOAD_AVG_WARN=4
LOAD_AVG_CRIT=8
DISK_WARN=80
DISK_CRIT=90
RATE_4XX_WARN=50       # per ~minute (sampled from last 200 log lines)
SLOW_QUERIES_WARN=10
FAILED_SSH_WARN=5

# Notifications (set to 1 to enable)
NOTIFY_EMAIL=0
NOTIFY_TELEGRAM=0
NOTIFY_SLACK=0

EMAIL_TO=""
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""
SLACK_WEBHOOK_URL=""
```

### `config/modules.conf`

Toggle any individual check on or off:

```bash
maintenance_disk_space=1
maintenance_apt_updates=1
security_ssh_config=1
security_cve_lookup=0   # off by default (needs network)
optimize_nginx=1
# ... etc
```

Set your sudo user baseline and port baseline here too:

```bash
SUDO_BASELINE_USERS="alice bob"
PORTS_BASELINE="22 80 443"
```

---

## Directory structure

```
ubuntils/
├── ubuntils.sh              # entrypoint, TUI main menu, CLI passthrough
├── config/
│   ├── ubuntils.conf        # global settings, thresholds, notify channels
│   └── modules.conf         # per-module and per-check enable/disable
├── lib/
│   ├── detect.sh            # stack autodetection → /tmp/ubuntils-detect.cache
│   ├── report.sh            # pass/warn/fail output, text/HTML/JSON, run diffing
│   ├── notify.sh            # email/Telegram/Slack senders
│   ├── backup.sh            # backup + diff-before-apply helper
│   └── tui.sh               # whiptail/dialog wrapper functions
├── modules/
│   ├── maintenance/         # one script per check, sourced by run.sh
│   ├── security/
│   ├── optimize/
│   ├── install/
│   └── monitor/
└── logs/
    ├── runs/                # timestamped run reports, diffed vs previous
    └── state/               # monitor daemon state (last-alerted values)
```

---

## Notifications

Enable any combination in `config/ubuntils.conf`:

**Email** — requires `sendmail` or `msmtp` to be configured on the server:
```bash
NOTIFY_EMAIL=1
EMAIL_TO="you@example.com"
```

**Telegram** — create a bot via @BotFather, get your chat ID:
```bash
NOTIFY_TELEGRAM=1
TELEGRAM_BOT_TOKEN="123456:ABC..."
TELEGRAM_CHAT_ID="987654321"
```

**Slack** — create an incoming webhook in your Slack workspace:
```bash
NOTIFY_SLACK=1
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/..."
```

---

## Report formats

Set `REPORT_FORMAT` in `config/ubuntils.conf`. Accepts a comma-separated list:

```bash
REPORT_FORMAT="text"          # terminal output (default)
REPORT_FORMAT="text,html"     # terminal + HTML file saved to logs/runs/
REPORT_FORMAT="text,json"     # terminal + JSON file
REPORT_FORMAT="text,html,json"
```

HTML reports are static files saved to `logs/runs/`. Open them in any browser.
