{ networking
, services
, environment
, pkgs
, config
, ...
}: {
  services.k3s = {
    enable = true;
    role = "server";
    extraFlags = toString [
      "--advertise-address=100.127.172.105"
      "--node-ip=100.127.172.105"
      "--embedded-registry"
    ];
  };
  environment.systemPackages = [ pkgs.nfs-utils ];
  services.openiscsi = {
    enable = true;
    name = "${config.networking.hostName}-initiatorhost";
  };

}
