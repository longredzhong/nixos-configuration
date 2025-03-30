{ config, lib, pkgs, ... }:

{
  programs.starship = {
    enable = true;
    settings = {
      aws.disabled = true;
      gcloud.disabled = true;
      kubernetes.disabled = true;
      git_branch.style = "242";
      directory.style = "blue";
      directory.truncate_to_repo = false;
      directory.truncation_length = 8;
      python.disabled = false;
      ruby.disabled = true;
      hostname.ssh_only = false;
      hostname.style = "bold green";
    };
  };
}