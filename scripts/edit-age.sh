#!/usr/bin/env bash
set -euo pipefail

# --- Argument Parsing ---
identity_provided="" # Store explicitly provided identity
input_file=""
current_user=$(whoami)
default_identities=(
    "/home/${current_user}/.ssh/id_ed25519"
    "/etc/ssh/ssh_host_ed25519_key"
)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --identity)
      shift
      if [[ -z "${1:-}" || "$1" == --* ]]; then
        echo "Error: Missing keyfile for --identity" >&2; exit 1
      fi
      identity_provided="$1"
      shift
      ;;
    -*) # Handle unknown flags
      echo "Error: Unknown option '$1'" >&2
      echo "Usage: $0 <file.age> [--identity <keyfile>]" >&2
      exit 1
      ;;
    *) # Assume the first non-flag argument is the input file
      if [[ -z "$input_file" ]]; then
        input_file="$1"
      else
        echo "Warning: Ignoring unexpected argument '$1'" >&2
      fi
      shift
      ;;
  esac
done

# --- Validation ---
if [[ -z "$input_file" ]]; then
  echo "Error: Input file <file.age> is required." >&2
  echo "Usage: $0 <file.age> [--identity <keyfile>]" >&2
  exit 1
fi
if [[ ! -f "$input_file" || "${input_file##*.}" != "age" ]]; then
  echo "Error: '$input_file' not found or not a .age file." >&2
  exit 1
fi
# Identity validation happens during decryption attempt
# --- End Validation ---

# use only the base name (no path) for suffix
filename=$(basename "$input_file" .age)
tmp="$(mktemp --suffix=".$filename")"
trap 'rm -f "$tmp"' EXIT

# --- Decryption Logic ---
decryption_successful=false
identity_to_use=""

if [[ -n "$identity_provided" ]]; then
    # Use explicitly provided identity
    if [[ ! -f "$identity_provided" ]]; then
        echo "Error: Specified identity file '$identity_provided' not found." >&2
        exit 1
    fi
    echo "Attempting decryption of '$input_file' → '$tmp' using specified identity '$identity_provided'"
    if age -d -i "$identity_provided" -o "$tmp" "$input_file" 2>/dev/null; then
        decryption_successful=true
        identity_to_use="$identity_provided"
        echo "Decryption successful with '$identity_to_use'."
    else
        echo "Error: Decryption failed with specified identity '$identity_provided'." >&2
        exit 1
    fi
else
    # Try default identities
    echo "No specific identity provided, trying defaults..."
    found_default=false
    for default_id in "${default_identities[@]}"; do
        if [[ -f "$default_id" ]]; then
            found_default=true
            echo "Attempting decryption of '$input_file' → '$tmp' using default identity '$default_id'"
            if age -d -i "$default_id" -o "$tmp" "$input_file" 2>/dev/null; then
                decryption_successful=true
                identity_to_use="$default_id"
                echo "Decryption successful with '$identity_to_use'."
                break # Stop trying once successful
            else
                echo "Decryption failed with '$default_id'."
            fi
        else
             echo "Default identity '$default_id' not found, skipping."
        fi
    done

    if ! $found_default; then
         echo "Error: None of the default identity files found: ${default_identities[*]}" >&2
         exit 1
    fi

    if ! $decryption_successful; then
        echo "Error: Decryption failed with all tried default identities." >&2
        exit 1
    fi
fi
# --- End Decryption Logic ---

orig_sum=$(sha256sum "$tmp" | cut -d' ' -f1)
${EDITOR:-nano} "$tmp"
new_sum=$(sha256sum "$tmp" | cut -d' ' -f1)

if [[ "$orig_sum" == "$new_sum" ]]; then
  echo "No changes detected. Original file '$input_file' remains untouched."
  exit 0
fi

echo "File modified. Re-encrypting '$input_file' with original recipients..."

# --- Get original recipients ---
# Use the full input filename (e.g., tmp.age) as the key for recipientMap
secret_name=$(basename "$input_file")
nix_expr="(import ./secrets/secrets.nix {}).recipientMap.\"${secret_name}\""
echo "[Debug] Evaluating Nix for original keys: ${nix_expr}" >&2

mapfile -t original_keys < <(
  nix eval --json --impure --expr "${nix_expr}" 2>/dev/null | jq -r '.[]'
)

if (( ${#original_keys[@]} == 0 )); then
  echo "Error: Could not find original recipients for '${secret_name}' in secrets.nix." >&2
  echo "Please ensure 'recipientMap.\"${secret_name}\"' is defined correctly." >&2
  exit 1
fi

# Convert original keys to --key arguments for get-age-keys.sh
key_args=()
for k in "${original_keys[@]}"; do
    key_args+=(--key "$k")
done

echo "[Debug] Reconstructing recipient flags with args: ${key_args[*]}" >&2
recipient_flags=$(./scripts/get-age-keys.sh "${key_args[@]}")

if [[ -z "$recipient_flags" ]]; then
  echo "Error: Failed to reconstruct recipient flags using get-age-keys.sh." >&2
  exit 1
fi
# --- End Get original recipients ---

echo "Re-encrypting with original recipients..."
# Use eval to handle quoted keys correctly, consistent with encrypt/rekey
eval age $recipient_flags -o "\"$input_file\"" "\"$tmp\""

echo "Edit complete: '$input_file' updated."
