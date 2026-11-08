{ config, pkgs, ... }:
let
  isoName = "ubuntu-26.04.1-live-server-amd64.iso";
  isoSha256 = "cc8a95cde20f6ced61a322420de00f10cc3c90ced545daa46cb9c1a117f1d927";
  isoPath = "/var/lib/ubuntu-images/${isoName}";
  bootDir = "/var/lib/ubuntu-pxe/current";

  prepareBoot = pkgs.writeShellScript "ubuntu-pxe-prepare" ''
    set -euo pipefail
    iso="${isoPath}"
    state_dir="/var/lib/ubuntu-pxe"
    boot_dir="${bootDir}"

    test -f "$iso" || { echo "ISO not found: $iso" >&2; exit 1; }
    printf '%s  %s\n' "${isoSha256}" "$iso" | ${pkgs.coreutils}/bin/sha256sum -c --status || {
      echo "ISO checksum verification failed" >&2
      exit 1
    }

    if [ -s "$boot_dir/vmlinuz" ] && [ -s "$boot_dir/initrd" ] &&
       [ -f "$boot_dir/iso.sha256" ] &&
       [ "$(${pkgs.coreutils}/bin/cat "$boot_dir/iso.sha256")" = "${isoSha256}" ]; then
      echo "Boot files already prepared"
      exit 0
    fi

    temp_dir="$(${pkgs.coreutils}/bin/mktemp -d "$state_dir/.staging.XXXXXX")"
    trap '${pkgs.coreutils}/bin/rm -rf "$temp_dir"' EXIT

    ${pkgs.libarchive}/bin/bsdtar -xOf "$iso" casper/vmlinuz > "$temp_dir/vmlinuz"
    ${pkgs.libarchive}/bin/bsdtar -xOf "$iso" casper/initrd > "$temp_dir/initrd"
    test -s "$temp_dir/vmlinuz" && test -s "$temp_dir/initrd"
    printf '%s\n' "${isoSha256}" > "$temp_dir/iso.sha256"

    ${pkgs.coreutils}/bin/rm -rf "$state_dir/previous"
    if [ -d "$boot_dir" ]; then
      ${pkgs.coreutils}/bin/mv "$boot_dir" "$state_dir/previous"
    fi
    ${pkgs.coreutils}/bin/mv "$temp_dir" "$boot_dir"
    echo "Ubuntu PXE kernel and initrd prepared: $boot_dir"
  '';

  runPixiecore = pkgs.writeShellScript "ubuntu-pxe-run" ''
    set -euo pipefail
    test -s "${bootDir}/vmlinuz" && test -s "${bootDir}/initrd" || {
      echo "Boot files missing; run ubuntu-pxe-prepare.service first" >&2
      exit 1
    }

    ip="$(${pkgs.iproute2}/bin/ip -4 -o addr show dev "${config.myHost.primaryEthernet}" scope global |
      ${pkgs.gawk}/bin/awk 'NR == 1 { split($4, address, "/"); print address[1] }')"
    test -n "$ip" || { echo "No IPv4 address on primary Ethernet" >&2; exit 1; }

    test -s /var/lib/ubuntu-autoinstall/user-data && test -f /var/lib/ubuntu-autoinstall/meta-data || {
      echo "NoCloud seed missing; run sudo ubuntu-autoinstall-select HOSTNAME before PXE" >&2
      exit 1
    }

    iso_url="http://$ip/ubuntu/${isoName}"
    seed_url="http://$ip/ubuntu/autoinstall/"
    echo "Starting Pixiecore, installer ISO: $iso_url; seed: $seed_url"
    exec ${pkgs.pixiecore}/bin/pixiecore boot \
      "${bootDir}/vmlinuz" "${bootDir}/initrd" \
      --cmdline "root=/dev/ram0 ramdisk_size=1500000 ip=dhcp url=$iso_url autoinstall ds=nocloud-net;s=$seed_url" \
      --dhcp-no-bind --port 64172 --status-port 64172
  '';
in
{
  systemd.services.ubuntu-pxe-prepare = {
    description = "Extract Ubuntu 26.04.1 PXE boot files from verified ISO";
    serviceConfig = {
      Type = "oneshot";
      StateDirectory = "ubuntu-pxe";
      ExecStart = prepareBoot;
    };
  };

  # Respond to PXE requests only during manual tests.
  systemd.services.ubuntu-pxe = {
    description = "Ubuntu 26.04.1 Legacy BIOS network boot (Pixiecore)";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" "nginx.service" ];
    requires = [ "nginx.service" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = runPixiecore;
    };
  };

  networking.firewall.allowedUDPPorts = [ 67 69 4011 ];
  networking.firewall.allowedTCPPorts = [ 64172 ];
}
