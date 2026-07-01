# Contributing

Contributions are welcome — bug fixes, new checks, better detection, documentation improvements.

## Rules

- **Bash only.** No Python, no Ruby, no Node. If you need a one-liner helper, use `awk` or `sed`.
- **Idempotent.** Every script must be safe to run multiple times on the same system.
- **No hardcoding.** Values that vary between servers belong in `config/ubuntils.conf` or `config/modules.conf`.
- **Back up before writing.** Any script that modifies a system config must call `lib/backup.sh` first.
- **Use the report API.** Output goes through `report_pass`, `report_warn`, `report_fail`, `report_info` — never raw `echo` in module code.
- **No attribution.** No author names, emails, URLs, or signatures in code or comments.

## Adding a new maintenance/security check

1. Create `modules/<category>/your_check.sh` following the pattern of an existing check:
   - Source `lib/report.sh` is handled by the runner — don't re-source it
   - Define a single `check_your_check()` function
   - Add a standalone run block at the bottom guarded by `[[ "${BASH_SOURCE[0]}" == "$0" ]]`
2. Add an enable/disable key to `config/modules.conf`: `your_category_your_check=1`
3. Add one line to `modules/<category>/run.sh` to call your function when enabled
4. Test standalone: `sudo bash modules/<category>/your_check.sh`
5. Test via runner: `sudo ubuntils <category>`

## Adding a new optimization

Same pattern as above, but the function must:
- Accept `"$AUTO"` as its first argument
- Show current value vs suggested value before changing anything
- Call `backup_diff_apply` before writing any config file
- Skip writes when `"$AUTO"` is not `"--auto"` (interactive mode)

## Submitting

1. Fork the repo
2. Branch from `master`
3. Open a pull request with a clear description of what the check does and why it's useful
4. Include an example of the output (pass/warn/fail lines)

## Reporting bugs

Use the **Bug Report** issue template. Include your Ubuntu version, the exact command you ran, and the full output.
