# Ubuntu worker configuration with Ansible

The controller `c0` uses a dedicated worker-management key pair owned by `user1`:
`/home/user1/.ssh/id_ed25519_provisioner` (private) and `id_ed25519_provisioner.pub` (public).
The `provisioner-ssh-keygen.service` systemd unit creates it once at boot or on explicit start.
It never overwrites an existing private key. A missing public key is recovered from the private key; if only the public key remains, the unit fails to avoid silently rotating the identity.

After applying the NixOS configuration, run on c0:

```sh
sudo systemctl start provisioner-ssh-keygen.service
systemctl status provisioner-ssh-keygen.service
ls -l /home/user1/.ssh/id_ed25519_provisioner*
```

Autoinstall embeds c0's public key at `sudo ubuntu-autoinstall-select HOSTNAME` time. The Git-managed `ssh/authorized_keys` file is **not** used for worker access anymore. Controller login authentication is unchanged.

## Apply to a newly provisioned worker

As `user1` on c0 (Ansible reads the private key specified in `ansible.cfg`):

```sh
cd /etc/nixos/worker/ubuntu/ansible
ansible-playbook -i 'k2.local,' playbook.yml --syntax-check
ansible -i 'k2.local,' all -m ansible.builtin.ping
ansible-playbook -i 'k2.local,' playbook.yml --check --diff
ansible-playbook -i 'k2.local,' playbook.yml --diff
ansible-playbook -i 'k2.local,' playbook.yml --diff
```

The trailing comma means a single-host Inventory. SSH host-key checking remains enabled; verify and trust the worker host key before connecting. Aim for `changed=0` after convergence; check mode cannot guarantee this.

## Existing Ubuntu workers: migration required

Previously provisioned Ubuntu workers received public keys from `ssh/authorized_keys` and do not yet authorize the new controller key. **Do not apply the exclusive authorized-key task before verifying access with the new identity.** With the *previously working private key* still available, add the new public key non-exclusively and verify its login:

```sh
ssh -i /path/to/old-private-key user1@k2.local \
  'umask 077; mkdir -p ~/.ssh; cat >> ~/.ssh/authorized_keys' \
  < /home/user1/.ssh/id_ed25519_provisioner.pub

ssh -i /home/user1/.ssh/id_ed25519_provisioner -o IdentitiesOnly=yes \
  user1@k2.local 'sudo -n true'
```

The append may produce duplicate entries if repeated, so check first. Once new-key login succeeds, run the Playbook; its `exclusive: true` setting removes other keys from the worker's `user1` account.

The role manages the admin user, password lock, key-only SSH, passwordless sudo, Avahi, chrony, Python, and existing WoL script/systemd service. It does not manage disk or DHCP settings. The `ansible.posix` collection is needed for `authorized_key`.

**Backups and rotation:** The controller private key is persistent host data, not part of the Flake or Git. Back it up securely before reinstalling c0. Rotating it requires adding the replacement key to existing workers before the previous key is retired.

## Verify

```sh
ssh -i ~/.ssh/id_ed25519_provisioner user1@k2.local 'sudo -n true && systemctl is-active ssh avahi-daemon chrony enable-wol'
ssh -i ~/.ssh/id_ed25519_provisioner user1@k2.local 'hostnamectl; timedatectl'
```

Automatic installation completion detection and the `provision` CLI are out of scope.
