# Garage on longred-vm: the off-host backup target for the NUC's object storage.
#
# The NUC runs a single-node Garage and keeps two buckets in it. This module
# runs a second, independent single-node Garage on the VM and mirrors those
# buckets into it, so the lab has a copy that is itself a working S3 endpoint
# rather than an opaque blob store.
#
# Why mirror at the object level instead of copying files: Garage's data
# directory is not safe to read while the node is writing to it. Going through
# the S3 API is application-consistent by construction.
#
# The mirror runs on a timer rather than continuously because the NUC reaches
# this VM only through a relayed tailnet link (~1.6 MB/s measured), which is
# fine for incremental runs and painful for a stream.
{
  config,
  pkgs,
  lib,
  ...
}:
let
  garageDir = "/var/lib/garage";
  garageBin = lib.getExe pkgs.garage_2;

  # Generated on first start rather than kept as secrets: this Garage is its
  # own cluster and nothing outside the VM talks to its RPC or admin API.
  rpcSecretFile = "${garageDir}/rpc-secret";
  adminTokenFile = "${garageDir}/admin-token";
  destCredentials = "${garageDir}/dest.env";

  configFile = pkgs.writeText "garage-backup.toml" ''
    metadata_dir = "${garageDir}/meta"
    data_dir = "${garageDir}/data"

    db_engine = "lmdb"
    replication_factor = 1

    rpc_bind_addr = "127.0.0.1:3901"
    rpc_public_addr = "127.0.0.1:3901"
    rpc_secret_file = "${rpcSecretFile}"

    [s3_api]
    api_bind_addr = "[::]:3900"
    s3_region = "garage"

    [admin]
    api_bind_addr = "127.0.0.1:3903"
  '';

  # The CLI needs the secret paths on the command line: the config's
  # `rpc_secret_file` is read literally, and the wrapper below also supplies the
  # admin token.
  garage = "${garageBin} -c ${configFile} --admin-token-file ${adminTokenFile} --rpc-secret-file ${rpcSecretFile}";

  # Mirror target is addressed over the tailnet; the guest cannot route the
  # NUC's LAN address.
  sourceEndpoint = "http://100.100.10.1:3900";
  destEndpoint = "http://127.0.0.1:3900";
  region = "garage";
  keyName = "longred-vm-mirror";

  # Buckets copied from the NUC's Garage. Listed explicitly so the backup is
  # auditable; add a name here when the NUC grows a bucket.
  buckets = [
    "openobserve"
    "tmp"
  ];
