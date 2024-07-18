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
          # We're running our own init from the system path.
          Boot = false;
          Parameters = "${containerCfg.path}/init";
          # Pick a free UID/GID range and apply user namespace isolation.
          PrivateUsers = "pick";
          # Place the journal on the host to make it persistent
          LinkJournal = "try-host";
        };
        filesConfig = {
          # This chowns the directory /var/lib/machines/${name} to ensure that
          # always same UID/GID mapping range is used. Since the directory is
          # empty the operation is fast and only happens on first boot.
          PrivateUsersOwnership = "chown";
          # The nix store must be available in the container to run binaries
          BindReadOnly = "/nix/store";
        };
        networkConfig = {
          # XXX: Do want want to support host networking?
          Private = true;
          VirtualEthernet = true;
        };
      }
    );

    systemd.services."systemd-nspawn@" = {
      # We this dummy image directory because systemd-nspawn fails otherwise and it persists
      # the UID/GID mapping for user namespaces.
      serviceConfig.ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p /var/lib/machines/%i";
    };

    # Activate the container units with machines.target
    systemd.targets.machines.wants = lib.mapAttrsToList (
      name: _: "systemd-nspawn@${name}.service"
    ) cfg.containers;

    # XXX: This is basically a copy of upstream's systemd-nspawn@.service for experimentation
    # systemd.services = lib.flip lib.mapAttrs' cfg.containers (
    #   name: conf:
    #   lib.nameValuePair "nixos-nspawn-${name}" {
    #     description = "NixOS nspawn container ${name}";
    #     partOf = [ "machines.target" ];
    #     before = [ "machines.target" ];
    #     after = [ "network.target" ];
    #     wantedBy = [ "machines.target" ];
    #     unitConfig = {
    #       RequiresMountsFor = "/var/lib/machines/${name}";
    #     };
    #     serviceConfig = {
    #       ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p /var/lib/machines/${name}";
    #       ExecStart = "${pkgs.systemd}/bin/systemd-nspawn --quiet --keep-unit --settings=override --machine=${name}";
    #       KillMode = "mixed";
    #       Type = "notify";
    #       RestartForceExitStatus = 133;
    #       SuccessExitStatus = 133;
    #       Slice = "machine.slice";
    #       Delegate = true;
    #       DelegateSubgroup = "supervisor";
    #       TasksMax = 16384;
    #       WatchdogSec = "3min";
    #       DevicePolicy = "closed";
    #       DeviceAllow = [ "char-pts rw" ];
    #     };
    #   }
    # );
  };
}
