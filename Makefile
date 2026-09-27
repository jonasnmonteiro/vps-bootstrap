SHELL_FILES := bootstrap.sh install.sh modules/*.sh checks/*.sh tests/*.sh tests/fixtures/*.sh

.PHONY: help lint test-container test-vm check-style record-demo

help:
	@echo "make lint             ShellCheck on every script"
	@echo "make check-style      Reject comments, em dashes and emojis"
	@echo "make record-demo      Record terminal demo animation with VHS"
	@echo "make test-container   Full run in a systemd container (Docker)"
	@echo "make test-vm          Full run, reboot and verification in a Multipass VM"

lint:
	shellcheck -x $(SHELL_FILES)

check-style:
	./tests/style.sh

record-demo:
	vhs docs/demo.tape

test-container:
	./tests/container.sh

test-vm:
	./tests/multipass.sh
