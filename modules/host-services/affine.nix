# Self-hosted AFFiNE (https://docs.affine.pro/self-host-affine) on the NUC,
# translated from the upstream docker-compose.yml into rootless Podman
# user-level systemd units (same pattern as garage-ui; the plain
# docker-compose CLI needs a Docker API socket we do not run).
#
# Stack: postgres (pgvector) + redis + manticore indexer + one-shot migration
# + affine server.
# Web UI is published on the Tailscale IP only: http://100.100.10.1:3010
# Data lives in /data/affine/{data,config}; config/config.json is owned by the
# nix template (overwritten on every start for a single source of truth —
# Admin Panel settings live in the database and are unaffected).
{ config, pkgs, ... }:
let
  inherit (config.hostServices) proxyEnvironment;

  affineImage = "ghcr.io/toeverything/affine:stable";
  postgresImage = "docker.io/pgvector/pgvector:pg16";
  redisImage = "docker.io/library/redis:7";
  indexerImage = "docker.io/manticoresearch/manticore:10.1.0";

  dataDir = "/data/affine";
  listenAddress = "100.100.10.1";
  port = 3010;
  indexerPort = 9308;
  indexerEndpoint = "http://indexer:${toString indexerPort}";

  podman = "${pkgs.podman}/bin/podman";
  # --http-proxy=false: keep the proxy env on the podman client (needed for
  # image pulls) but do not inject it into the containers, so server-side
  # requests to LAN/tailnet AI endpoints stay direct.
  # DEPLOYMENT_TYPE=selfhosted is what makes the server treat the instance as
  # self-hosted (AI BYOK entitlement); SELF_HOSTED is kept for compatibility.
  commonFlags = "--rm --replace --security-opt label=disable --http-proxy=false --network affine";

  configTemplate = pkgs.writeText "affine-config.json" ''
    {
      "$schema": "https://github.com/toeverything/affine/releases/latest/download/config.schema.json",
      "server": {
        "name": "AFFiNE @ nuc",
        "externalUrl": "http://${listenAddress}:${toString port}"
      },
      "copilot": {
        "enabled": true,
        "byok": {
          "enabled": true,
          "allowCustomEndpoint": true
        }
      }
    }
  '';
