# The home lab's tailnet, and the no-proxy list derived from it.
#
# MagicDNS answers both `<host>` and `<host>.<domain>`, and this repository
# addresses hosts by the short name: the binary cache substituter is
# `http://longred-vm:5000`, the default outbound proxy is `http://metacube:7890`.
#
# A no-proxy list that only excludes the tailnet's address range therefore does
# not work. `NO_PROXY` is matched against the host string *in the URL*, never
# against the address that host resolves to, so a short name slips past
# `100.64.0.0/10` and is sent to the proxy -- which cannot reach a tailnet-only
# service and answers `502 Bad Gateway`. That is how the nix daemon on a host
# with a system-wide proxy ended up unable to substitute from the home lab
# cache while `curl` to the same URL answered normally.
#
# One file owns the names so the user shell, the NixOS proxy settings (which the
# nix daemon inherits) and the host services' systemd environment cannot drift
# apart again.
let
  # MagicDNS suffix.
  domain = "tail388af.ts.net";

  # Hosts this repository reaches by short name.
  hosts = [
    "nuc"
    "longred-vm"
    "fedora-thinkbook"
    "metacube"
  ];

  # Entries every no-proxy list needs: loopback, RFC1918, the tailnet's CGNAT
  # range and mDNS names.
  localEntries = [
    "localhost"
    "127.0.0.1"
    "::1"
    "10.0.0.0/8"
    "172.16.0.0/12"
    "192.168.0.0/16"
    "100.64.0.0/10"
    ".local"
  ];

  # The suffix covers fully qualified names, the short names cover everything
  # addressed the way this repository addresses it.
  names = [ ".${domain}" ] ++ hosts;
in
{
  inherit domain hosts localEntries names;

  noProxy = builtins.concatStringsSep "," (localEntries ++ names);
}
