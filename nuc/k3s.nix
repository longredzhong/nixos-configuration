{ networking
, services
, environment
, pkgs
, config
, ...
}:
let
  k3s_envfile = pkgs.writeText "k3s.env" ''
    HTTP_PROXY=http://nuc:7890
    HTTPS_PROXY=http://nuc:7890
    NO_PROXY=127.0.0.0/8,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16
    CONTAINERD_HTTP_PROXY=http://nuc:7890
    CONTAINERD_HTTPS_PROXY=http://nuc:7890
    CONTAINERD_NO_PROXY=127.0.0.0/8,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16
    '';
in
{
  services.k3s = {
    enable = true;
    role = "server";
    environmentFile = k3s_envfile;
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
