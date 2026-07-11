# Troubleshooting

Run these commands first:

```bash
codex-goal-watch doctor
codex-goal-watch list
codex-goal-watch inspect --all
codex-goal-watch status --all
journalctl -u codex-goal-watch.service -n 100 --no-pager
```

`SESSION_NOT_FOUND` means the registered full or short screen name no longer resolves for its configured user. Remove it and add the new session; a reused short name with a different PID is not trusted as the same event.

`BLOCKED_COMPOSER_UNCERTAIN`, `BLOCKED_UNKNOWN_INPUT`, and `BLOCKED_HIDDEN_PASTE` are safe stops, not failures to work around. Inspect the session yourself. Use `arm-enter NAME` only when you deliberately intend to submit the hidden draft once.

If no session is chosen with `auto`, restrict registration to an explicit window after read-only inspection. If several windows appear relevant, the watchdog refuses to guess. Use `reset-state NAME` after investigating a reached-attempt situation; it does not change configuration or screen.
