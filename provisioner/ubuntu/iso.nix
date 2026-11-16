{ pkgs, ... }:
let
  isoName = "ubuntu-26.04.1-live-server-amd64.iso";
  isoUrl = "https://releases.ubuntu.com/26.04.1/${isoName}";
  isoSha256 = "cc8a95cde20f6ced61a322420de00f10cc3c90ced545daa46cb9c1a117f1d927";

  fetchIso = pkgs.writeShellScript "ubuntu-iso-fetch" ''
    set -euo pipefail

    state_dir="/var/lib/ubuntu-images"
    target="$state_dir/${isoName}"

    # Reuse only files that match the pinned checksum.
    if [ -f "$target" ] && printf '%s  %s\n' "${isoSha256}" "$target" | ${pkgs.coreutils}/bin/sha256sum --check --status; then
      ${pkgs.coreutils}/bin/chmod 0644 "$target"
      echo "Verified ISO already exists: $target"
      exit 0
    fi

    # Download to the same filesystem to allow atomic publication.
    tmp="$("${pkgs.coreutils}/bin/mktemp" --tmpdir="$state_dir" ".${isoName}.XXXXXX")"
    trap '${pkgs.coreutils}/bin/rm -f "$tmp"' EXIT

    echo "Downloading ${isoUrl}"
    ${pkgs.curl}/bin/curl --fail --location --retry 3 --output "$tmp" "${isoUrl}"

    printf '%s  %s\n' "${isoSha256}" "$tmp" | ${pkgs.coreutils}/bin/sha256sum --check --status || {
      echo "ISO SHA256 mismatch" >&2
      exit 1
    }

    ${pkgs.coreutils}/bin/chmod 0644 "$tmp"
    ${pkgs.coreutils}/bin/mv -f "$tmp" "$target"
    echo "Verified ISO saved: $target"
  '';
in
{
  # Fix permissions on an ISO fetched before HTTP delivery was enabled.
  systemd.tmpfiles.rules = [
    "z /var/lib/ubuntu-images/ubuntu-26.04.1-live-server-amd64.iso 0644 root root -"
  ];

  # Manual only: no wantedBy or timer.
  systemd.services.ubuntu-iso-fetch = {
    description = "Fetch and verify Ubuntu Server 26.04.1 ISO";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];

    serviceConfig = {
      Type = "oneshot";
      StateDirectory = "ubuntu-images";
      ExecStart = fetchIso;
    };
  };
}
