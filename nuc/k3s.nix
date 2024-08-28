{ networking
, services
, ...
}: {
  networking.firewall = {
    allowedTCPPorts = [
      6443
      2380
    ];
  };

  services.k3s = {
    enable = true;
    role = "server";
    extraFlags = toString [
      "--advertise-address=100.127.172.105"
      "--node-ip=100.127.172.105"
      "--embedded-registry"
    ];
  };

}
