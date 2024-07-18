{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.virtualisation.nixos-nspawn-ephemeral;

  containerModule = lib.types.submodule (
    {
      config,
      options,
      name,
      ...
    }:
    {
      options = {
        config = lib.mkOption {
          description = ''
            A specification of the desired configuration of this
            container, as a NixOS module.
          '';
          type = lib.mkOptionType {
            name = "Toplevel NixOS config";
            merge =
              loc: defs:
              (import "${toString pkgs.path}/nixos/lib/eval-config.nix" {
                modules = [
                  {
                    networking.hostName = lib.mkDefault name;
                    nixpkgs.hostPlatform = lib.mkDefault pkgs.system;
                  }
                  ./container.nix
                ] ++ (map (x: x.value) defs);
                prefix = [
                  "containers"
                  name
                ];
                system = null;
              }).config;
          };
        };

        path = lib.mkOption {
          type = lib.types.path;
          example = "/nix/var/nix/profiles/per-container/webserver";
          description = ''
            As an alternative to specifying
            {option}`config`, you can specify the path to
            the evaluated NixOS system configuration, typically a
            symlink to a system profile.
          '';
        };
      };

      config = {
        path = lib.mkIf options.config.isDefined config.config.system.build.toplevel;
      };
    }
  );
in
{
  options = {
    virtualisation.nixos-nspawn-ephemeral = {
      containers = lib.mkOption { type = lib.types.attrsOf containerModule; };
    };
  };

  config = {
    networking = {
      useNetworkd = true;
      firewall.interfaces."ve-+" = {
        # allow DHCP
        allowedUDPPorts = [ 67 ];
      };
    };

    systemd.nspawn = lib.flip lib.mapAttrs cfg.containers (
      name: containerCfg: {
        execConfig = {
          Ephemeral = true;
          Boot = false;
          PrivateUsers = true;
          Parameters = "${containerCfg.path}/init";
        };
        filesConfig = {
          BindReadOnly = "/nix/store";
        };
        networkConfig = {
          Private = true;
          VirtualEthernet = true;
        };
      }
    );

    systemd.services."systemd-nspawn@" = {
      # systemd-nspawn needs this dummy image directory even though the machine is executed ephemerally
      serviceConfig.ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p /var/lib/machines/%i";
    };

    # Run declared containers at boot
    systemd.targets.machines.wants = lib.mapAttrsToList (
      name: _: "systemd-nspawn@${name}.service"
    ) cfg.containers;
  };
}
