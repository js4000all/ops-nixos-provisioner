{ config, ... }:
{
  # Actual device is generated into boot-local.nix on the target machine.
  # Disko also generates fileSystems from this same declaration.
  disko.devices.disk.main = {
    type = "disk";
    device = config.myHost.bootDisk;
    content = {
      type = "gpt";
      partitions =
        if config.myHost.bootMode == "uefi" then {
          ESP = {
            size = "1G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };
          root = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
            };
          };
        } else {
          bios = {
            size = "2M";
            type = "EF02";
          };
          root = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
            };
          };
        };
    };
  };
}
