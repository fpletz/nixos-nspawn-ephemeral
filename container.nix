{
  boot.isContainer = true;
  networking = {
    useNetworkd = true;
    useDHCP = false;
    useHostResolvConf = false;
  };

  # FIXME: logrotate currently fails because files in the nix store are not
  # owned by root due to private users, see host.nix. Since we're running
  # ephemerally anyway this shouldn't be an issue, though.
  services.logrotate.enable = false;
}
