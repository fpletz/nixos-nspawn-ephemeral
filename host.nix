{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.virtualisation.nixos-nspawn-ephemeral;
in
{
  options = {
    virtualisation.nixos-nspawn-ephemeral = {
      containers = lib.mkOption { type = lib.types.attrs; };
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
      name: container: {
        execConfig = {
          Ephemeral = true;
          Boot = false;
          PrivateUsers = true;
          Parameters = "${container.config.system.build.toplevel}/init";
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
