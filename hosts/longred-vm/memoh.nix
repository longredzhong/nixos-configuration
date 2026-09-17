# Memoh: a multi-agent platform where every agent gets its own workspace.
#
# Upstream ships a Docker Compose stack that expects a Docker engine, so this
# module is the only place in the repository that enables a container daemon
# instead of talking to rootless podman. It runs on this guest, not on the NUC,
# because the `server` container is `privileged` with `pid: host` and can
# therefore read every decrypted agenix secret on the machine it runs on.
#
# Upstream is pinned by revision and fetched into the store rather than vendored:
# the deployment directory carries 43 provider definitions that we do not own and
# should not fork.
#
# Exposure: the published ports are forced onto loopback. Docker inserts its own
# iptables rules that bypass `networking.firewall`, so leaving upstream's
# `8080:8080` / `8082:8082` in place would publish the admin UI on the guest's
# lab LAN interface. The web UI is instead reached through `tailscale serve` on
# its own port, because ntfy already owns 443 on this node.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  memohSrc = pkgs.fetchFromGitHub {
    owner = "felinics";
    repo = "Memoh";
    rev = "1aaef83ff55a9432da4ac7dc631fff36f5e254ab";
    hash = "sha256-FI/17YswZ519bgQAXrcJ4VLTO25mh6PHf3xHWEvHZPo=";
  };

  stateDir = "/var/lib/memoh";
  composeFiles = [
    "${memohSrc}/docker-compose.yml"
    "${memohSrc}/docker/docker-compose.cn.yml"
    "${localOverride}"
  ];

  # Upstream's compose file publishes on all interfaces. `!override` replaces the
  # list instead of appending to it, which is what makes this a narrowing change
  # rather than one more published port.
  localOverride = pkgs.writeText "docker-compose.local.yml" ''
    services:
      # memoh.cn, the mirror this deployment otherwise uses, does not carry the
      # pgvector namespace at all: it answers 403 for every pgvector path while
      # serving library/* and memohai/*. This one image therefore comes from a
      # public Docker Hub mirror and is pinned by digest so its content cannot
      # change silently. The digest cannot be cross-checked against Docker Hub
      # from here, because the guest has no route to registry-1.docker.io.
      pgvector:
        image: docker.m.daocloud.io/pgvector/pgvector:pg18@sha256:2ba9ca5f2e7daa0f0e7723cba1ee9167bab54efd3640516a44ac1a928dd67e7a
      # Upstream's China mirror overlay rewrites postgres, pgvector, migrate,
      # server and web but omits `channel`, which is a default (non-profile)
      # service. Without this the start fails on an unreachable
      # registry-1.docker.io.
      channel:
        image: memoh.cn/memohai/server:latest
      server:
        ports: !override
          - "127.0.0.1:8080:8080"
      web:
        ports: !override
          - "127.0.0.1:8082:8082"
  '';

  # config.toml is generated from upstream's own template at every start so that
  # a template change upstream cannot silently drift: every replacement asserts
  # how many occurrences it expects and aborts the unit if the count is wrong.
  generateConfig = pkgs.writeText "memoh-generate-config.py" ''
    import os
    import sys

    template = os.path.join("${memohSrc}", "conf", "app.docker.toml")
    destination = os.path.join("${stateDir}", "config.toml")
    secret_file = "${config.age.secrets.memoh-env.path}"

    env = {}
    with open(secret_file) as handle:
        for line in handle:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            key, _, value = line.partition("=")
            env[key.strip()] = value

    for required in ("POSTGRES_PASSWORD", "MEMOH_AUTH_JWT_SECRET", "MEMOH_ADMIN_PASSWORD"):
        if not env.get(required):
            sys.exit("memoh: " + required + " is missing from the secret file")

    with open(template) as handle:
        text = handle.read()


    def replace(old, new, expected):
        global text
        found = text.count(old)
        if found != expected:
            sys.exit(
                "memoh: upstream template changed: expected "
                + str(expected)
                + " occurrence(s) of "
                + repr(old)
                + ", found "
                + str(found)
            )
        text = text.replace(old, new)


    # Upstream ships a working default password for every credential. Each of
    # these anchors appears exactly as written in conf/app.docker.toml.
    replace('password = "admin123"', 'password = "' + env["MEMOH_ADMIN_PASSWORD"] + '"', 1)
    replace(
        'jwt_secret = "YZq8kXrW5dFpNt9mLxQvHbRjKsMnOePw"',
        'jwt_secret = "' + env["MEMOH_AUTH_JWT_SECRET"] + '"',
        1,
    )
    # The relational and the vector database share one generated password; the
    # same default line appears once per database section.
    replace('password = "memoh123"', 'password = "' + env["POSTGRES_PASSWORD"] + '"', 2)
    replace(
        '# registry = "memoh.cn"  # Uncomment for China mainland mirror',
        'registry = "memoh.cn"',
        1,
    )

    with open(destination, "w") as handle:
        handle.write(text)
    os.chmod(destination, 0o600)
  '';

  prepare = pkgs.writeShellScript "memoh-prepare" ''
    set -euo pipefail

    '${pkgs.coreutils}/bin/install' -d -m 700 '${stateDir}' '${stateDir}/conf'
    '${pkgs.coreutils}/bin/ln' -sfnT '${memohSrc}/docker-compose.yml' '${stateDir}/docker-compose.yml'
    '${pkgs.coreutils}/bin/ln' -sfnT '${memohSrc}/docker/docker-compose.cn.yml' '${stateDir}/docker-compose.cn.yml'
    '${pkgs.coreutils}/bin/ln' -sfnT '${localOverride}' '${stateDir}/docker-compose.local.yml'
    '${pkgs.coreutils}/bin/ln' -sfnT '${memohSrc}/conf/providers' '${stateDir}/conf/providers'

    # Compose reads .env from the project directory, so the decrypted secret file
    # doubles as the environment for every service.
    '${pkgs.coreutils}/bin/install' -m 600 '${config.age.secrets.memoh-env.path}' '${stateDir}/.env'

    '${pkgs.python3}/bin/python3' '${generateConfig}'
  '';

  compose = [
    "'${pkgs.docker-compose}/bin/docker-compose'"
    "--project-directory '${stateDir}'"
  ]
  ++ map (file: "-f '${file}'") composeFiles;
