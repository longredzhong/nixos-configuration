# DeepSeek Harness ACP profile (Zed) for standalone Home Manager targets.
#
# The ACP server is the shipped `dsh --profile acp` stdio bridge. An ACP client
# (Zed) spawns it as a child process and talks newline-delimited JSON-RPC over
# stdin/stdout, so the agent MUST run on the machine that holds the checkout —
# there is no remote/network transport here.
#
# Layer split (see docs/deepseek-harness-acp.md):
#   - repository  : model seed, global memory, global patch layer, profile patch
#   - this module : npm runtime + profile composition + the `dsh` entry point
#   - host-local  : $DSH_HOME/sessions and $DSH_HOME/storages (never synced)
#
# Secret handling: nothing in this module, the Nix store or the patch files
# carries a credential value. `credentialsFiles` maps an environment variable
# name to a file whose content is the value; the launching environment has the
# highest precedence in the harness credential seam, so an agenix-managed file
# wins over $DSH_HOME/.credentials.yaml without ever being copied into the repo.
{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.hostServices.deepseekHarnessAcp;

  # Same runtime line as modules/host-services/deepseek-harness.nix; the two
  # modules intentionally agree on the layout so a host can adopt either
  # surface, or both, against one $DSH_HOME.
  #
  # dsh 0.1.6-alpha.2 boots profiles through node-addon-require-builtin, whose
  # native prebuild only recognizes the official nodejs.org V8 layout; nixpkgs'
  # nodejs build fails closed (`Unsupported/no-getter`). See
  # pkgs/nodejs-official. npm only drives `npm install`, so it stays on nixpkgs.
  node = pkgs.nodejs-official;
  npm = pkgs.nodejs-slim_22.npm;
  python = pkgs.python3.withPackages (ps: [ ps.pyyaml ]);

  profileDir = "${cfg.dshHome}/profiles/${cfg.profileName}";
  profileManifest = "${profileDir}/package.json";
  profilePatch = "${profileDir}/cordis.patch.yml";
  dshEntry = "${cfg.runtimeDir}/node_modules/@deepseek-ai/dsh/lib/bin.js";
  stampFile = "${cfg.dshHome}/.provision-stamp";

  sessionPluginName = "@longred/deepseek-harness-opencode-session";
  sessionPluginPath = "${pkgs.deepseek-harness-opencode-session}/lib/node_modules/${sessionPluginName}";

  # The opencode-session bundle registers the opencode-go-live-* routes from the
  # live provider catalog. Those routes — and the static opencode-go route in the
  # settings seed — authenticate through OPENCODE_GO_API_KEY. On a host without
  # that credential every one of them fails its first turn, which is worse than
  # not offering them: an ACP client remembers the last selected model, so one
  # visit to a dead route keeps failing new threads. `openCodeRoutes.enable`
  # therefore gates the bundle and the seed together.
  openCodePlugin = {
    name = sessionPluginName;
    path = sessionPluginPath;
  };

  # Which ACP transport answers the client.
  #
  # The shipped `dsh-acp-app` bridge is automation-only: it advertises no session
  # modes and no permission config option, so an editor renders no selector for
  # either. The enhanced bridge adds `permission_preset` (category `mode`),
  # `agent_preset` (`model_config`) and `plan_mode`, plus `session/load` and
  # image prompts.
  #
  # The enhanced bundle imports real runtime dependencies, and the profile loader
  # installs import routes only for importers inside the profile directory — a
  # symlinked plugin resolves from its store path and cannot find them. Hence
  # `copy = true`: provisioning copies this bundle instead of linking it.
  enhancedBridge = cfg.bridge == "enhanced";

  bridgePlugin =
    if enhancedBridge then
      {
        name = "dsh-acp-enhanced";
        path = "${pkgs.dsh-acp-enhanced}/lib/node_modules/dsh-acp-enhanced";
        copy = true;
      }
    else
      null;

  # The official bridge answers the client first, so an enhanced profile has to
  # drop it from the bundle layers or the enhanced transport never sees the
  # connection.
  removeBundles = lib.optionals enhancedBridge [ "@deepseek-ai/dsh-acp-app" ];

  # ...and switching back has to put it there again: removing a bundle is a
  # manifest edit, so the profile would otherwise keep whatever transport the
  # previous generation left, including none at all.
  ensureBundles =
    if enhancedBridge then
      [ "dsh-acp-enhanced" ]
    else
      [ "@deepseek-ai/dsh-acp-app" ];

  # The order of `dsh.profile.bundles` is load-bearing, not cosmetic: dsh folds
  # the list into an ordered stack of patch layers, and a layer that lands after
  # the ACP bridge is dropped from the composed profile. Measured on
  # 0.1.6-alpha.1, `[base, acp-app, <plugin>]` leaves the model routes
  # unregistered -- `session/new` fails with `no adapter registered for provider
  # "<route>"` -- while `[base, <plugin>, acp-app]` works.
  #
  # Provisioning can only append, and the profile template ships `[base,
  # acp-app]`, so a freshly created home gets exactly the broken order. That
  # makes the working order an accident of history: a home created by an older
  # generation keeps it, a new one does not. Declare the order here and let
  # provisioning normalize the manifest to it.
  desiredBundles =
    [ "@deepseek-ai/dsh-base" ]
    ++ lib.optional cfg.openCodeRoutes.enable sessionPluginName
    ++ lib.optionals enhancedBridge [ "dsh-acp-enhanced" ]
    ++ lib.optionals (!enhancedBridge) [ "@deepseek-ai/dsh-acp-app" ]
    ++ cfg.extraBundles;

  profilePlugins =
    lib.optional enhancedBridge bridgePlugin
    ++ lib.optionals cfg.openCodeRoutes.enable [ openCodePlugin ]
    ++ cfg.extraBundles;

  runtimeManifest = pkgs.writeText "deepseek-harness-package.json" ''
    {
      "private": true,
      "dependencies": {
        "@deepseek-ai/dsh": "${cfg.dshVersion}"
      }
    }
  '';

  # A patch replaces the targeted row's whole `config` (its name and inject list
  # survive), which is how the starting route is chosen. The enhanced bridge also
  # needs one host-scope row that dsh-web-app mounts but the bundle — written
  # against an older harness — does not: without it the `standard` and `cordis`
  # presets fail to mount with
  # `tool-subagent: modelSelectionSettings requires ... in the Host scope`.
  profilePatchFile = pkgs.writeText "deepseek-harness-acp-patch.yml" (
    ''
      # Generated from the Home Manager generation; edit the module, not this file.
    ''
    + (
      if enhancedBridge then
        ''
          - insert:
              - id: subagent-model-selection-settings
                name: '@deepseek-ai/dsh-tool-subagent/model-selection-settings'

          - id: acp-enhanced
            config:
              provider: ${cfg.provider}
              model: ${cfg.model}
              preset: ${cfg.agentPreset}
        ''
      else
        ''
          - id: acp
            config:
              provider: ${cfg.provider}
              model: ${cfg.model}
        ''
    )
  );

  # The home-level patch layer applies to EVERY profile on the machine. Keep it
  # to genuinely global rows: a patch naming an id a profile does not have only
  # warns, but it warns on every boot of that profile.
  globalPatchFile = pkgs.writeText "deepseek-harness-home-patch.yml" (
    ''
      # Generated from the Home Manager generation; edit the module, not this file.
      # $DSH_HOME/cordis.patch.yml — machine-global user patch layer.
    ''
    + (
      if cfg.openObserveMcp.enable then
        ''
          - insert:
              - id: mcp-openobserve
                name: '@deepseek-ai/dsh-mcp-client'
                config:
                  serverName: openobserve-mcp
                  transport: streamable-http
                  url: ${cfg.openObserveMcp.endpoint}
                  headers:
                    # !!js is evaluated at boot. The expression must not start with a
                    # backtick: js-yaml cannot resolve that scalar under this tag.
                    Authorization: !!js process.env.${cfg.openObserveMcp.credentialEnv}
                  toolCallTimeoutMs: 120000
                  # An unreachable OpenObserve must not abort harness boot.
                  failOnStartupError: false
        ''
      else
        "[]\n"
    )
  );

  globalMemory = ../../config/deepseek-harness/user-instructions.md;

  # Seeds are applied in order and a later seed wins a conflicting key. The base
  # seed defines the providers every host can authenticate; the opencode seed is
  # gated with the bundle that registers its dynamic routes, so a host without
  # those credentials never advertises a route that would fail every turn;
  # extra seeds carry host-specific routes and defaults.
  settingsSeeds =
    [ ../../config/deepseek-harness/settings.seed.yaml ]
    ++ lib.optionals cfg.openCodeRoutes.enable [
      ../../config/deepseek-harness/settings.seed.opencode.yaml
    ]
    ++ cfg.extraSettingsSeeds;

  # Everything whose content change must re-run provisioning. Keys are
  # compared as a hash so a version bump or a new bundle invalidates the stamp.
  provisionStamp = "${cfg.dshVersion}:${
    builtins.hashString "sha256" (
      builtins.toJSON profilePlugins
      + builtins.toJSON removeBundles
      + builtins.toJSON ensureBundles
      + builtins.toJSON desiredBundles
      + builtins.readFile profilePatchFile
      + builtins.readFile globalPatchFile
      + lib.concatMapStrings builtins.readFile settingsSeeds
    )
  }";

  provision = pkgs.writeShellScript "deepseek-harness-acp-provision" ''
    set -euo pipefail

    # npm is a separate nixpkgs output and resolves `node` through PATH.
    export PATH='${node}/bin:${npm}/bin:/usr/bin:/bin'

    runtime='${cfg.runtimeDir}'
    dsh_home='${cfg.dshHome}'
    entry='${dshEntry}'
    expected='${cfg.dshVersion}'
    stamp='${stampFile}'

    mkdir -p "$runtime" "$dsh_home/profiles"

    # Fast path: the runtime, the profile manifest and the generated inputs are
    # all already at the expected revision. This keeps the per-invocation cost
    # of the `dsh` wrapper to a couple of file reads.
    if [ -f "$stamp" ] && [ -x "$entry" ] && [ -f '${profileManifest}' ] && [ -f "$dsh_home/settings.yaml" ] \
       && [ "$(cat "$stamp")" = '${provisionStamp}' ]; then
      exit 0
    fi

    if [ ! -f "$runtime/package.json" ]; then
      install -m 0644 '${runtimeManifest}' "$runtime/package.json"
    fi

    installed=""
    if [ -f "$runtime/node_modules/@deepseek-ai/dsh/package.json" ]; then
      installed="$('${node}/bin/node' -e '
        const fs = require("node:fs");
        try {
          const manifest = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
          process.stdout.write(typeof manifest.version === "string" ? manifest.version : "");
        } catch (_) {
          process.exit(1);
        }
      ' "$runtime/node_modules/@deepseek-ai/dsh/package.json" 2>/dev/null || true)"
    fi

    if [ "$installed" != "$expected" ] || [ ! -x "$entry" ]; then
      echo "deepseek-harness: installing @deepseek-ai/dsh@$expected" >&2
      cd "$runtime"
      '${npm}/bin/npm' install \
        --omit=dev \
        --no-audit \
        --no-fund \
        --save-exact \
        "@deepseek-ai/dsh@$expected"
    fi

    # Initialize the shipped profile once. --dump-default-config writes nothing
    # to stdout we need; it only materializes $DSH_HOME/profiles/<name>/.
    if [ ! -f '${profileManifest}' ]; then
      echo "deepseek-harness: initializing profile '${cfg.profileName}'" >&2
      DSH_HOME="$dsh_home" \
        '${node}/bin/node' --expose-internals "$entry" \
        --profile '${cfg.profileName}' --dump-default-config >/dev/null
    fi

    DSH_PROFILE='${profileDir}' \
      DSH_PROFILE_MANIFEST='${profileManifest}' \
      DSH_PROFILE_PLUGINS='${builtins.toJSON profilePlugins}' \
      DSH_REMOVE_BUNDLES='${builtins.toJSON removeBundles}' \
      DSH_ENSURE_BUNDLES='${builtins.toJSON ensureBundles}' \
      DSH_DESIRED_BUNDLES='${builtins.toJSON desiredBundles}' \
      '${python}/bin/python3' - <<'PY'
    import json
    import os
    import pathlib
    import shutil
    import sys

    profile_dir = pathlib.Path(os.environ["DSH_PROFILE"])
    manifest_path = pathlib.Path(os.environ["DSH_PROFILE_MANIFEST"])
    plugins = json.loads(os.environ["DSH_PROFILE_PLUGINS"])
    remove_bundles = json.loads(os.environ["DSH_REMOVE_BUNDLES"])
    ensure_bundles = json.loads(os.environ["DSH_ENSURE_BUNDLES"])
    desired_bundles = json.loads(os.environ["DSH_DESIRED_BUNDLES"])

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    dependencies = manifest.setdefault("dependencies", {})
    profile = manifest.setdefault("dsh", {}).setdefault("profile", {})
    bundles = profile.setdefault("bundles", [])

    # Replace this bridge with another and the old one must go, or two
    # transports race for the same connection.
    for name in remove_bundles:
        if name in bundles:
            bundles.remove(name)
            print(f"deepseek-harness: dropped bundle {name}", file=sys.stderr)

    for name in ensure_bundles:
        if name not in bundles:
            bundles.append(name)
            print(f"deepseek-harness: restored bundle {name}", file=sys.stderr)

    def force_rmtree(path):
        """Remove a copied store tree; store permissions are read-only.

        The root has to be made writable too: `shutil.rmtree` unlinks entries
        from the directory it is removing, and a copied store directory keeps
        mode 0555.
        """
        os.chmod(path, 0o700, follow_symlinks=False)
        for root, dirs, files in os.walk(path):
            for entry in dirs + files:
                os.chmod(os.path.join(root, entry), 0o700, follow_symlinks=False)
        shutil.rmtree(path)

    # Reconcile rather than only append: a bundle this module added in an
    # earlier generation must disappear again when the option that pulled it in
    # is turned off. Only names this module recorded as its own are touched, so
    # a hand-added bundle is never removed.
    desired = [plugin["name"] for plugin in plugins]
    for stale in [name for name in profile.get("homeManagerPlugins", []) if name not in desired]:
        if stale in bundles:
            bundles.remove(stale)
        dependencies.pop(stale, None)
        stale_link = profile_dir / "node_modules" / stale
        if stale_link.is_symlink():
            stale_link.unlink()
        elif stale_link.exists():
            force_rmtree(stale_link)
        print(f"deepseek-harness: removed plugin {stale} no longer in the profile", file=sys.stderr)

    profile["homeManagerPlugins"] = desired

    for plugin in plugins:
        plugin_name = plugin["name"]
        plugin_path = pathlib.Path(plugin["path"])

        dependencies[plugin_name] = f"file:{plugin_path}"
        if plugin_name not in bundles:
            bundles.append(plugin_name)

        plugin_link = profile_dir / "node_modules" / plugin_name
        if plugin.get("copy"):
            # A bundle that imports packages the profile loader only resolves
            # for importers inside the profile directory has to be a real copy:
            # a symlink resolves from its store path and cannot find them.
            if plugin_link.is_symlink():
                plugin_link.unlink()
            elif plugin_link.exists():
                force_rmtree(plugin_link)
            plugin_link.parent.mkdir(parents=True, exist_ok=True)
            shutil.copytree(plugin_path, plugin_link)
            # Store trees are read-only; a later generation has to be able to
            # replace this copy, and the root is one of the directories whose
            # mode a copy preserves.
            os.chmod(plugin_link, 0o755)
            for root, dirs, files in os.walk(plugin_link):
                for entry in dirs:
                    os.chmod(os.path.join(root, entry), 0o755)
                for entry in files:
                    os.chmod(os.path.join(root, entry), 0o644)
            continue

        if plugin_link.is_symlink():
            if plugin_link.resolve() != plugin_path.resolve():
                plugin_link.unlink()
        elif plugin_link.exists():
            raise SystemExit(
                "deepseek-harness: refusing to replace an existing custom plugin at "
                f"{plugin_link}"
            )

        plugin_link.parent.mkdir(parents=True, exist_ok=True)
        if not plugin_link.exists():
            plugin_link.symlink_to(plugin_path, target_is_directory=True)

    # Normalize the order last, after every step that can append: the declared
    # stack is load-bearing (see `desiredBundles`). Names this module does not
    # own keep whatever position they had, after the declared ones.
    ordered = [name for name in desired_bundles if name in bundles]
    ordered += [name for name in bundles if name not in ordered]
    if ordered != bundles:
        print(
            "deepseek-harness: reordered bundles to " + ", ".join(ordered),
            file=sys.stderr,
        )
        bundles[:] = ordered

    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    PY

    # Generated configuration. Compare before writing so a steady-state switch
    # does not churn mtimes (the harness watches some of these paths).
    for pair in '${profilePatchFile}:${profilePatch}' '${globalPatchFile}:${cfg.dshHome}/cordis.patch.yml'; do
      src="''${pair%%:*}"
      dst="''${pair#*:}"
      if ! cmp -s "$src" "$dst"; then
        echo "deepseek-harness: updating $dst" >&2
        install -m 0644 "$src" "$dst"
      fi
    done

    # Apply the repository seeds to settings.yaml. Keys a seed mentions are owned
    # by the repository and overwrite what is on disk; keys no seed mentions are
    # left alone. That makes the model configuration reproducible without taking
    # over runtime-owned state: the opencode-session bundle's managed routes, UI
    # preferences and each host's own agent-default-model all survive. For the
    # same reason the file is never a store symlink and never rewritten
    # wholesale.
    DSH_SETTINGS='${cfg.dshHome}/settings.yaml' \
      DSH_SEEDS='${builtins.toJSON settingsSeeds}' \
      '${python}/bin/python3' - <<'PY'
    import json
    import os
    import pathlib
    import re
    import sys

    import yaml

    # The harness parses settings.yaml with js-yaml's JSON_SCHEMA, where only
    # true/false are booleans. PyYAML's default resolver follows YAML 1.1 and
    # reads a bare `off:` as boolean false, which would silently rename a
    # thinking-level key into `false` and make the whole provider route fail
    # validation. Load with the harness's dialect instead. (Dumping is already
    # safe: SafeDumper quotes any string its own resolver would read as a
    # non-string.)
    class HarnessLoader(yaml.SafeLoader):
        pass

    HarnessLoader.yaml_implicit_resolvers = {
        char: [(tag, regexp) for (tag, regexp) in resolvers if tag != "tag:yaml.org,2002:bool"]
        for char, resolvers in yaml.SafeLoader.yaml_implicit_resolvers.items()
    }
    HarnessLoader.add_implicit_resolver(
        "tag:yaml.org,2002:bool",
        re.compile(r"^(?:true|True|TRUE|false|False|FALSE)$"),
        list("tTfF"),
    )

    def load_settings(path):
        return yaml.load(path.read_text(encoding="utf-8"), Loader=HarnessLoader) or {}

    live_path = pathlib.Path(os.environ["DSH_SETTINGS"])
    seed_paths = [pathlib.Path(entry) for entry in json.loads(os.environ["DSH_SEEDS"])]

    if not live_path.exists():
        live_path.parent.mkdir(parents=True, exist_ok=True)
        live_path.write_text("{}\n", encoding="utf-8")
        live_path.chmod(0o600)
        print("deepseek-harness: created settings.yaml", file=sys.stderr)

    try:
        live = load_settings(live_path)
    except Exception as error:
        print(f"deepseek-harness: leaving unparsable settings.yaml alone ({error})", file=sys.stderr)
        raise SystemExit(0)

    if not isinstance(live, dict):
        print("deepseek-harness: settings.yaml is not a mapping; leaving it alone", file=sys.stderr)
        raise SystemExit(0)

    def apply_seed(dst, src, prefix=""):
        """Seed wins a conflict; keys the seed does not mention are untouched."""
        changed = []
        for key, value in src.items():
            path = f"{prefix}{key}"
            if isinstance(value, dict) and isinstance(dst.get(key), dict):
                changed.extend(apply_seed(dst[key], value, prefix=f"{path}."))
            elif key not in dst or dst[key] != value:
                dst[key] = value
                changed.append(path)
        return changed

    changed = []
    for seed_path in seed_paths:
        changed.extend(apply_seed(live, load_settings(seed_path)))

    if not changed:
        raise SystemExit(0)

    live_path.write_text(
        yaml.safe_dump(live, sort_keys=False, default_flow_style=False, allow_unicode=True, width=100),
        encoding="utf-8",
    )
    live_path.chmod(0o600)
    print("deepseek-harness: applied seed keys: " + ", ".join(changed), file=sys.stderr)
    PY

    test -f "$entry"
    ${lib.optionalString cfg.openCodeRoutes.enable "test -f '${sessionPluginPath}/package.json'"}
    printf '%s' '${provisionStamp}' > "$stamp"
    chmod 0600 "$stamp"
  '';

  # `dsh` is the single entry point: provision on demand (fast path first),
  # export credentials from their protected files, then exec the harness.
  #
  # stdout is reserved for whatever the invoked profile emits — for `--profile
  # acp` that is newline-delimited ACP JSON-RPC and nothing else, so every
  # provisioning message above is written to stderr.
  #
  # Two traps make a naive `export VAR="$(cat "$file")"` wrong here:
  #   - agenix publishes secrets under $XDG_RUNTIME_DIR, which is unset for a
  #     non-login launch (an editor started from a desktop entry, a plain ssh
  #     command), so the directory has to be resolved explicitly;
  #   - `export` reports its own status rather than the command substitution's,
  #     so a failed `cat` under `set -e` still "succeeds" and leaves the
  #     variable empty — which then surfaces much later as a confusing
  #     MISSING_CREDENTIAL instead of a missing file.
  credentialExports = lib.optionalString (cfg.credentialsFiles != { }) ''
    : "''${XDG_RUNTIME_DIR:=/run/user/$(id -u)}"
    export XDG_RUNTIME_DIR

    read_secret() {
      if [ ! -r "$1" ]; then
        echo "deepseek-harness: cannot read credential file $1" >&2
        exit 1
      fi
      cat "$1"
    }

    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (env: file: ''export ${env}="$(read_secret "${file}")"'') cfg.credentialsFiles
    )}
  '';

  dshWrapper = pkgs.writeShellScriptBin "dsh" ''
    set -eu

    # The harness home here is not the built-in default (~/.dsh), so every
    # entry point — an ACP client, a terminal, a headless run — has to be told
    # explicitly. Relying on the caller to set it would silently start the
    # harness against an empty home with no profiles and no settings.
    export DSH_HOME='${cfg.dshHome}'

    # Sandbox and approval policy are launch facts for this bridge: it has no
    # ACP mode or permission config option, so this is where they are set.
    export DSH_PERMISSION_MODE='${cfg.permissionMode}'

    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: value: "export ${name}=${lib.escapeShellArg value}") cfg.proxyEnvironment
    )}

    lock='${cfg.dshHome}/.provision.lock'
    if command -v flock >/dev/null 2>&1; then
      flock -w 900 "$lock" '${provision}' 1>&2
    else
      '${provision}' 1>&2
    fi

    ${credentialExports}

    exec '${node}/bin/node' --expose-internals '${dshEntry}' "$@"
  '';
