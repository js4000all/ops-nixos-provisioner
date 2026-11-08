{ pkgs, ... }:
let
  # This is a discovery-only seed: all installer sections remain interactive.
  # It must not include unattended storage directives.
  userData = pkgs.writeText "ubuntu-autoinstall-user-data" ''
    #cloud-config
    autoinstall:
      version: 1
      interactive-sections:
        - "*"
  '';
  metaData = pkgs.writeText "ubuntu-autoinstall-meta-data" "";
in
{
  # Serve only these two exact NoCloud seed endpoints.
  services.nginx.virtualHosts."_".locations = {
    "= /ubuntu/autoinstall/user-data".alias = userData;
    "= /ubuntu/autoinstall/meta-data".alias = metaData;
  };
}
