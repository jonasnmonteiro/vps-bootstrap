# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [1.0.0] (2026-09-23)

### Added

- `bootstrap.sh` with interactive selection, a plan that must be confirmed, `--auto`, `--dry-run`, `--only` and `--list`.
- Eleven idempotent modules: updates, cloud image account, admin user, SSH, UFW, fail2ban, journald, unattended upgrades, swap, time and hostname.
- `checks/verify.sh`, which checks the final state and exits non-zero on any failure.
- Container test that simulates a cloud image, runs everything twice and tests SSH logins.
- Multipass test that adds a reboot and checks from outside the VM.
- CI with ShellCheck, a style check and the container test.
