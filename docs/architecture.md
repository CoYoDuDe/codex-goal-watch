# Architecture

The command is a small Bash orchestrator. Python helpers have only two narrow, testable roles: byte-safe terminal cleanup/classification and timezone-aware time parsing. Configuration is never sourced as shell code.

`/etc/codex-goal-watch/sessions.d/*.conf` stores independent registrations. Each file contains the full screen identity, user, window selector, priority, and enabled flag. State is stored under `/var/lib/codex-goal-watch/sessions/<hash>/`; the hash prevents arbitrary screen names from becoming unsafe file paths. The global scheduler state is in `/var/lib/codex-goal-watch/global/`.

Each timer pass holds one non-blocking global `flock`. It analyzes every enabled registration without sending input, writes atomic per-session state, then selects at most one ready candidate by priority, waiting age, and stable session-name order. It re-reads the exact target before sending and records a verification deadline. A global cooldown is set only after a successful screen send call.

There is intentionally no v0.1.0 heuristic claiming to prove that another Codex session is "working". This cannot be reliably derived from a hardcopy. The conservative bound is one action per run plus global cooldown.
