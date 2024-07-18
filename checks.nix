{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      checks = {
        simple-container = pkgs.nixosTest {
          name = "simple-container";
          nodes.host =
            { ... }:
            {
              imports = [ inputs.self.nixosModules.host ];
              virtualisation.nixos-nspawn-ephemeral.containers.test = inputs.nixpkgs.lib.nixosSystem {
                inherit (pkgs) system;
                modules = [
                  inputs.self.nixosModules.container
                  { networking.hostName = "test-container"; }
                ];
              };
            };

          testScript = ''
            start_all()
            host.wait_for_unit("systemd-nspawn@test.service")
            # needs to wait until networking is configured
            host.wait_until_succeeds("ping -c 1 test")
            host.succeed("machinectl shell test /run/current-system/sw/bin/ping -c 1 host")
          '';
        };
      };
    };
}