in
{
  # Source-side credentials: a read-only Garage key created on the NUC and
  # granted read on each bucket. The mirror never writes to the NUC.
  age.secrets.garage-backup-read = {
    file = ../../secrets/garage-backup-read.age;
    owner = "root";
    mode = "0400";
  };

  environment.systemPackages = [
    pkgs.curl
    pkgs.jq
    pkgs.rclone
  ];

  # Garage's S3 API is reachable from the tailnet so the mirrored data can be
  # read back; the admin API stays on loopback.
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 3900 ];

  # --- one-time local material -------------------------------------------
  systemd.services.garage-backup-init = {
    description = "Prepare local Garage secrets for the backup node";
    wantedBy = [ "multi-user.target" ];
    before = [ "garage-backup.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail
      install -d -m 0700 ${garageDir}
      for f in ${rpcSecretFile} ${adminTokenFile}; do
        if [ ! -s "$f" ]; then
          ${pkgs.openssl}/bin/openssl rand -hex 32 > "$f"
          chmod 600 "$f"
        fi
      done
      install -d -m 0755 ${garageDir}/data ${garageDir}/meta
    '';
  };

  # --- the backup Garage itself ------------------------------------------
  systemd.services.garage-backup = {
    description = "Garage backup node (mirror target for the NUC's object storage)";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "garage-backup-init.service"
    ];
    wants = [ "network-online.target" ];
    requires = [ "garage-backup-init.service" ];
    serviceConfig = {
      ExecStart = "${garageBin} -c ${configFile} server";
      Restart = "always";
      RestartSec = "5s";
    };
  };

  # --- cluster layout, buckets and mirror credentials ---------------------
  systemd.services.garage-backup-provision = {
    description = "Apply Garage layout, create buckets and the mirror key";
    # Runs once the node is up, on every boot: the layout, buckets and key are
    # all idempotent, and this is also what kicks off the first mirror run.
    wantedBy = [ "multi-user.target" ];
    after = [ "garage-backup.service" ];
    requires = [ "garage-backup.service" ];
    wants = [ "garage-backup-mirror.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail
      token="$(cat ${adminTokenFile})"

      # The admin API only answers once the node is up.
      for _ in $(seq 1 60); do
        if ${pkgs.curl}/bin/curl -sf -o /dev/null \
             -H "Authorization: Bearer $token" http://127.0.0.1:3903/health; then
          break
        fi
        sleep 1
      done

      # A single-node layout has to be assigned and applied once before any
      # bucket can exist.
      if ! ${garage} layout show 2>/dev/null | grep -qE '^[0-9a-f]{16}[[:space:]]'; then
        node="$(${garage} status | ${pkgs.gawk}/bin/awk '$1 ~ /^[0-9a-f]{16}$/ {print $1; exit}')"
        if [ -z "$node" ]; then
          echo "garage-backup: could not determine the local node id" >&2
          exit 1
        fi
        ${garage} layout assign -z backup -c 100G "$node"
        ${garage} layout apply --version 1
      fi

      ${lib.concatMapStringsSep "\n" (bucket: ''
        ${garage} bucket create ${bucket} 2>/dev/null || true
      '') buckets}

      if ! ${garage} key info ${keyName} >/dev/null 2>&1; then
        ${garage} key create ${keyName}
      fi

      ${lib.concatMapStringsSep "\n" (bucket: ''
        ${garage} bucket allow --read --write --owner ${bucket} --key ${keyName} >/dev/null 2>&1 || true
      '') buckets}

      info="$(${garage} key info --show-secret ${keyName})"
      ak="$(printf '%s\n' "$info" | ${pkgs.gawk}/bin/awk -F': *' '$1 == "Key ID" {print $2; exit}')"
      sk="$(printf '%s\n' "$info" | ${pkgs.gawk}/bin/awk -F': *' '$1 == "Secret key" {print $2; exit}')"
      if [ -z "$ak" ] || [ -z "$sk" ]; then
        echo "garage-backup: could not read the mirror key credentials" >&2
        exit 1
      fi
      umask 077
      printf 'GARAGE_DEST_ACCESS_KEY=%s\nGARAGE_DEST_SECRET_KEY=%s\n' "$ak" "$sk" > ${destCredentials}
      chmod 600 ${destCredentials}
    '';
  };

  # --- the mirror ---------------------------------------------------------
  systemd.services.garage-backup-mirror = {
    description = "Mirror the NUC's Garage buckets into the backup node";
    after = [ "garage-backup-provision.service" ];
    requires = [ "garage-backup-provision.service" ];
    serviceConfig = {
      Type = "oneshot";
      # Credentials are read from a runtime config file rather than the command
      # line, so the journal is free to show rclone's progress.
      TimeoutStartSec = "infinity";
    };
    script = ''
      set -euo pipefail
      # shellcheck disable=SC1091
      . ${destCredentials}
      # shellcheck disable=SC1091
      . ${config.age.secrets.garage-backup-read.path}

      rclone=${pkgs.rclone}/bin/rclone

      # Credentials go in a runtime config rather than on the command line, so
      # they never appear in the process table or in an error message.
      cfg="$(mktemp)"
      chmod 600 "$cfg"
      trap 'rm -f "$cfg"' EXIT
      cat > "$cfg" <<CFG
      [source]
      type = s3
      provider = Other
      region = ${region}
      endpoint = ${sourceEndpoint}
      access_key_id = $GARAGE_BACKUP_ACCESS_KEY
      secret_access_key = $GARAGE_BACKUP_SECRET_KEY
      no_check_bucket = true

      [dest]
      type = s3
      provider = Other
      region = ${region}
      endpoint = ${destEndpoint}
      access_key_id = $GARAGE_DEST_ACCESS_KEY
      secret_access_key = $GARAGE_DEST_SECRET_KEY
      no_check_bucket = true
      CFG

      ${lib.concatMapStringsSep "\n" (bucket: ''
        echo "mirroring ${bucket}"
        "$rclone" --config "$cfg" mkdir "dest:${bucket}"
        "$rclone" --config "$cfg" sync "source:${bucket}" "dest:${bucket}" \
          --checksum \
          --transfers 4 \
          --checkers 8 \
          --stats-one-line \
          --stats 60s
      '') buckets}
    '';
  };

  systemd.timers.garage-backup-mirror = {
    description = "Periodic Garage mirror into the backup node";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 00/6:30:00";
      RandomizedDelaySec = "15m";
      Persistent = true;
    };
  };
}
