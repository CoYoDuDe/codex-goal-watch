# codex-goal-watch

Safely auto-resume usage-limited OpenAI Codex CLI goals running in GNU screen sessions on Debian and Ubuntu.

> Unofficial community project – not affiliated with or endorsed by OpenAI.

`codex-goal-watch` is a compatibility supervisor for unattended Codex CLI sessions. Native Codex behavior takes precedence if equivalent functionality becomes available.

## What it does

The watchdog reads visible GNU screen terminal output. It recognizes the combination of a Codex account usage-limit message, a paused goal status, and a valid displayed reset time. It waits for the reset plus a safety grace period, then resumes only when the visible composer is known safe.

Several sessions may be registered and enabled. v0.1.0 examines all enabled sessions but sends at most one resume action per timer run and applies a global cooldown afterwards. Higher numerical priority wins; equal priority is ordered by waiting time and then session name. This avoids blindly resuming every session that shares one Codex usage allowance.

## Security model

The default is fail-closed:

- Unknown, ambiguous, or hidden composer content is never sent.
- A generic usage limit alone, a goal status alone, or a reset time alone does not cause input.
- An empty composer receives `/goal resume` plus Enter. A visible `/goal resume` draft receives Enter only.
- A hidden `[Pasted Content ...]` draft is blocked until `codex-goal-watch arm-enter NAME`; the permission is consumed once.
- Replace-goal confirmation automation is deliberately not implemented in v0.1.0. The dialog is reported as blocked.
- A global `flock`, state fingerprints, per-session attempt limits, stale re-read checks, verification delay, and retry delay prevent action storms.
- A successful `screen` key delivery is not a successful resume; a later visible-state verification is required.

The terminal interface can change. Use `inspect` before enabling a session, because this tool only observes visible terminal output.

## Requirements

- Debian 12+ or Ubuntu 22.04+
- Bash 5, GNU screen, Python 3.9+, `flock`, `pstree`, GNU `date`, `logger`, and systemd
- Codex CLI running inside a GNU screen session owned by the configured user

## Install

```bash
git clone https://github.com/CoYoDuDe/codex-goal-watch.git
cd codex-goal-watch
sudo ./scripts/install.sh --enable
```

To register a session during installation:

```bash
sudo ./scripts/install.sh --user root --session project-alpha --window auto --timezone Europe/Berlin --enable
```

The installer backs up existing program, library, configuration, state, and systemd files first. It migrates a legacy single-session `active` file into a session registry and removes one-time permissions during migration.

## Quick start and multiple sessions

```bash
sudo codex-goal-watch add project-alpha auto --priority 100
sudo codex-goal-watch add project-beta auto --priority 80
sudo codex-goal-watch add project-gamma auto --priority 50

codex-goal-watch list
codex-goal-watch inspect --all
codex-goal-watch status --all
```

New screen sessions do not require systemd changes. `auto` examines up to `WINDOW_SCAN_MAX` windows and refuses ambiguous matches. `activate NAME` is a compatible alias for `add NAME`; it no longer disables other registrations. `deactivate NAME` disables one registration. Use `deactivate --all` only when all registrations should be disabled.

## Commands

| Command | Purpose |
| --- | --- |
| `list` | Show registered sessions and their last state. |
| `add NAME [WINDOW|auto] [--priority N] [--user USER]` | Register and enable a session. |
| `remove NAME` | Remove registry and runtime state; never stop screen. |
| `enable NAME` / `disable NAME` | Toggle automatic handling. |
| `priority NAME N` | Set priority from 0 to 100000. |
| `status [NAME|--all]` | Show global cooldown and session state. |
| `inspect [NAME|--all]` | Read-only UI analysis; never sends keys. |
| `run` | One timer watchdog pass; may send at most one safe action. |
| `arm-enter NAME` | Allow one hidden-paste Enter for that session. |
| `disarm-enter NAME` | Remove the one-time permission. |
| `reset-state [NAME|--all]` | Clear retry/fingerprint/verification state only. |
| `cancel-pending [NAME|--all]` | Discard pending state but keep registration. |
| `doctor` | Read-only dependency and configuration diagnostics. |

`--force` on `add`/`activate` bypasses only the Codex-process preflight. It never disables a later safety check.

## Composer behavior

| Visible bottom composer | Behavior after a valid reset |
| --- | --- |
| empty prompt (`>`, `:`, or Codex prompt) | send `/goal resume` and Enter |
| `/goal resume` or `/goal resume [Pasted Content ...]` | send Enter only |
| `[Pasted Content ...]` | `BLOCKED_HIDDEN_PASTE` unless armed for this session |
| any other text | `BLOCKED_UNKNOWN_INPUT` |
| no trusted composer | `BLOCKED_COMPOSER_UNCERTAIN` |

## Configuration

`/etc/codex-goal-watch/config` is a strict `KEY=VALUE` file, not a shell script. Unknown keys and invalid values fail closed. Defaults:

```text
TIMEZONE=Europe/Berlin
GRACE_SECONDS=120
RETRY_SECONDS=900
VERIFY_SECONDS=30
MAX_ATTEMPTS=3
WINDOW_SCAN_MAX=30
SCREEN_USER=root
LOG_LEVEL=info
HARD_COPY_LINES=100
MAX_CONCURRENT_SESSIONS=1
GLOBAL_ACTION_COOLDOWN_SECONDS=120
```

`MAX_CONCURRENT_SESSIONS` is intentionally fixed to `1` in v0.1.0. Several sessions may wait, but only one resume can be sent per run and the global cooldown prevents concurrent use of a shared account quota.

## Operations and troubleshooting

```bash
systemctl status codex-goal-watch.timer --no-pager
systemctl list-timers --all codex-goal-watch.timer --no-pager
journalctl -u codex-goal-watch.service -n 100 --no-pager
codex-goal-watch doctor
codex-goal-watch inspect --all
```

See [architecture](docs/architecture.md), [security model](docs/security-model.md), and [troubleshooting](docs/troubleshooting.md). Several Codex sessions can share one account usage limit; the watchdog queues candidates rather than treating a reset as permission to send input everywhere.

## Update and uninstall

```bash
sudo ./scripts/update.sh
sudo ./scripts/uninstall.sh --keep-config
sudo ./scripts/uninstall.sh --purge --non-interactive
```

The updater validates source, backs up installed files, stops only the timer and service, installs atomically, reloads systemd, and restores the backup if installation fails. Neither script stops GNU screen or Codex.

## Known limitations

- The watcher supports GNU screen, not tmux, in v0.1.0.
- Codex TUI changes may require detection updates.
- Replace-goal dialogs are detected and blocked, never confirmed.
- Terminal observation cannot prove that Codex accepted a keystroke, so a follow-up verification is always required.

## Contributing

Run `make lint` and `make test` before opening a change. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Support the project

This project is independently developed and provided free of charge. Voluntary support helps cover infrastructure, servers, domains, testing, maintenance and continued development.

- [PayPal](https://paypal.me/CoYoDuDe)
- [Buy Me a Coffee](https://www.buymeacoffee.com/CoYoDuDe)
- [More projects and information](https://dnsmith.net/)

Support is entirely voluntary. There is no subscription requirement, and support does not create an entitlement to specific features or personal support.

## License

MIT. See [LICENSE](LICENSE).