in
{
  imports = [ ./proxy.nix ];

  systemd.user.services.affine-postgres = {
    Unit.Description = "AFFiNE PostgreSQL (pgvector)";
    Service = {
      Environment = proxyEnvironment; # podman image pull
      ExecStartPre = pkgs.writeShellScript "affine-net" ''
        mkdir -p ${dataDir}/data/postgres ${dataDir}/data/storage ${dataDir}/config
        ${podman} network exists affine || ${podman} network create affine
      '';
      ExecStart = pkgs.writeShellScript "affine-postgres-start" ''
        exec ${podman} run ${commonFlags}:alias=postgres \
          --name affine-postgres \
          --pull missing \
          --env POSTGRES_USER=affine \
          --env POSTGRES_DB=affine \
          --env POSTGRES_INITDB_ARGS=--data-checksums \
          --env POSTGRES_HOST_AUTH_METHOD=trust \
          --volume ${dataDir}/data/postgres:/var/lib/postgresql/data \
          ${postgresImage}
      '';
      ExecStop = "${podman} stop -t 10 affine-postgres";
      Restart = "always";
      RestartSec = "5s";
    };
    Install.WantedBy = [ "default.target" ];
  };

  systemd.user.services.affine-redis = {
    Unit.Description = "AFFiNE Redis";
    Service = {
      Environment = proxyEnvironment; # podman image pull
      ExecStart = pkgs.writeShellScript "affine-redis-start" ''
        exec ${podman} run ${commonFlags}:alias=redis \
          --name affine-redis \
          --pull missing \
          ${redisImage}
      '';
      ExecStop = "${podman} stop -t 10 affine-redis";
      Restart = "always";
      RestartSec = "5s";
    };
    Install.WantedBy = [ "default.target" ];
  };

  systemd.user.services.affine-indexer = {
    Unit.Description = "AFFiNE Manticore full-text indexer";
    Service = {
      Environment = proxyEnvironment; # podman image pull
      ExecStartPre = pkgs.writeShellScript "affine-indexer-dirs" ''
        mkdir -p ${dataDir}/data/manticore
      '';
      # memlock ulimit is left out: rootless podman cannot raise it
      ExecStart = pkgs.writeShellScript "affine-indexer-start" ''
        exec ${podman} run ${commonFlags}:alias=indexer \
          --name affine-indexer \
          --pull missing \
          --ulimit nproc=65535 \
          --ulimit nofile=65535:65535 \
          --volume ${dataDir}/data/manticore:/var/lib/manticore \
          ${indexerImage}
      '';
      ExecStop = "${podman} stop -t 10 affine-indexer";
      Restart = "always";
      RestartSec = "5s";
    };
    Install.WantedBy = [ "default.target" ];
  };

  systemd.user.services.affine-migration = {
    Unit = {
      Description = "AFFiNE one-shot schema migration";
      After = [
        "affine-postgres.service"
        "affine-redis.service"
        "affine-indexer.service"
      ];
      Requires = [
        "affine-postgres.service"
        "affine-redis.service"
        "affine-indexer.service"
      ];
    };
    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      Environment = proxyEnvironment; # podman image pull
      ExecStartPre = pkgs.writeShellScript "affine-wait" ''
        mkdir -p ${dataDir}/data/storage ${dataDir}/config
        for i in $(seq 1 60); do
          ${podman} exec affine-postgres pg_isready -U affine -d affine >/dev/null 2>&1 \
            && ${podman} exec affine-redis redis-cli ping >/dev/null 2>&1 \
            && ${podman} exec affine-indexer wget -q -O- http://127.0.0.1:${toString indexerPort} >/dev/null 2>&1 && exit 0
          sleep 2
        done
        echo "affine: postgres/redis/indexer not ready in time" >&2
        exit 1
      '';
      ExecStart = pkgs.writeShellScript "affine-migration-start" ''
        exec ${podman} run ${commonFlags} \
          --name affine-migration \
          --pull newer \
          --env SELF_HOSTED=true \
          --env DEPLOYMENT_TYPE=selfhosted \
          --env REDIS_SERVER_HOST=redis \
          --env DATABASE_URL=postgresql://affine@postgres:5432/affine \
          --env AFFINE_INDEXER_ENABLED=true \
          --env AFFINE_INDEXER_SEARCH_ENDPOINT=${indexerEndpoint} \
          --volume ${dataDir}/data/storage:/root/.affine/storage \
          --volume ${dataDir}/config:/root/.affine/config \
          ${affineImage} sh -c 'node ./scripts/self-host-predeploy.js'
      '';
    };
  };

  systemd.user.services.affine = {
    Unit = {
      Description = "AFFiNE self-hosted server (${listenAddress}:${toString port})";
      After = [ "affine-migration.service" ];
      Requires = [ "affine-migration.service" ];
    };
    Service = {
      Environment = proxyEnvironment; # podman image pull
      ExecStartPre = pkgs.writeShellScript "affine-init-config" ''
        mkdir -p ${dataDir}/config
        install -m 644 ${configTemplate} ${dataDir}/config/config.json
      '';
      ExecStart = pkgs.writeShellScript "affine-server-start" ''
        exec ${podman} run ${commonFlags}:alias=affine \
          --name affine-server \
          --pull newer \
          --env SELF_HOSTED=true \
          --env DEPLOYMENT_TYPE=selfhosted \
          --publish ${listenAddress}:${toString port}:3010 \
          --env REDIS_SERVER_HOST=redis \
          --env DATABASE_URL=postgresql://affine@postgres:5432/affine \
          --env AFFINE_INDEXER_ENABLED=true \
          --env AFFINE_INDEXER_SEARCH_ENDPOINT=${indexerEndpoint} \
          --volume ${dataDir}/data/storage:/root/.affine/storage \
          --volume ${dataDir}/config:/root/.affine/config \
          ${affineImage}
      '';
      ExecStop = "${podman} stop -t 10 affine-server";
      Restart = "always";
      RestartSec = "5s";
    };
    Install.WantedBy = [ "default.target" ];
  };
}
