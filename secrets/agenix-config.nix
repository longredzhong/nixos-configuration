# This file is the NixOS module for Agenix configuration.
# It imports key data from secrets.nix.
{ config, lib, pkgs, username, ... }:

let
  # Import the key definitions and mappings
  secretsData = import ./secrets.nix { inherit lib; }; # Pass lib if needed by helper
  intendedRecipientsComment = secretsData.generateComment; # Get the comment generator

in
{
  # Define the actual NixOS options for agenix
  age.identityPaths = [
    # --- Host Keys (Per Host Identity) ---
    "/etc/ssh/ssh_host_ed25519_key" # Recommended, most hosts default generate
    # "/etc/ssh/ssh_host_rsa_key"
    # "/etc/ssh/agenix_host_key.txt" # If using dedicated age host key

    # --- User Keys (Can act as Per User Identity for decryption) ---
    "/home/${username}/.ssh/id_ed25519" # User longred's key
    # "/home/${username}/.ssh/id_rsa"
    # "/home/${username}/.ssh/id_age" # If using dedicated age user key
    # "/root/.ssh/id_ed25519" # If needed for root
  ];

  age.secrets."test" = {
    file = ./tmp.age;
    owner = config.users.users.${username}.name;
    group = config.users.users.${username}.group;
    mode = "600";
    path = "/home/${username}/test";
  };

  age.secrets."minio-credentials" = {
    file = ./minio-credentials.age;
    owner = "root";
    group = "root";
    mode = "600";
    path = "/etc/nixos/minio-root-credentials";
  };

  # Add other age.secrets definitions here as needed...
  # Example:
  # age.secrets."user-api-token" = {
  #   # ${intendedRecipientsComment "user-api-token.age"}
  #   file = ./user-api-token.age;
  #   owner = username;
  #   group = "users"; # Or config.users.users.${username}.group
  #   mode = "600";
  # };
}
