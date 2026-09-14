# OpenObserve single-node service on the Fedora NUC.
#
# The SQLite metadata, WAL, and local cache stay on /data. Stream data is
# written to the dedicated Garage S3 bucket created by the provisioning step.
# The container uses host networking so it can reach Garage on 127.0.0.1:3900;
# OpenObserve itself is bound to the NUC's Tailscale address only.
{
  config,
  pkgs,
  ...
}:
let
  inherit (config.hostServices) proxyEnvironment;

  openobserveImage = "public.ecr.aws/zinclabs/openobserve:v1.0.0";
  openobserveDataDir = "/data/openobserve";
  openobserveDataVolume = "${openobserveDataDir}/data";
  openobserveEnvFile = "${openobserveDataDir}/openobserve.env";
  listenAddress = "100.100.10.1";
  httpPort = 5080;
  grpcPort = 5081;
  bucketName = "openobserve";
  keyName = "openobserve";

  garageConfig = "${config.xdg.configHome}/garage/garage.toml";
  garageRpcSecret = config.age.secrets.garage-rpc-secret.path;
  garageAdminToken = config.age.secrets.garage-admin-token.path;
  garage = "${pkgs.garage_2}/bin/garage";
  podman = "${pkgs.podman}/bin/podman";
  coreutils = "${pkgs.coreutils}/bin";
  grep = "${pkgs.gnugrep}/bin/grep";
  awk = "${pkgs.gawk}/bin/awk";
  openssl = "${pkgs.openssl}/bin/openssl";

  provisionOpenObserve = pkgs.writeShellScript "openobserve-provision" ''
    set -euo pipefail

    data_dir='${openobserveDataDir}'
    env_file='${openobserveEnvFile}'
    bucket='${bucketName}'
    key_name='${keyName}'

    ensure_setting() {
      local variable="$1"
      local value="$2"
      if ! '${grep}' -q "^''${variable}=" "$env_file"; then
        printf '%s=%s\n' "$variable" "$value" >>"$env_file"
      fi
    }

    garage() {
      '${garage}' \
        --config '${garageConfig}' \
        --rpc-secret-file "${garageRpcSecret}" \
        --admin-token-file "${garageAdminToken}" \
        "$@"
    }

    '${coreutils}/mkdir' -p "${openobserveDataVolume}"
    '${coreutils}/chmod' 700 "$data_dir"

    # Credentials are generated once and kept on the data disk. Do not put
    # them in the Nix expression: that would copy them into /nix/store.
    if [ -f "$env_file" ]; then
      for variable in \
        ZO_ROOT_USER_EMAIL \
        ZO_ROOT_USER_PASSWORD \
        ZO_S3_ACCESS_KEY \
        ZO_S3_SECRET_KEY; do
        if ! '${grep}' -q "^''${variable}=." "$env_file"; then
          echo "openobserve: $env_file is missing $variable" >&2
          exit 1
        fi
      done
      # Move small, low-volume workloads out of the local WAL promptly. These
      # values keep the NUC's S3 durability delay bounded without changing
      # stream retention policy.
      ensure_setting ZO_MAX_FILE_RETENTION_TIME 60
      ensure_setting ZO_FILE_PUSH_INTERVAL 10
      '${coreutils}/chmod' 600 "$env_file"
      exit 0
    fi

    # Garage may have been started before its RPC endpoint is ready. Use
    # `status` here because the pinned Garage 2.3.0 CLI has no `health`
    # subcommand.
    for attempt in $(seq 1 60); do
      if garage status >/dev/null 2>&1; then
        break
      fi
      if [ "$attempt" -eq 60 ]; then
        echo "openobserve: Garage did not become healthy within 120 seconds" >&2
        exit 1
      fi
      sleep 2
    done

    if ! garage bucket info "$bucket" >/dev/null 2>&1; then
      garage bucket create "$bucket" >/dev/null
    fi

    # Garage prints the secret only when a key is created (and, on current
    # versions, when key info is requested with --show-secret). Keeping the
    # parsing here makes a partially completed first start recoverable.
    if ! garage key info "$key_name" >/dev/null 2>&1; then
      garage key create "$key_name" >/dev/null
    fi

    key_info="$(garage key info --show-secret "$key_name")"
    access_key="$(printf '%s\n' "$key_info" | '${awk}' -F': *' '$1 == "Key ID" { print $2; exit }')"
    secret_key="$(printf '%s\n' "$key_info" | '${awk}' -F': *' '$1 == "Secret key" { print $2; exit }')"
    if [ -z "$access_key" ] || [ -z "$secret_key" ]; then
      echo "openobserve: Garage did not return credentials for key $key_name" >&2
      echo "openobserve: rotate the key or run 'garage key info --show-secret $key_name' manually" >&2
      exit 1
    fi

    # OpenObserve needs object read/write/list/delete access. Bucket-owner
    # administration is intentionally not granted to the application key.
    garage bucket allow --read --write "$bucket" --key "$key_name" >/dev/null

    root_password="O2!OpenObserve-$('${openssl}' rand -hex 24)"
    tmp_file="$('${coreutils}/mktemp' "$data_dir/.openobserve.env.XXXXXX")"
    trap '${coreutils}/rm -f "$tmp_file"' EXIT
    {
      printf 'ZO_ROOT_USER_EMAIL=%s\n' 'root@openobserve.local'
      printf 'ZO_ROOT_USER_PASSWORD=%s\n' "$root_password"
      printf 'ZO_LOCAL_MODE=%s\n' 'true'
      printf 'ZO_LOCAL_MODE_STORAGE=%s\n' 's3'
      printf 'ZO_META_STORE=%s\n' 'sqlite'
      printf 'ZO_DATA_DIR=%s\n' '/data'
      printf 'ZO_S3_PROVIDER=%s\n' 's3'
      printf 'ZO_S3_SERVER_URL=%s\n' 'http://127.0.0.1:3900'
      printf 'ZO_S3_REGION_NAME=%s\n' 'garage'
      printf 'ZO_S3_BUCKET_NAME=%s\n' "$bucket"
      printf 'ZO_S3_BUCKET_PREFIX=%s\n' 'openobserve/'
      printf 'ZO_S3_ACCESS_KEY=%s\n' "$access_key"
      printf 'ZO_S3_SECRET_KEY=%s\n' "$secret_key"
      # Garage is an S3-compatible HTTP/1.1 endpoint. Path-style requests are
      # required because a loopback endpoint cannot resolve bucket subdomains.
      printf 'ZO_S3_FEATURE_FORCE_HOSTED_STYLE=%s\n' 'false'
      printf 'ZO_S3_FEATURE_HTTP1_ONLY=%s\n' 'true'
      printf 'ZO_MAX_FILE_RETENTION_TIME=%s\n' '60'
      printf 'ZO_FILE_PUSH_INTERVAL=%s\n' '10'
      printf 'ZO_HTTP_ADDR=%s\n' '${listenAddress}'
      printf 'ZO_HTTP_PORT=%s\n' '${toString httpPort}'
      printf 'ZO_GRPC_ADDR=%s\n' '${listenAddress}'
      printf 'ZO_GRPC_PORT=%s\n' '${toString grpcPort}'
      printf 'ZO_WEB_URL=%s\n' 'http://${listenAddress}:${toString httpPort}'
      printf 'ZO_TELEMETRY=%s\n' 'false'
      printf 'ZO_MMDB_DISABLE_DOWNLOAD=%s\n' 'true'
      printf 'RUST_LOG=%s\n' 'info'
    } >"$tmp_file"
    '${coreutils}/chmod' 600 "$tmp_file"
    '${coreutils}/mv' "$tmp_file" "$env_file"
    trap - EXIT
    echo "openobserve: Garage bucket/key initialized and local env file created"
  '';

  startOpenObserve = pkgs.writeShellScript "openobserve-start" ''
    exec '${podman}' run \
      --name openobserve \
      --rm \
      --replace \
      --pull missing \
      --network host \
      --security-opt label=disable \
      --http-proxy=false \
      --env-file '${openobserveEnvFile}' \
      --volume '${openobserveDataVolume}:/data' \
      '${openobserveImage}'
  '';
in
{
  imports = [ ./proxy.nix ];

  age.secrets.garage-rpc-secret.file = ../../secrets/garage-rpc-secret.age;
  age.secrets.garage-admin-token.file = ../../secrets/garage-admin-token.age;
  age.identityPaths = [ "${config.home.homeDirectory}/.ssh/id_ed25519" ];

  systemd.user.services.openobserve = {
    Unit = {
      Description = "OpenObserve single-node observability platform";
      After = [
        "agenix.service"
        "garage.service"
        "network-online.target"
      ];
      Requires = [
        "agenix.service"
        "garage.service"
      ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      Environment = proxyEnvironment;
      ExecStartPre = [
        "${coreutils}/mkdir -p ${openobserveDataVolume}"
        provisionOpenObserve
      ];
      ExecStart = startOpenObserve;
      ExecStop = "${podman} stop -t 20 openobserve";
      LimitNOFILE = 65535;
      Restart = "always";
      RestartSec = "10s";
      TimeoutStartSec = "180s";
    };
    Install.WantedBy = [ "default.target" ];
  };
}
