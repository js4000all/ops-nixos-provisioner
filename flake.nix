{
  description = "NixOS provisioning for c0";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, disko, ... }: {
    nixosConfigurations.c0 = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        disko.nixosModules.disko
        ./disk-config.nix
      ];
    };

    # Use the exact disko input pinned by flake.lock during installation.
    packages.x86_64-linux.disko = disko.packages.x86_64-linux.disko;
  };
}
