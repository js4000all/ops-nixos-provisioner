{ pkgs, ... }:
{
  # Keep worker-management credentials out of Git and the Nix store.
  systemd.services.provisioner-ssh-keygen = {
    description = "Ensure controller SSH identity for worker provisioning";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "user1";
      Group = "users";
      UMask = "0077";
    };
    script = ''
      set -eu
      dir=/home/user1/.ssh
      key="$dir/id_ed25519_provisioner"
      ${pkgs.coreutils}/bin/install -d -m 0700 "$dir"

      if [ ! -e "$key" ]; then
        if [ -e "$key.pub" ]; then
          echo "Refusing to replace a missing private key while its public key remains" >&2
          exit 1
        fi
        ${pkgs.openssh}/bin/ssh-keygen -q -t ed25519 -N "" -C provisioner-c0 -f "$key"
      fi

      # Restore the public half without rotating the private identity.
      if [ ! -f "$key.pub" ]; then
        ${pkgs.openssh}/bin/ssh-keygen -y -f "$key" > "$key.pub.tmp"
        ${pkgs.coreutils}/bin/chmod 0644 "$key.pub.tmp"
        ${pkgs.coreutils}/bin/mv -f "$key.pub.tmp" "$key.pub"
      fi
    '';
  };
}
