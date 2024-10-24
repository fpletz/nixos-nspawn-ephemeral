# Declarative ephemeral NixOS nspawn containers

This is a work in progress proof of concept for a simple alternative to NixOS containers. It
contains NixOS modules for a host machine and a container to run declarative NixOS nspawn
containers.

Imperative containers are not in scope of this project since it is the author's opinion that those
are the main issue holding back the upstream NixOS container migration to proper systemd-nspawn
support. Imperative containers need a separate state outside of the NixOS module system and
therefore a tool to manage that state. The author suggests importing the official container tarball
and using the regular imperative NixOS deployment options instead.

## Highlights

* first-class integration into `machinectl`
  * `-M` flag for `systemctl` and `loginctl` works as intended
  * uses systemd's `systemd-nspawn@.service` unit
* automatic network configuration using `systemd-networkd`
* user namespaces with dynamic UID/GID allocation
* ephemeral execution so no state is being kept across restarts
  * if state is needed, bind mounts can be defined in the nspawn configuration

## TODO

* the whole host nix store is being bind mounted into the container
  * explore if only needed store paths could be bind mounted instead
  * maybe create an option to make a separate nix daemon instance available in the container
* explore how to pass credentials into the container and provide an interface

## How to use this

You can consume this flake and use the provided NixOS modules. See the `simple-container` check
in `checks.nix` for an example. If you are not using flakes, the NixOS modules are located in
`host.nix` and `container.nix`.

### Examples

Simple container called `mycontainer` running plain NixOS:

```nix
{
  # import the module on the host
  imports = [
    # with flakes
    inputs.nixos-nspawn-ephemeral.nixosModules.host
    # OR
    # without flakes
    "${builtins.fetchTarball "https://github.com/fpletz/nixos-nspawn-ephemeral/archive/main.tar.gz"}/host.nix"
  ];

  virtualisation.nixos-nspawn-ephemeral.containers = {
    mycontainer = { };
  };
}
```

The following NixOS configuration creates a container host with an nginx configured to reverse proxy
to a container named `backend` with another nginx instance.

```nix
{
  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    virtualHosts."default".locations."/".proxyPass = "http://backend";
  };

  virtualisation.nixos-nspawn-ephemeral.containers = {
    backend = {
      config = {
        networking.firewall.allowedTCPPorts = [ 80 ];
        services.nginx = {
          enable = true;
          virtualHosts."backend".locations."/".return = ''200 "hack the planet"'';
        };
      };
    };
  };
}
```

Static network configuration is also possible:

```nix
{
  virtualisation.nixos-nspawn-ephemeral.containers = {
    testcontainer = {
      config = { };
      network.veth.config = {
        # networkd network unit configs for host and container side
        host = {
          networkConfig.Address = [
            "fc42::1/64"
            "192.168.42.1/24"
          ];
        };
        container = {
          networkConfig = {
            Address = [
              "fc42::2/64"
              "192.168.42.2/24"
            ];
            Gateway = [
              "fc42::1"
              "192.168.42.1"
            ];
          };
        };
      };
    };
  };
}
```
