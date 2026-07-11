# Security model

The project treats terminal output as untrusted input. It strips ANSI/OSC sequences, NULs, CRs, and backspaces centrally, then accepts only a narrow set of strings. No terminal text is evaluated as shell code.

An action requires all of: current-looking limit text, paused-goal text, a strictly parsed reset time, a release time after grace, a known composer, a matching session/window fingerprint, and the global lock. A fresh hardcopy is taken immediately before key delivery. Hidden paste text has no inspectable content and needs a one-time session-bound `arm-enter` permission.

Screen delivery is not application confirmation. The watch state stays in `RESUME_SENT` or `VERIFYING_RESUME` until a later read changes the visible state. Persistent limits enter a retry delay and stop at `MAX_ATTEMPTS`. Changing a fingerprint starts a separate event; stale state cannot target a new PID or window because identity is part of the fingerprint.

The project never confirms replace-goal dialogs in v0.1.0.
