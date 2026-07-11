# Changelog

## 0.1.1 - 2026-07-12

- Recognize screen-wrapped `try again at` messages.
- Recognize documented empty Codex composer placeholders below a paused-goal footer.
- Interpret a late-night reset time correctly shortly after midnight.

## 0.1.0 - 2026-07-11

- Initial public release.
- Fail-closed Codex goal resume detection for GNU screen.
- Multiple registered sessions, per-session state, global lock, priority selection, one action per timer pass, and global cooldown.
- Safe installer, updater, migration, uninstaller, Bats tests, and CI.
