# Ubuntu worker configuration with Ansible

This playbook configures an already-installed Ubuntu worker. **It never installs or repartitions the OS.**
PXE, Autoinstall, and cloud-init remain unchanged in this stage.

## Prerequisites

- Controller `c0` has Ansible installed through its NixOS configuration.
- Worker was installed with the current Ubuntu Autoinstall (SSH public-key login for `user1`, passwordless sudo, Avahi/mDNS, and Python 3 available).
- The invoking account on `c0` has a private SSH key matching an entry in `ssh/authorized_keys`. Installing Ansible on `c0` does not itself provide that private key.
- The SSH host key has been verified/trusted. Host-key checking remains enabled.
- Controller resolves `k2.local` using mDNS.

From the repository root (`/etc/nixos` on c0):

```sh
cd worker/ubuntu/ansible
ansible-playbook -i 'k2.local,' playbook.yml --syntax-check
ansible -i 'k2.local,' all -m ansible.builtin.ping -u user1
ansible-playbook -i 'k2.local,' playbook.yml --check --diff
ansible-playbook -i 'k2.local,' playbook.yml --diff
ansible-playbook -i 'k2.local,' playbook.yml --diff
```

The trailing comma makes `k2.local,` a one-host Ansible inventory; no host-specific inventory file is committed. The final run should report `changed=0` once the target is converged. Check mode is advisory, not a replacement for a real apply.

To use a different SSH identity, use OpenSSH agent/config or Ansible's `--private-key` option. Never store private keys in this repository.

## Managed scope

- Packages: avahi-daemon, libnss-mdns, chrony, ethtool, openssh-server, python3.
- `user1`: membership in `adm` and `sudo`, password lock, keys from `ssh/authorized_keys`, passwordless sudo.
- SSH key-only policy in `/etc/ssh/sshd_config.d/00-provisioner.conf`.
- Existing `enable-wol` script and systemd service; enabled and running.
- `ssh`, `avahi-daemon`, and `chrony` enabled and running.

The common role is intentionally aligned with the current cloud-init configuration; it does not remove those bootstrap definitions yet. The role does not manage hostnames, disk layout, DHCP or global network policy. It uses `ansible.posix.authorized_key`, so the matching collection must be available in the controller's Ansible installation.

**Access note:** Authorized keys are managed exclusively from the shared public-key file. Review the desired key set before applying; keys added manually on a worker are removed. Check the existing controller SSH access before making changes.

## Verification on worker

```sh
ssh user1@k2.local 'sudo -n true && systemctl is-active ssh avahi-daemon chrony enable-wol'
ssh user1@k2.local 'hostnamectl; timedatectl'
```

WoL capability depends on the physical NIC; compare `sudo ethtool <interface>` output on the target if needed.

## Stage boundaries

Stage 2 validates the common Ansible role on an existing Ubuntu worker. Automatic post-install readiness detection and the `provision` CLI are separate later stages.
