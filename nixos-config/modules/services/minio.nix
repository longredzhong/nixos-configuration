{ config, lib, pkgs, secrets, ... }:
{
  services.minio = {
    enable = true;  # Enable MinIO service
    # Additional configuration options can be added here
    accessKey = secrets.minio.accessKey;
    secretKey = secrets.minio.secretKey;
    # Optionally, specify the MinIO server's storage path

  };
}