in
{
  options.hostServices.deepseekHarnessAcp = {
    enable = lib.mkEnableOption "the DeepSeek Harness ACP stdio profile and the `dsh` entry point";

    dshVersion = lib.mkOption {
      type = lib.types.str;
      default = "0.1.6-alpha.2";
      description = "Pinned @deepseek-ai/dsh version installed into the user runtime.";
    };

    dshHome = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.local/share/deepseek-harness/home";
      description = ''
        Harness home holding settings, credentials, profiles and session logs.

        The default matches the web module's service-style home. Point it at
        `~/.dsh` (the harness's own default) to adopt a home that was already
        in interactive use on the host: the harness resolves `$DSH_HOME`, then
        falls back to `~/.dsh`, so leaving this at the service-style default on
        such a host silently starts the harness against an empty home and
        orphans the existing settings, credentials and sessions.
      '';
    };

    runtimeDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.local/share/deepseek-harness/runtime";
      description = "npm install root for the harness distribution.";
    };

    profileName = lib.mkOption {
      type = lib.types.str;
      default = "acp";
      description = "Profile under $DSH_HOME/profiles that the ACP client boots.";
    };

    bridge = lib.mkOption {
      type = lib.types.enum [
        "official"
        "enhanced"
      ];
      default = "official";
      description = ''
        ACP transport that answers the client.

        `official` is the shipped automation-only bridge: streaming, tool cards,
        a model selector and a thought-level selector, plus a per-tool-call
        allow/reject prompt. It advertises no session mode and no permission
        option, so an editor shows no selector for either.

        `enhanced` uses dsh-acp-enhanced, which adds `permission_preset`
        (category `mode`), `agent_preset` (`model_config`) and `plan_mode`, plus
        session/load and image prompts. It composes every session from an agent
        preset instead of the base rows, so the tool and prompt set is chosen by
        `agentPreset`.
      '';
    };

    agentPreset = lib.mkOption {
      type = lib.types.str;
      default = "standard";
      description = ''
        Agent preset the enhanced bridge composes sessions from. The harness
        ships `standard`, `minimal`, `ptc` and `cordis`; `standard` restores the
        instruction, bash, filesystem and skill rows that the enhanced bundle
        disables in the base layer, including the user-global AGENTS.md.
      '';
    };

    provider = lib.mkOption {
      type = lib.types.str;
      default = "opencode-go-live-chat";
      description = ''
        Provider route an ACP session starts on. A route registered by a plugin
        bundle is only available when that bundle is in `extraBundles`.
      '';
    };

    model = lib.mkOption {
      type = lib.types.str;
      default = "deepseek-v4.1-flash";
      description = "Model an ACP session starts on.";
    };

    permissionMode = lib.mkOption {
      type = lib.types.enum [
        "read-only"
        "workspace-write"
        "danger-full-access"
      ];
      default = "workspace-write";
      description = ''
        Harness sandbox and approval mode for every session this host starts,
        exported as DSH_PERMISSION_MODE.

        The automation-only ACP bridge advertises no permission or mode config
        option, so an ACP client cannot switch this per thread: it is a launch
        fact here. `danger-full-access` also pins the approval policy to
        `never`, which means tool calls run without prompting. Expose the
        selector inside the editor only by composing a richer ACP bridge.
      '';
    };

    proxyEnvironment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        HTTP_PROXY = "http://127.0.0.1:7890";
        HTTPS_PROXY = "http://127.0.0.1:7890";
        NO_PROXY = "localhost,127.0.0.1,::1";
      };
      description = ''
        Extra environment variables exported before the harness starts.

        Use this for an HTTP proxy: the harness skips a `socks5://` URL rather
        than failing, so a SOCKS-only listener silently leaves every request
        direct. Loopback is always direct, and `NO_PROXY` matches host and
        domain suffixes only — CIDR ranges do not work.
      '';
    };

    credentialsFiles = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        DEEPSEEK_API_KEY = "/run/agenix/deepseek-api-key";
      };
      description = ''
        Environment variables exported before the harness starts, each read
        from a file. The launching environment has the highest precedence in
        the credential seam, so these win over $DSH_HOME/.credentials.yaml.
        Leave empty to let the harness use its own credential store.

        The value is a shell string, not a Nix path: an agenix secret resolves
        to `''${XDG_RUNTIME_DIR}/agenix/<name>`, which only becomes absolute
        once the launching shell expands it, so it is expanded by the wrapper
        at run time.
      '';
    };

    extraBundles = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Package name of the bundle.";
            };
            path = lib.mkOption {
              type = lib.types.path;
              description = "Store path added to the profile as a file: dependency.";
            };
          };
        }
      );
      default = [ ];
      description = "Additional profile bundles, appended after the built-in ones.";
    };

    openCodeRoutes = {
      enable = lib.mkEnableOption ''
        the shared OpenCode provider routes: the opencode-session bundle that
        registers opencode-go-live-* from the live catalog, and the static
        opencode-go / opencode routes from the settings seed.

        Enable this only on a host that can resolve OPENCODE_GO_API_KEY and
        OPENCODE_API_KEY. Without them every offered route fails its first turn
        with MISSING_CREDENTIAL, and because an ACP client remembers the last
        selected model, one selection of a dead route keeps failing new threads
        until it is changed back
      '';
    };

    extraSettingsSeeds = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      example = [ ../../config/deepseek-harness/settings.seed.fedora-thinkbook.yaml ];
      description = ''
        Host-specific settings seeds, applied after the shared ones; a later
        seed wins a conflicting key. Use this for a provider only this host can
        authenticate (its own gateway) or for its default model, instead of
        putting it in the shared seed where a host without those credentials
        would advertise a route that fails every turn.
      '';
    };

    openObserveMcp = {
      enable = lib.mkEnableOption "the OpenObserve MCP server in the global patch layer";

      endpoint = lib.mkOption {
        type = lib.types.str;
        default = "http://100.100.10.1:5080/api/default/mcp";
        description = "Streamable HTTP endpoint of the OpenObserve MCP server.";
      };

      credentialEnv = lib.mkOption {
        type = lib.types.str;
        default = "OPENOBSERVE_MCP_AUTH";
        description = ''
          Variable holding the complete Authorization header value. The global
          patch references the variable name only; provide the value through
          `credentialsFiles`.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      node
      dshWrapper
    ];

    # The user-global instruction file. The harness only reads it, so a store
    # symlink is safe; the repository stays the source of truth.
    home.file."${cfg.dshHome}/AGENTS.md".source = globalMemory;

    # Warm the npm runtime and profile at login so the first ACP session does
    # not pay for a network install inside the editor.
    systemd.user.services.deepseek-harness-runtime = {
      Unit = {
        Description = "Provision the DeepSeek Harness runtime and ${cfg.profileName} profile";
        After = [ "network-online.target" ];
        Wants = [ "network-online.target" ];
      };
      Service = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = provision;
        TimeoutStartSec = "15min";
        UMask = "0077";
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
