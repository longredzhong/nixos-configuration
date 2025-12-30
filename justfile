# NixOS Configuration Justfile
# ============================
# Usage: just <command> [args]
# Default host/target: current hostname/user

DEFAULT_USER := `whoami`
DEFAULT_HOST := `hostname`
DEFAULT_TARGET := `printf '%s@%s' "$(whoami)" "$(hostname)"`

# Show all commands
default:
    @just --list

# ============================================================
# Checks & Evaluation
# ============================================================

# Full flake check
check:
    nix flake check --option eval-cache true --accept-flake-config

# Fast evaluation only (recommended for development)
check-fast:
    nix flake check --no-build --no-update-lock-file --option eval-cache true --accept-flake-config

# Evaluate single NixOS host
eval-host host=DEFAULT_HOST:
    @nix eval ".#nixosConfigurations.{{host}}.config.system.build.toplevel.drvPath"

# Evaluate single Home Manager target
eval-home target=DEFAULT_TARGET:
    @nix eval ".#homeConfigurations.{{target}}.activationPackage.drvPath"

# ============================================================
# NixOS System
# ============================================================

# Build system configuration
build host=DEFAULT_HOST:
    nixos-rebuild build --flake .#{{host}}

# Build and switch system
switch host=DEFAULT_HOST:
    sudo -E nixos-rebuild switch --flake .#{{host}}

# Build and switch on next boot
boot host=DEFAULT_HOST:
    sudo -E nixos-rebuild boot --flake .#{{host}}

# Test in VM
vm host=DEFAULT_HOST:
    nixos-rebuild build-vm --flake .#{{host}}

# Rollback to previous generation
rollback:
    sudo nixos-rebuild --rollback switch

# List system generations
list-generations:
    sudo nix-env --list-generations --profile /nix/var/nix/profiles/system

# ============================================================
# Home Manager (standalone, for non-NixOS)
# ============================================================

HM := "github:nix-community/home-manager"
NIXCMD := "nix --extra-experimental-features 'nix-command flakes'"

# Build Home Manager activation package
hm-build target=DEFAULT_TARGET:
    {{NIXCMD}} build .#homeConfigurations.{{target}}.activationPackage -L

# Preview changes (dry run)
hm-dry-run target=DEFAULT_TARGET:
    {{NIXCMD}} run {{HM}} -- switch --flake .#{{target}} --dry-run

# Switch with backup
hm-switch target=DEFAULT_TARGET:
    {{NIXCMD}} run {{HM}} -- switch --flake .#{{target}} -b backup

# Switch without backup
hm-switch-force target=DEFAULT_TARGET:
    {{NIXCMD}} run {{HM}} -- switch --flake .#{{target}}

# Rollback Home Manager
hm-rollback:
    {{NIXCMD}} run {{HM}} -- rollback

# List Home Manager generations
hm-generations:
    {{NIXCMD}} run {{HM}} -- generations

# ============================================================
# Maintenance
# ============================================================

# Update all flake inputs
update:
    nix flake update

# Update specific input
update-input input:
    nix flake lock --update-input {{input}}

# Format all nix files
fmt:
    nixfmt .

# Garbage collect
gc:
    sudo nix-collect-garbage -d

# Delete old generations only
gc-old:
    sudo nix-collect-garbage --delete-old

# Show nixosConfigurations
show-systems:
    nix flake show --json | jq '.nixosConfigurations'

# Show homeConfigurations
show-homes:
    nix flake show --json | jq '.homeConfigurations'

# ============================================================
# Secrets (agenix)
# ============================================================

# List secrets/keys
secret-list type="all" filter="all":
    ./scripts/secretctl.py list {{type}} --filter {{filter}}

# Generate new keypair
secret-generate type name:
    ./scripts/secretctl.py generate {{type}} {{name}}

# Edit secret file
secret-edit file identity="":
    ./scripts/secretctl.py edit {{file}} {{if identity != "" { "--identity " + identity } else { "" } }}

# Check secrets consistency
secret-check:
    ./scripts/secretctl.py check

# Safe switch (check secrets first)
switch-safe host=DEFAULT_HOST:
    just secret-check && just switch {{host}}
