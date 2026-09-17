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
  # Must be exactly the URL subscribers use. ntfy derives the Firebase poll
  # topic that makes iOS push work on a self-hosted server from this value, so a
  # value that differs from the address typed into the app makes iPhones fail
  # silently while Android keeps working. This is the public hostname published
  # by the Cloudflare tunnel in ./cloudflared.nix.
  baseUrl = "https://ntfy.longred.work";

  # Second, local-only path: `tailscale serve` publishes the same listener on the
  # node's tailnet HTTPS name, which keeps publishing and the web UI reachable
  # even if Cloudflare or the tunnel is down.
  tailnetName = "${config.networking.hostName}.tail388af.ts.net";

  # The nixpkgs module defaults `listen-http` to this port; keeping the value
  # here means the serve target cannot drift from the listener.
  httpPort = 2586;

  # Certificate name is the node's own tailnet DNS name, and tailscaled caches
  # certificates under this directory.
  certName = tailnetName;
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

      # Required for instant notifications on iOS, which cannot receive push
      # without a central server: every incoming message makes this server POST a
      # poll request to the upstream, which relays it through Firebase/APNs, and
      # the phone then fetches the message body from here.
      #
      # This is NOT a built-in default even though the documentation's config
      # table lists it as one: `ntfy serve --help` prints no default for the
      # flag, and with it unset iOS delivery silently degrades to slow polling
      # (the docs say "hours"). Android is unaffected either way.
      upstream-base-url = "https://ntfy.sh";

      # Private instance: nothing is readable or writable without a credential.
      # Publishing used to be allowed anonymously on the one topic, which was
      # defensible while the service was tailnet-only. It is not once the service
      # is published on a public hostname, so the destination now authenticates
      # with a bearer token and no anonymous entry exists at all.
      auth-default-access = "deny-all";
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
