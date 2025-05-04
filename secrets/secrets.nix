# This file now ONLY defines keys and recipient mappings for reference and scripting.
# It is NOT a NixOS module anymore.
{ lib ? { } }: # Only need lib for helper function potentially
let
  # --- Key Definitions ---
  user_longred_ssh = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICucQsD88/+YzMcFFKc7p8rxx489u/panXkKkOFpzrDG";
  allUsers = [ user_longred_ssh ];

  host_nuc_ssh = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO1dYCjl6iFU6sqTuk7PLl/Mn2CP8wVehoTv3+HzQwCb root@nixos";
  host_thinkbook_ssh = "...";
  host_metacube_ssh = "...";
  allHosts = [ host_nuc_ssh host_thinkbook_ssh host_metacube_ssh ];

  # --- Key Name Mappings ---
  definedUsers = { longred = [ user_longred_ssh ]; };
  definedHosts = {
    nuc = [ host_nuc_ssh ];
    thinkbook-wsl = [ host_thinkbook_ssh ];
    metacube-wsl = [ host_metacube_ssh ];
  };

  # --- Secret Recipient Mapping (Documentation) ---
  secretRecipients = {
    "tmp.age" = definedUsers.longred ++ definedHosts.nuc;
    "minio-credentials.age" = definedHosts.nuc;
    # ... other mappings ...
  };

  # --- Helper Function (Optional, can be moved or duplicated if needed elsewhere) ---
  intendedRecipientsCommentGenerator = recipientsMap: definedUsersMap: definedHostsMap: secretFileName:
    let
      keys = recipientsMap.${secretFileName} or [ "ERROR: No recipients defined" ];
      findName = key:
        let
          userNames = lib.attrNames (lib.filterAttrs (n: v: v == key) definedUsersMap);
          hostNames = lib.attrNames (lib.filterAttrs (n: v: v == key) definedHostsMap);
        in
        if (userNames != [ ]) then "User '${builtins.elemAt userNames 0}'"
        else if (hostNames != [ ]) then "Host '${builtins.elemAt hostNames 0}'"
        else "Unknown Key";
      recipientNames = lib.concatStringsSep ", " (map findName keys);
    in
    "# Intended Recipients: ${recipientNames}";

in
{
  # Return structure containing keys and mappings
  keys = {
    inherit definedUsers definedHosts allUsers allHosts;
  };
  recipientMap = secretRecipients;
  # Expose the generator function if needed by agenix-config.nix
  generateComment = intendedRecipientsCommentGenerator secretRecipients definedUsers definedHosts;
}
