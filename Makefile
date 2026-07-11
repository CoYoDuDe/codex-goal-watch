.PHONY: test lint install uninstall

test:
	@bash -n bin/codex-goal-watch
	@find lib/codex-goal-watch -name '*.sh' -print0 | xargs -0 -r -n1 bash -n
	@python3 -m py_compile lib/codex-goal-watch/*.py
	@bats tests

lint:
	@shellcheck -e SC1091 bin/codex-goal-watch lib/codex-goal-watch/*.sh scripts/*.sh
	@shfmt -d -i 2 -ci bin/codex-goal-watch lib/codex-goal-watch/*.sh scripts/*.sh tests/helpers/bin/*

install:
	@sudo ./scripts/install.sh --enable

uninstall:
	@sudo ./scripts/uninstall.sh --non-interactive