in
{
  age.secrets.memoh-env = {
    file = ../../secrets/memoh-env.age;
    owner = "root";
    mode = "0400";
  };

  virtualisation.docker.enable = true;

  # The directory has to exist before the unit starts: systemd chdir's into
  # WorkingDirectory before it runs ExecStartPre, so creating it there is too
  # late and the unit dies with status=200/CHDIR.
  systemd.tmpfiles.rules = [ "d ${stateDir} 0700 root root -" ];

  systemd.services.memoh = {
    description = "Memoh multi-agent platform (Docker Compose)";
    wantedBy = [ "multi-user.target" ];
    after = [
      "docker.service"
      "network-online.target"
    ];
    requires = [ "docker.service" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      WorkingDirectory = stateDir;
      ExecStartPre = prepare;
      ExecStart = "${lib.concatStringsSep " " compose} up -d --remove-orphans";
      ExecStop = "${lib.concatStringsSep " " compose} down";
      # First start pulls several images, and the guest's egress is slow. An
      # unbounded start timeout is better than a unit that gives up midway
      # through a pull and leaves the database half-initialised.
      TimeoutStartSec = "0";
      TimeoutStopSec = "300";
    };
  };

  # The web UI already sits behind loopback; `tailscale serve` gives it a tailnet
  # HTTPS name on its own port, so the LAN and the internet still cannot reach it.
  systemd.services.tailscale-serve-memoh = {
    description = "Publish the Memoh web UI on this node's tailnet HTTPS name";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "tailscaled.service"
      "memoh.service"
    ];
    requires = [ "tailscaled.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStartPre = "${config.services.tailscale.package}/bin/tailscale cert --cert-file /var/lib/tailscale/certs/${config.networking.hostName}.tail388af.ts.net.crt --key-file /var/lib/tailscale/certs/${config.networking.hostName}.tail388af.ts.net.key ${config.networking.hostName}.tail388af.ts.net";
      ExecStart = "${config.services.tailscale.package}/bin/tailscale serve --bg --https=8443 http://127.0.0.1:8082";
      ExecStop = "${config.services.tailscale.package}/bin/tailscale serve --https=8443 off";
      Restart = "on-failure";
      RestartSec = "15s";
    };
  };
}
