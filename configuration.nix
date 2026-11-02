{ config, lib, pkgs, ... }:
let
  # The bootstrap-generated network-local.nix enables DHCP on the wired NIC.
  dhcpInterfaces = lib.attrNames (
    lib.filterAttrs (_: interface: interface.useDHCP) config.networking.interfaces
  );
in
{
  imports = [
    ./hardware-configuration.nix
    ./network-local.nix
    ./boot-local.nix
  ];

  networking.hostName = "c0";
  networking.useDHCP = false;
  networking.wireless.enable = false;

  # Apply the common WoL policy to the machine's bootstrap-selected wired NIC.
  # Derive its name from network-local.nix without hard-coding it here.
  assertions = [
    {
      assertion = builtins.length dhcpInterfaces == 1;
      message = "Expected exactly one DHCP-enabled interface for Wake-on-LAN.";
    }
  ];

  systemd.services.enable-wol = lib.mkIf (builtins.length dhcpInterfaces == 1) {
    description = "Enable magic-packet Wake-on-LAN on the wired NIC";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-pre.target" ];
    before = [ "network.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.ethtool}/bin/ethtool -s ${builtins.head dhcpInterfaces} wol g";
    };
  };

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
