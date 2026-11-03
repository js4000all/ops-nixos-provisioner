#!/usr/bin/env bash
set -Eeuo pipefail

REPO_URL="https://github.com/js4000all/ops-nixos-provisioner.git"
REPO_REF="main"
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
for cmd in git lsblk findmnt mountpoint nix nixos-generate-config nixos-install; do
  command -v "$cmd" >/dev/null || die "Required command missing: $cmd"
done
[[ ! -e /mnt/etc/nixos/configuration.nix ]] || die "/mnt appears to contain an existing installation."
mountpoint -q /mnt && die "/mnt is already mounted."

log "Fetching repository branch $REPO_REF before changing disks..."
git clone --depth 1 --no-single-branch --branch "$REPO_REF" "$REPO_URL" "$WORKDIR/repo" || die "Unable to fetch repository."
for file in configuration.nix disk-config.nix flake.nix flake.lock; do
  [[ -f "$WORKDIR/repo/$file" ]] || die "Missing $file in $REPO_REF."
done
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

cat > "$WORKDIR/repo/network-local.nix" <<EOF
{ ... }: {
  myHost.primaryEthernet = "$nic";
}
EOF
cat > "$WORKDIR/repo/boot-local.nix" <<EOF
{ ... }: {
  myHost.bootMode = "$boot_mode";
  myHost.bootDisk = "$disk";
}
EOF

# Disko evaluates the whole NixOS module graph before filesystems exist.
# Replace this placeholder with detected hardware settings after mounting.
cat > "$WORKDIR/repo/hardware-configuration.nix" <<'EOF'
{ ... }: { }
EOF

flake="path:$WORKDIR/repo"
nix_flags=(--extra-experimental-features 'nix-command flakes')
log "Preparing disko from locked flake inputs..."
# Fail before destructive operations if the NixOS configuration cannot evaluate.
nix "${nix_flags[@]}" eval --raw "$flake#nixosConfigurations.c0.config.networking.hostName" >/dev/null

log "ERASING ALL DATA on $disk"
nix "${nix_flags[@]}" run "$flake#disko" -- \
  --mode destroy,format,mount --yes-wipe-all-disks --flake "$flake#c0"

log "Generating hardware configuration (without filesystem definitions)..."
nixos-generate-config --root /mnt --no-filesystems --show-hardware-config \
  > "$WORKDIR/repo/hardware-configuration.nix"

mkdir -p /mnt/etc/nixos
cp -a "$WORKDIR/repo/." /mnt/etc/nixos/

log "Installing NixOS from locked Flake configuration..."
nixos-install --flake "path:/mnt/etc/nixos#c0" --no-root-passwd
log "Installation finished. Remove USB media and reboot manually."
