{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.nixos-nspawn;

  containerVdevNetwork = {
    matchConfig = {
      Kind = "veth";
      Name = "host0";
      Virtualization = "container";
    };
    networkConfig = {
      DHCP = lib.mkDefault true;
      LinkLocalAddressing = lib.mkDefault true;
      LLDP = true;
      EmitLLDP = "customer-bridge";
      IPv6DuplicateAddressDetection = lib.mkDefault 0;
      IPv6AcceptRA = lib.mkDefault true;
      MulticastDNS = true;
    };
  };

  hostVdevNetwork = name: {
    matchConfig = {
      Kind = "veth";
      Name = "ve-${name}";
    };
    networkConfig = {
      Address = lib.mkDefault [
        "0.0.0.0/30"
        "::/64"
      ];
      DHCPServer = lib.mkDefault true;
      IPMasquerade = lib.mkDefault "both";
      LinkLocalAddressing = lib.mkDefault true;
      LLDP = true;
      EmitLLDP = "customer-bridge";
      IPv6DuplicateAddressDetection = lib.mkDefault 0;
      IPv6AcceptRA = lib.mkDefault false;
      IPv6SendRA = lib.mkDefault true;
      MulticastDNS = true;
    };
  };

  containerModule = lib.types.submodule (
    {
      config,
      options,
      name,
      ...
    }:
    {
      options = {
        autoStart = lib.mkOption {
          description = ''
            Whether to start the container by default with machines.target.
          '';
          type = lib.types.bool;
          default = true;
          example = false;
        };

        config = lib.mkOption {
          description = ''
            A specification of the desired configuration of this
            container, as a NixOS module.
          '';
          example = lib.literalExpression ''
            { pkgs, ... }: {
              networking.hostName = "foobar";
              services.openssh.enable = true;
              environment.systemPackages = [ pkgs.htop ];
            }'';
          type = lib.mkOptionType {
            name = "Toplevel NixOS config";
            merge =
              _loc: defs:
              (import "${toString pkgs.path}/nixos/lib/eval-config.nix" {
                modules =
                  [
                    ./container.nix
                    {
                      networking.hostName = lib.mkDefault name;
                      nixpkgs.hostPlatform = lib.mkDefault pkgs.system;

                      networking.firewall.interfaces."host0" = {
                        allowedTCPPorts = [
                          5353 # MDNS
                        ];
                        allowedUDPPorts = [
                          5353 # MDNS
                        ];
                      };

                      systemd.network.networks."10-container-host0" =
                        let
                          veth = config.network.veth;
                          customConfig = if veth.config.container != null then veth.config.container else { };
                        in
                        lib.mkIf veth.enable (
                          lib.mkMerge [
                            containerVdevNetwork
                            customConfig
                          ]
                        );
                    }
                  ]
                  ++ cfg.imports
                  ++ (map (x: x.value) defs);
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
          example = "/nix/var/nix/profiles/my-container";
          description = ''
            As an alternative to specifying
            {option}`config`, you can specify the path to
            the evaluated NixOS system configuration, typically a
            symlink to a system profile.
          '';
        };

        network.veth = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            example = false;
            description = ''
              Enable default veth link between host and container.
            '';
          };

          config.host = lib.mkOption {
            type = lib.types.nullOr lib.types.attrs;
            description = ''
              Networkd network config merged with the systemd.network.networks
              unit on the **host** side. Interface match config is already
              prepopulated.
            '';
            default = null;
            example = {
              networkConfig.Address = [
                "fd42::1/64"
                "10.23.42.1/28"
              ];
            };
          };

          config.container = lib.mkOption {
            type = lib.types.nullOr lib.types.attrs;
            description = ''
              Networkd network config merged with the systemd.network.networks unit
              on the **container** side. Interface match config is already
              prepopulated.
            '';
            default = null;
            example = {
              networkConfig.Address = [
                "fd42::2/64"
                "10.23.42.2/28"
              ];
            };
          };
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
    nixos-nspawn = {
      containers = lib.mkOption {
        type = lib.types.attrsOf containerModule;
        default = { };
        example = lib.literalExpression ''
          {
            webserver = {
              config = {
                networking.firewall.allowedTCPPorts = [ 80 ];
                services.nginx.enable = true;
              };
            };
          }'';
        description = ''
          Attribute set of containers that are configured by this module.
        '';
      };

      imports = lib.mkOption {
        type = lib.types.listOf lib.types.deferredModule;
        default = [ ];
        example = lib.literalExpression ''
          [
            { services.getty.helpLine = "Hello world! I'm a nspawn container!"; }
            inputs.lix-module.nixosModules.default
          ]'';
        description = ''
          List of NixOS modules to be imported in every system evaluation when
          {option}`containers.*.config` is being used.
        '';
      };
    };
  };

  config = lib.mkIf (lib.length (lib.attrNames cfg.containers) > 0) {
    networking = {
      useNetworkd = true;
      firewall.interfaces."ve-+" = {
        allowedTCPPorts = [
          5353 # MDNS
        ];
        allowedUDPPorts = [
          67 # DHCP
          5353 # MDNS
        ];
      };
    };

    systemd.network.networks = lib.flip lib.mapAttrs' cfg.containers (
      name: containerCfg:
      lib.nameValuePair "10-ve-${name}" (
        let
          veth = containerCfg.network.veth;
          customConfig = if veth.config.host != null then veth.config.host else { };
        in
        lib.mkIf veth.enable (
          lib.mkMerge [
            (hostVdevNetwork name)
            customConfig
          ]
        )
      )
    );

    systemd.nspawn = lib.flip lib.mapAttrs cfg.containers (
      _name: containerCfg: {
        execConfig = {
          Ephemeral = true;
          # We're running our own init from the system path.
          Boot = false;
          Parameters = "${containerCfg.path}/init";
          # Pick a free UID/GID range and apply user namespace isolation.
          PrivateUsers = "pick";
          # Place the journal on the host to make it persistent
          LinkJournal = "try-host";
          # NixOS config takes care of the timezone
          Timezone = "off";
        };
        filesConfig = {
          # This chowns the directory /var/lib/machines/${name} to ensure that
          # always same UID/GID mapping range is used. Since the directory is
          # empty the operation is fast and only happens on first boot.
          PrivateUsersOwnership = "chown";
          # The nix store must be available in the container to run binaries
          # FIXME: This should be mounted with an idmap so the nix store is
          # owned by root. Setting an idmap fails for some reason, though.
          # Due to this, logrotate currently fails because it requires
          # configuration files to be owned by root. See container.nix.
          BindReadOnly = [ "/nix/store:/nix/store:noidmap" ];
        };
        networkConfig = {
          # XXX: Do want want to support host networking?
          Private = true;
          VirtualEthernet = containerCfg.network.veth.enable;
        };
      }
    );

    # We create this dummy image directory because systemd-nspawn fails otherwise.
    # Additionally, it persists the UID/GID mapping for user namespaces.
    systemd.tmpfiles.settings."10-nixos-nspawn" = lib.mapAttrs' (
      name: _: lib.nameValuePair "/var/lib/machines/${name}" { d = { }; }
    ) cfg.containers;

    # Activate the container units with machines.target
    systemd.targets.machines.wants = lib.mapAttrsToList (name: _: "systemd-nspawn@${name}.service") (
      lib.filterAttrs (_n: c: c.autoStart) cfg.containers
    );

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
