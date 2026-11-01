#!/usr/bin/env bash
set -Eeuo pipefail

REPO_URL="https://github.com/js4000all/ops-nixos-provisioner.git"
MIN_DISK_BYTES=$((64 * 1024 * 1024 * 1024))
WORKDIR="$(mktemp -d)"
trap 'echo "Installation failed at line $LINENO" >&2' ERR
trap 'rm -rf "$WORKDIR"' EXIT

log() { printf '[m1] %s\n' "$*"; }
die() { printf '[m1] ERROR: %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run as root (sudo bash install.sh)."
if [[ -d /sys/firmware/efi ]]; then
  boot_mode=uefi
else
  boot_mode=bios
fi
log "Detected boot mode: $boot_mode"
for cmd in git lsblk sgdisk partprobe udevadm mkfs.vfat mkfs.ext4 mount mountpoint nixos-generate-config nixos-install; do
  command -v "$cmd" >/dev/null || die "Required command missing: $cmd"
done
[[ ! -e /mnt/etc/nixos/configuration.nix ]] || die "/mnt appears to contain an existing installation."
mountpoint -q /mnt && die "/mnt is already mounted."

log "Fetching repository before changing disks..."
git clone --depth 1 "$REPO_URL" "$WORKDIR/repo" || die "Unable to fetch repository."
[[ -f "$WORKDIR/repo/configuration.nix" ]] || die "Missing configuration.nix."
git -C "$WORKDIR/repo" rev-parse HEAD | xargs printf '[m1] Repository revision: %s\n'

# Only a single non-USB, non-removable physical disk larger than 64 GiB is accepted.
disks=()
while IFS= read -r disk; do
  [[ -b "$disk" ]] || continue
  size="$(lsblk -bdn -o SIZE "$disk" | tr -d ' ')"
  transport="$(lsblk -dn -o TRAN "$disk" | tr -d ' ')"
  removable="$(lsblk -dn -o RM "$disk" | tr -d ' ')"
  [[ "$size" =~ ^[0-9]+$ ]] || die "Unknown disk size: $disk"
  (( size > MIN_DISK_BYTES )) || continue
  [[ "$transport" != usb ]] || continue
  [[ "$removable" == 0 ]] || continue
  disks+=("$disk")
done < <(lsblk -dn -o PATH,TYPE | awk '$2 == "disk" { print $1 }')
[[ "${#disks[@]}" -eq 1 ]] || die "Expected exactly one install disk; found ${#disks[@]}. Inspect lsblk."
disk="${disks[0]}"
log "Selected installation disk: $disk"

# Capture the single physical wired Ethernet interface; no name-based assumptions.
nics=()
for sysnet in /sys/class/net/*; do
  nic="${sysnet##*/}"
  [[ "$nic" != lo ]] || continue
  [[ -e "$sysnet/device" ]] || continue
  [[ ! -d "$sysnet/wireless" && ! -e "$sysnet/phy80211" ]] || continue
  [[ "$(cat "$sysnet/type")" == 1 ]] || continue
  nics+=("$nic")
done
[[ "${#nics[@]}" -eq 1 ]] || die "Expected exactly one physical wired NIC; found ${#nics[@]}."
nic="${nics[0]}"
[[ "$nic" =~ ^[a-zA-Z0-9_.-]+$ ]] || die "Unexpected interface name: $nic"
log "Selected wired NIC: $nic"

# Refuse to erase the disk providing the live installation environment.
while IFS= read -r source; do
  [[ -n "$source" && -b "$source" ]] || continue
  parent="$(lsblk -no PKNAME "$source" | head -n 1 | tr -d ' ')"
  [[ "$source" != "$disk" && "/dev/$parent" != "$disk" ]] || die "Selected disk appears to back a mounted filesystem."
done < <(findmnt -rn -o SOURCE)

log "ERASING ALL DATA on $disk"
sgdisk --zap-all "$disk"
if [[ "$boot_mode" == uefi ]]; then
  sgdisk -n 1:1MiB:+1GiB -t 1:ef00 -c 1:EFI "$disk"
else
  sgdisk -n 1:1MiB:+2MiB -t 1:ef02 -c 1:BIOS-BOOT "$disk"
fi
sgdisk -n 2:0:0 -t 2:8300 -c 2:nixos "$disk"
partprobe "$disk"
udevadm settle
boot_partition="$(lsblk -nr -o PATH,PARTN "$disk" | awk '$2 == 1 {print $1}')"
root="$(lsblk -nr -o PATH,PARTN "$disk" | awk '$2 == 2 {print $1}')"
[[ -b "$boot_partition" && -b "$root" ]] || die "Partition device discovery failed."
if [[ "$boot_mode" == uefi ]]; then
  mkfs.vfat -F 32 -n boot "$boot_partition"
fi
mkfs.ext4 -F -L nixos "$root"
mount -t ext4 "$root" /mnt
mkdir -p /mnt/etc/nixos
if [[ "$boot_mode" == uefi ]]; then
  mkdir -p /mnt/boot
  mount -o umask=077 "$boot_partition" /mnt/boot
fi

cp -a "$WORKDIR/repo/." /mnt/etc/nixos/
nixos-generate-config --root /mnt
cat > /mnt/etc/nixos/network-local.nix <<EOF
{ ... }: {
  networking.interfaces."${nic}".useDHCP = true;
}
EOF

if [[ "$boot_mode" == uefi ]]; then
  cat > /mnt/etc/nixos/boot-local.nix <<'EOF'
{ ... }: {
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
}
EOF
else
  cat > /mnt/etc/nixos/boot-local.nix <<EOF
{ ... }: {
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "$disk";
}
EOF
fi

log "Installing NixOS..."
nixos-install --no-root-passwd
log "Installation finished. Remove USB media and reboot manually."
