# Standalone Home Manager config for Fedora ThinkBook
{ config, ... }:
{
  imports = [
    ./common.nix
    ../../modules/home-manager/desktop/default.nix
    ../../modules/host-services/openobserve-agent.nix
    ../../modules/host-services/deepseek-harness-acp.nix
  ];

  # Harness API credentials, encrypted to this host and to the NUC. The values
  # originate in the NUC's $DSH_HOME/.credentials.yaml; the encrypted copies
  # make the same keys available declaratively on both hosts. Recipients are
  # SSH public keys because age.identityPaths point at SSH private keys — see
  # secrets/README.md.
  age.secrets = {
    deepseek-api-key.file = ../../secrets/deepseek-api-key.age;
    # One credential, two variable names: OpenCode Go and OpenCode Zen accept
    # the same key, so it is stored once and read under both names.
    opencode-api-key.file = ../../secrets/opencode-api-key.age;
    ten-rings-api-key.file = ../../secrets/ten-rings-api-key.age;
  };

  # DeepSeek Harness as an ACP stdio server for Zed (`dsh --profile acp`).
  #
  # Repository-owned configuration is layered on top of the harness home from
  # config/deepseek-harness/: the user-global instruction file, the model seed,
  # and the profile composition. Session state stays local to this host and is
  # deliberately not shared with the NUC.
  hostServices.deepseekHarnessAcp = {
    enable = true;

    # This host already had a harness home in interactive use under the
    # harness's own default (`~/.dsh`), holding its own settings, provider
    # routes, credentials and sessions. Adopt it instead of the module's
    # service-style default, which would orphan all of that.
    dshHome = "${config.home.homeDirectory}/.dsh";

    # Start ACP sessions on the route this host already selects as its default
    # (`agent-default-model` in ~/.dsh/settings.yaml). Zed's model selector can
    # still switch per session, including to the shared OpenCode routes below.
    provider = "ten-rings";
    model = "gpt-5.6-terra";

    # The launch environment has the highest precedence in the credential seam,
    # so these win over ~/.dsh/.credentials.yaml without deleting it.
    credentialsFiles = {
      DEEPSEEK_API_KEY = config.age.secrets.deepseek-api-key.path;
      OPENCODE_GO_API_KEY = config.age.secrets.opencode-api-key.path;
      OPENCODE_API_KEY = config.age.secrets.opencode-api-key.path;
      TEN_RINGS_API_KEY = config.age.secrets.ten-rings-api-key.path;
    };

    # This host can reach the ten-rings gateway and has its credential, so its
    # route and default model live in a host seed rather than the shared one,
    # which would advertise them on a host that cannot authenticate them.
    extraSettingsSeeds = [ ../../config/deepseek-harness/settings.seed.fedora-thinkbook.yaml ];

    # The OpenCode keys now exist on this host, so the shared routes are usable
    # and the bundle plus the seed routes that were switched off to keep dead
    # entries out of the model picker are enabled again.
    openCodeRoutes.enable = true;

    # The sandbox policy a session runs under. The automation-only ACP bridge
    # advertises no permission selector, so this is a launch fact rather than
    # something switchable per thread in Zed.
    permissionMode = "workspace-write";

    # Keep the OpenObserve MCP patch disabled until its Authorization value has
    # a file-backed source; an unauthenticated MCP server only adds noise.
    openObserveMcp.enable = false;
  };
}
