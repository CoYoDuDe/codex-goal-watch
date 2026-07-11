# Contributing

Please keep changes fail-closed, add fixtures for new terminal variants, and never add real hardcopies, state files, logs, credentials, or private prompts.

Run `make lint` and `make test`. Changes that can send input require a mock test and must preserve the one-action global scheduler invariant.
