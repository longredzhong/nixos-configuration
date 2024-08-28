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
      # "--kubelet-arg=v=4" # Optionally add additional args to k3s
      "--kubelet-arg=node-ip=0.0.0.0"
      "--embedded-registry"
    ];
  };

}
