# ntfy: the home lab notification bus.
#
# Placement: this service is deliberately NOT on the NUC. The NUC is the machine
# OpenObserve watches, so a notifier living there would fall silent at exactly
# the moment its alerts start to matter. This guest runs on a different physical
# host, which keeps the notification path alive when the NUC is gone.
#
# Exposure: ntfy listens on loopback only, and `tailscale serve` publishes it on
# this node's tailnet HTTPS name. No firewall rule is needed because tailscaled
# owns port 443, and nothing here is reachable from the LAN.
{
  config,
  ...
}:
let
  # Must be exactly the URL clients use. ntfy derives the Firebase poll topic
  # that makes iOS push work on a self-hosted server from this value, so a wrong
  # value fails silently on iPhones while Android keeps working.
  baseUrl = "https://${config.networking.hostName}.tail388af.ts.net";

  # Publishing topic. Not a secret: the access rule below lets anyone who can
  # reach the service publish to it, while reading requires an authenticated
  # user. Keep it in sync with the OpenObserve destination URL.
  topic = "homelab-alerts";

  # The nixpkgs module defaults `listen-http` to this port; keeping the value
  # here means the serve target cannot drift from the listener.
  httpPort = 2586;

  # Certificate name is the node's own tailnet DNS name, and tailscaled caches
  # certificates under this directory.
  certName = "${config.networking.hostName}.tail388af.ts.net";
  certDir = "/var/lib/tailscale/certs";
in
{
  services.ntfy-sh = {
    enable = true;
    settings = {
      listen-http = "127.0.0.1:${toString httpPort}";
      base-url = baseUrl;
      behind-proxy = true;

      # Phones and laptops come back from suspend with dead connections; keep
      # messages long enough that a missed notification is still retrievable.
      cache-duration = "24h";

      # Private instance: nothing is readable or writable unless the entry below
      # or an authenticated user grants it.
      auth-default-access = "deny-all";

      # OpenObserve publishes anonymously from the NUC. This grants write-only
      # access to exactly one topic, so an anonymous client can inject noise
      # into that topic but can neither read it nor touch anything else. Replace
      # it with a bearer token once a publisher token exists; see
      # docs/alerting.md.
      auth-access = [ "*:${topic}:write-only" ];
    };
  };

  # `tailscale serve` terminates TLS and reverse-proxies to loopback, so ntfy
  # needs no listener of its own on the tailnet and receives the client address
  # through X-Forwarded-For (hence behind-proxy above). --bg keeps the config
  # applied without an interactive login.
  systemd.services.tailscale-serve-ntfy = {
    description = "Publish ntfy on this node's tailnet HTTPS name";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "tailscaled.service"
      "ntfy-sh.service"
    ];
    requires = [
      "tailscaled.service"
      "ntfy-sh.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;

      # `tailscale serve` publishes the HTTPS listener but does not obtain the
      # TLS certificate itself. Without one the listener still accepts TCP and
      # then fails the handshake, which is exactly what a delivery attempt would
      # hit, so the certificate is ensured first. `tailscale cert` is
      # idempotent: while the cached certificate is valid it reports it
      # unchanged and exits zero.
      ExecStartPre = "${config.services.tailscale.package}/bin/tailscale cert --cert-file ${certDir}/${certName}.crt --key-file ${certDir}/${certName}.key ${certName}";
      ExecStart = "${config.services.tailscale.package}/bin/tailscale serve --bg --https=443 http://127.0.0.1:${toString httpPort}";
      ExecStop = "${config.services.tailscale.package}/bin/tailscale serve --https=443 off";

      # The certificate request needs a reachable control plane, which can lag
      # behind tailscaled at boot. Retry rather than leaving the listener
      # half-configured.
      Restart = "on-failure";
      RestartSec = "15s";
    };
  };
}
