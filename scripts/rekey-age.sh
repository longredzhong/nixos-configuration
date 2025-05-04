#!/usr/bin/env bash
set -euo pipefail

# --- Argument Parsing ---
identity_provided="" # Store explicitly provided identity
input_file=""
recipient_args=() # Store recipient args separately
current_user=$(whoami)
default_identities=(
    "/etc/ssh/ssh_host_ed25519_key"
    "/home/${current_user}/.ssh/id_ed25519"
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
    --host|--user|--key) # Collect recipient arguments
      recipient_args+=("$1")
      shift
      if [[ -z "${1:-}" || "$1" == --* ]]; then # Check value for recipient flag
         echo "Error: Missing value for ${recipient_args[-1]}" >&2; exit 1
      fi
      recipient_args+=("$1")
      shift
      ;;
    -*) # Handle unknown flags
      echo "Error: Unknown option '$1'" >&2
      echo "Usage: $0 <file.age> [--identity <keyfile>] [--host <h> | --user <u> | --key <k>]..." >&2
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
  echo "Usage: $0 <file.age> [--identity <keyfile>] [--host <h> | --user <u> | --key <k>]..." >&2
  exit 1
fi
if [[ ! -f "$input_file" || "${input_file##*.}" != "age" ]]; then
  echo "Error: '$input_file' not found or not a .age file." >&2
  exit 1
fi
# Identity validation happens during decryption attempt
if [[ ${#recipient_args[@]} -eq 0 ]]; then
    echo "Error: No new recipients specified. Use --host, --user, or --key." >&2
    exit 1
fi
# --- End Validation ---

tmp="$(mktemp --suffix=".decrypted")"
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

# Pass collected recipient arguments to get-age-keys.sh
echo "Getting new recipient keys..."
new_recipient_flags=$(./scripts/get-age-keys.sh "${recipient_args[@]}") # Pass the array correctly

if [[ -z "$new_recipient_flags" ]]; then
  echo "Error: Failed to get new recipient keys." >&2
  exit 1
fi

echo "Re-encrypting '$input_file' with new recipients..."
# Use eval to handle quoted keys correctly
eval age $new_recipient_flags -o "\"$input_file\"" "\"$tmp\""

echo "Rekey complete: '$input_file' updated with new recipients."
echo "IMPORTANT: Remember to update 'secrets/secrets.nix' with the new recipient list for this file."
