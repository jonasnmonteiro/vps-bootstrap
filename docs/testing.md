# Testing

Hardening scripts can lock you out of a real server, so nothing here is ever tried first on a server
you care about. Each layer below is cheaper than the next one and catches a different class of
problem.

| Layer | Needs | Catches | Cannot catch |
|---|---|---|---|
| Lint and style | ShellCheck, Perl | Shell mistakes, comments, dashes, emojis | Anything at runtime |
| Container | Docker | Real package installs, sshd, UFW, fail2ban, journald, cloud-init traps, idempotency, SSH logins | Swap, NTP, IPv6 (depending on Docker), reboots |
| VM | Multipass or UTM | Everything the server itself controls, including a reboot | The provider's network firewall |
| Throwaway VPS | A provider account | Everything, including checks from the internet | Nothing, but it costs money |

## Lint and style

```
brew install shellcheck
make lint
make check-style
```

## Container test

```
make test-container
```

The test:

1. Builds an Ubuntu 24.04 image with systemd as PID 1 (`tests/container/Dockerfile`).
2. Starts it privileged, so systemd, sshd, UFW and fail2ban work inside it.
3. Recreates the defaults of a cloud image with `tests/fixtures/cloud-image.sh`: an `ubuntu` account
   with a password and passwordless sudo, `50-cloud-init.conf` turning password login on,
   `preserve_hostname: false` and a test key for root.
4. Confirms that password login is on, so the test starts from the real trap.
5. Runs `--dry-run` and confirms that nothing changed.
6. Runs `--auto`, which also runs `checks/verify.sh`.
7. Runs `--auto` again and requires `No changes needed`.
8. Logs in over SSH with the key as the admin user and as root, and confirms that a login without a
   key ends in `Permission denied (publickey)`.

Swap, swappiness and NTP belong to the host kernel, so the modules and checks detect the container
and report them as skipped. IPv6 rule checks are skipped when the container has no IPv6.

On macOS this runs on Docker Desktop, OrbStack or Colima. Useful variables:

| Variable | Effect |
|---|---|
| `KEEP=1` | Keep the container after the test, to inspect it with `docker exec -it vps-bootstrap-test bash` |
| `SKIP_BUILD=1` | Reuse the image from the previous run |
| `BASE_IMAGE=...` | Build on another base image |

## VM test with Multipass

Multipass creates Ubuntu VMs with one command, on Intel and Apple Silicon Macs.

```
brew install --cask multipass
make test-vm
```

The test launches a fresh Ubuntu 24.04 VM, copies the project, runs a dry run, a first run and a
second run that must change nothing, then reboots the VM and runs `checks/verify.sh` again. After
the reboot the journal must list more than one boot, and swap, hostname, firewall and SSH settings
must still be in place. Finally it tries a password login from your Mac and probes ports 22, 80, 443
and 8080 from outside the VM.

`KEEP=1 make test-vm` keeps the VM. Open a shell with `multipass shell vps-bootstrap-test` and remove
it with `multipass delete --purge vps-bootstrap-test`.

The test uses the VM's `ubuntu` account as the admin user, because Multipass itself logs in with it.

## VM test with UTM

UTM is useful when you want to follow the whole manual process by hand, including the SSH key
steps from the checklist in the README.

1. Download the Ubuntu Server 24.04 image for your Mac's architecture (ARM64 on Apple Silicon).
2. Create a VM in UTM with the QEMU backend, 2 CPUs, 2 GB of memory and a 10 GB disk. Choose a
   bridged or shared network so your Mac can reach it.
3. Install Ubuntu with OpenSSH enabled and shut the VM down.
4. Right click the VM and choose "Run without saving changes". Every session then starts from the
   clean install, like a new VPS.
5. From your Mac, install your key and copy the project:

   ```
   ssh-copy-id -i ~/.ssh/<key>.pub <user>@<vm ip>
   scp -r . <user>@<vm ip>:vps-bootstrap
   ```

6. On the VM, run `sudo ./bootstrap.sh --dry-run`, then `sudo ./bootstrap.sh`, reboot and run
   `sudo ./checks/verify.sh`.
7. From the Mac, run the checks in "After the run" in the README.

In this mode a reboot from inside the VM keeps your changes, and stopping the VM in UTM discards
them. Stop it to get a clean server again.

## Throwaway VPS

The last layer is a real server billed by the hour. Create it, run the checklist and the bootstrap
exactly as you would in production, check it from outside, and delete it. This is the only layer
that tests the provider's firewall and what the internet actually sees.

## CI

`.github/workflows/ci.yml` runs lint and style on every push and pull request, then the container
test on a GitHub hosted Ubuntu 24.04 runner.
