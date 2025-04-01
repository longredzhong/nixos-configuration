{ config, lib, pkgs, secrets, ... }:
{
  services.minio = {
    enable = true;  # Enable MinIO service
    accessKey = secrets.minio.accessKey;
    secretKey = secrets.minio.secretKey;
  };
}
