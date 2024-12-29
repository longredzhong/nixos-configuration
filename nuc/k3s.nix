{ networking
, services
, environment
, pkgs
, config
, ...
}: {
  networking.firewall = {
    allowedTCPPorts = [
      6443
      2379
      2380
      10250
    ];
    allowedUDPPorts = [
      8472
      51820
      51821
    ];
  };

  services.k3s = {
    enable = true;
    role = "server";
    extraFlags = toString [
      "--advertise-address=100.127.172.105"
      "--node-ip=100.127.172.105"
    ];
  };
  environment.systemPackages = [ pkgs.nfs-utils ];
  services.openiscsi = {
    enable = true;
    name = "${config.networking.hostName}-initiatorhost";
  };

}
