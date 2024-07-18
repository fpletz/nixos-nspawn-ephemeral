{
  description = "Declarative ephemeral NixOS nspawn containers";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        nixpkgs-stable.follows = "nixpkgs";
      };
    };
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      imports = [
        inputs.treefmt-nix.flakeModule
        inputs.git-hooks.flakeModule
        ./checks.nix
      ];

      flake.nixosModules = rec {
        default = host;
        container = import ./container.nix;
        host = import ./host.nix;
      };

      perSystem =
        { pkgs, config, ... }:
        {
          formatter = pkgs.nixfmt-rfc-style;

          devShells.default = pkgs.mkShellNoCC {
            packages = [ pkgs.nix-fast-build ];

            inputsFrom = [
              config.treefmt.build.devShell
              config.pre-commit.devShell
            ];
          };

          treefmt = {
            projectRootFile = "flake.lock";
            programs = {
              deadnix.enable = true;
              nixfmt-rfc-style.enable = true;
            };
          };

          pre-commit.settings.hooks = {
            treefmt.enable = true;
          };
        };
    };
}
