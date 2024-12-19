# Declarative NixOS nspawn containers

This is a work in progress proof of concept for a simple alternative to NixOS containers
with an opinionated minimal feature set.

The goal is to provide a minimal layer around systemd's existing nspawn facilities
and simple networking using networkd on both sides. In contrast to standard NixOS containers,
the containers are by design ephemeral. No state is being kept across restarts. Directories
can be bind mounted into the container if state is explicitly needed.

Imperative containers are not in scope of this project for now.

The idea is to upstream this either as a new module or a replacement for NixOS containers in
nixpkgs at some point.

## Use cases

* Run services in different network namespaces for custom routing
* Run multiple instances of a NixOS service on the same machine
* Provide more isolation by default than the systemd service hardening options between services on the same machine

## How it works

The project provides a NixOS module for a host machine that create nspawn units and uses
systemd's `systemd-nspawn@` service to launch the containers. Only the nix store is bind
mounted into the container and the nix daemon from the host is not passed into the container. 
User namespaces with dynamic UID/GID allocation are enabled by default.

### Networking

By default, a veth link is created between the host and the container and set up with networkd's
default DHCP-based configuration. Additionally, LinkLocalAddressing and MDNS are enabled by default.
The networkd network units can be overridden easily to configure custom networking instead.

### Operation

Most `machinectl` commands can be used to manage these declarative containers like `start`,
`stop`,`shell` and other commands not involving images work as expected. Using the `-M`
flags tools like `systemctl` or `journalctl` can access containers from the host.

## Open Issues

* the whole host nix store is being bind mounted into the container
  * explore if only needed store paths could be bind mounted instead
  * maybe create an option to make a separate nix daemon instance available in the container
* explore how to pass credentials into the container and provide an interface

## How to use this

You can consume this flake and use the provided NixOS modules. See the `simple-container` check
in `checks.nix` for an example. If you are not using flakes, the NixOS modules are located in
`host.nix` and `container.nix`.

### Example: Simple Container

Simple container called `mycontainer` running a plain NixOS instance with `htop` installed:

```nix
# NixOS configuration of host machine
{
  # import the module on the host
  imports = [
    # with flakes
    inputs.nixos-nspawn.nixosModules.host
    # OR
    # without flakes
    "${builtins.fetchTarball "https://github.com/fpletz/nixos-nspawn/archive/main.tar.gz"}/host.nix"
  ];

  nixos-nspawn.containers = {
    mycontainer.config = { pkgs,... }: {
      environment.systemPackages = [ pkgs.htop ];
    };
  };
}
```

You can use `machinectl shell mycontainer` to access a root shell in the container and run `htop`.

### Example: Reverse Proxy on the host for container

The following NixOS configuration creates a container host with an nginx configured to reverse proxy
to a container named `backend` with another nginx instance.

```nix
{
  # reverse proxy on the host
  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    virtualHosts."_".locations."/".proxyPass = "http://backend";
  };

  nixos-nspawn.containers = {
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

### Example: Custom network configuration

Static network configuration is also possible:

```nix
{
  nixos-nspawn.containers = {
    testcontainer = {
      config = { };
      network.veth.config = {
        # networkd network unit configs for host and container side
        host = {
          networkConfig = {
            DHCPServer = false;
            Address = [
              "fc42::1/64"
              "192.168.42.1/24"
            ];
          };
        };
        container = {
          networkConfig = {
            DHCP = false;
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
