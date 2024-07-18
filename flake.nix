{
  description = "Declarative ephemeral NixOS nspawn containers";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      imports = [ ./checks.nix ];

      flake.nixosModules = {
        container = import ./container.nix;
        host = import ./host.nix;
      };

      perSystem =
        { pkgs, ... }:
        {
          formatter = pkgs.nixfmt-rfc-style;
          devShells.default = pkgs.mkShell { packages = [ pkgs.nix-fast-build ]; };
        };
    };
}
