SHELL_FILES := bootstrap.sh modules/*.sh checks/*.sh tests/*.sh tests/fixtures/*.sh

.PHONY: help lint test-container test-vm check-style

help:
	@echo "make lint             ShellCheck on every script"
	@echo "make check-style      Reject comments, em dashes and emojis"
	@echo "make test-container   Full run in a systemd container (Docker)"
	@echo "make test-vm          Full run, reboot and verification in a Multipass VM"

lint:
	shellcheck -x $(SHELL_FILES)

check-style:
	./tests/style.sh

test-container:
	./tests/container.sh

test-vm:
	./tests/multipass.sh
