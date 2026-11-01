{ pkgs, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./network-local.nix
    ./boot-local.nix
  ];

  networking.hostName = "c0";
  networking.useDHCP = false;
  networking.wireless.enable = false;

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish.enable = true;
    publish.addresses = true;
  };

  # Keep laptop-based servers running when the lid is closed.
  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchDocked = "ignore";
  };

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  users.mutableUsers = false;
  users.users.user1 = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    hashedPassword = "!";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJMCfnXI3s2GGGdga46YqpBAw2sge9enT27ZCvVh8A73 Air"
    ];
  };
  security.sudo.wheelNeedsPassword = false;

  # Allow dynamically linked binaries such as VS Code Server to run on NixOS.
  programs.nix-ld.enable = true;

  environment.systemPackages = with pkgs; [ git curl vim ];
  networking.firewall.allowedTCPPorts = [ 22 ];

  system.stateVersion = "26.05";
}
