{ lib, pkgs, ... }:
let
  keys = lib.filter (line: line != "" && !(lib.hasPrefix "#" line))
    (lib.splitString "\n" (builtins.readFile ./ssh/authorized_keys));
  yaml = pkgs.formats.yaml { };
  template = yaml.generate "ubuntu-autoinstall-template.yaml" {
    autoinstall = {
      version = 1;
      # Fully unattended: the selected disk is erased without confirmation.
      interactive-sections = [ ];
      shutdown = "reboot";
      locale = "en_US.UTF-8";
      keyboard = { layout = "jp"; variant = ""; };
      timezone = "Asia/Tokyo";
      storage.layout.name = "direct";
      ssh = { install-server = true; allow-pw = false; };
      packages = [ "avahi-daemon" "libnss-mdns" "chrony" "ethtool" ];
      user-data = {
        hostname = "__HOSTNAME__";
        preserve_hostname = false;
        manage_etc_hosts = true;
        disable_root = true;
        ssh_pwauth = false;
        users = [{
          name = "user1";
          groups = [ "adm" "sudo" ];
          shell = "/bin/bash";
          lock_passwd = true;
          sudo = "ALL=(ALL) NOPASSWD:ALL";
          ssh_authorized_keys = keys;
        }];
        write_files = [
          {
            path = "/etc/ssh/sshd_config.d/00-provisioner.conf";
            permissions = "0644";
            content = ''
              PasswordAuthentication no
              KbdInteractiveAuthentication no
              PermitRootLogin no
              PubkeyAuthentication yes
            '';
          }
          {
            path = "/usr/local/sbin/enable-wol";
            permissions = "0755";
            content = ''
              #!/bin/sh
              set -eu
              found=0
              for path in /sys/class/net/*; do
                nic="${path##*/}"
                [ "$nic" != lo ] || continue
                [ -e "$path/device" ] || continue
                [ ! -d "$path/wireless" ] && [ ! -e "$path/phy80211" ] || continue
                [ "$(cat "$path/type")" = 1 ] || continue
                found=1
                /usr/sbin/ethtool -s "$nic" wol g
              done
              [ "$found" -eq 1 ] || { echo "No physical wired NIC found" >&2; exit 1; }
            '';
          }
          {
            path = "/etc/systemd/system/enable-wol.service";
            permissions = "0644";
            content = ''
              [Unit]
              Description=Enable Wake-on-LAN on wired NICs
              After=network.target

              [Service]
              Type=oneshot
              ExecStart=/usr/local/sbin/enable-wol
              RemainAfterExit=yes

              [Install]
              WantedBy=multi-user.target
            '';
          }
        ];
        runcmd = [
          "passwd -l root"
          "systemctl enable --now avahi-daemon"
          "systemctl enable --now chrony"
          "systemctl restart ssh"
          "systemctl daemon-reload"
          "systemctl enable --now enable-wol.service"
        ];
      };
    };
  };
  selectHost = pkgs.writeShellScriptBin "ubuntu-autoinstall-select" ''
    set -euo pipefail
    if [ "$#" -ne 1 ]; then
      echo "Usage: sudo ubuntu-autoinstall-select HOSTNAME" >&2
      exit 2
    fi
    host="$1"
    if ! [[ "$host" =~ ^[a-z][a-z0-9-]{0,62}$ ]] || [[ "$host" == *- ]]; then
      echo "Invalid hostname (lowercase ASCII letters, digits and hyphens only)" >&2
      exit 2
    fi
    if [ "$(${pkgs.coreutils}/bin/id -u)" -ne 0 ]; then
      echo "Run with sudo" >&2
      exit 2
    fi
    dir="/var/lib/ubuntu-autoinstall"
    ${pkgs.coreutils}/bin/install -d -m 0755 "$dir"
    tmp="$(${pkgs.coreutils}/bin/mktemp "$dir/.user-data.XXXXXX")"
    trap '${pkgs.coreutils}/bin/rm -f "$tmp"' EXIT
    printf '#cloud-config\n' > "$tmp"
    ${pkgs.gnused}/bin/sed "s/__HOSTNAME__/$host/g" ${template} >> "$tmp"
    ${pkgs.coreutils}/bin/chmod 0644 "$tmp"
    ${pkgs.coreutils}/bin/mv -f "$tmp" "$dir/user-data"
    trap - EXIT
    printf 'instance-id: ubuntu-%s\nlocal-hostname: %s\n' "$host" "$host" > "$dir/.meta-data.tmp"
    ${pkgs.coreutils}/bin/chmod 0644 "$dir/.meta-data.tmp"
    ${pkgs.coreutils}/bin/mv -f "$dir/.meta-data.tmp" "$dir/meta-data"
    echo "Prepared unattended NoCloud seed for $host (disk will be erased without confirmation)"
  '';
in
{
  assertions = [{
    assertion = keys != [ ];
    message = "ssh/authorized_keys must contain at least one public SSH key";
  }];
  environment.systemPackages = [ selectHost ];
  systemd.tmpfiles.rules = [ "d /var/lib/ubuntu-autoinstall 0755 root root -" ];
  services.nginx.virtualHosts."_".locations = {
    "= /ubuntu/autoinstall/user-data".alias = "/var/lib/ubuntu-autoinstall/user-data";
    "= /ubuntu/autoinstall/meta-data".alias = "/var/lib/ubuntu-autoinstall/meta-data";
  };
}
