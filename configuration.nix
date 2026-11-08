{ config, lib, pkgs, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./network-local.nix
    ./boot-local.nix
    ./ubuntu-iso.nix
    ./ubuntu-http.nix
    ./ubuntu-pxe.nix
  ];

  options.myHost = {
    primaryEthernet = lib.mkOption {
      type = lib.types.str;
      description = "Primary wired Ethernet interface detected at installation";
    };
    bootMode = lib.mkOption {
      type = lib.types.enum [ "bios" "uefi" ];
      description = "Firmware boot mode detected at installation";
    };
    bootDisk = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Disk used by GRUB for legacy BIOS boot";
    };
  };

  config = {
    assertions = [
      {
        assertion = config.myHost.bootMode != "bios" || config.myHost.bootDisk != null;
        message = "myHost.bootDisk must be set for BIOS boot";
      }
    ];

    networking.hostName = "c0";
    networking.useDHCP = false;
    networking.wireless.enable = false;
    networking.interfaces.${config.myHost.primaryEthernet} = {
      useDHCP = true;
      wakeOnLan.enable = true;
    };

    # Disko derives GRUB's install devices from disko.devices.
    # Do not specify boot.loader.grub.device here: that duplicates the device.
    boot.loader.grub.enable = config.myHost.bootMode == "bios";
    boot.loader.systemd-boot.enable = config.myHost.bootMode == "uefi";
    boot.loader.efi.canTouchEfiVariables = config.myHost.bootMode == "uefi";

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
  };
}
