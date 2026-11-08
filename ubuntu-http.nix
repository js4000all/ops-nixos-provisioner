{ ... }:
{
  services.nginx = {
    enable = true;

    virtualHosts."_" = {
      default = true;

      # Expose only the pinned ISO, not the entire image directory.
      locations."= /ubuntu/ubuntu-26.04.1-live-server-amd64.iso" = {
        alias = "/var/lib/ubuntu-images/ubuntu-26.04.1-live-server-amd64.iso";
      };

      locations."/" = {
        return = "404";
      };
    };
  };

  networking.firewall.allowedTCPPorts = [ 80 ];
}
