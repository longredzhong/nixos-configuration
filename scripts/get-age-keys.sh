#!/usr/bin/env bash
# filepath: /home/longred/nixos-configuration/dev-nixos/scripts/get-age-keys.sh
set -euo pipefail

# Assuming the script is run from the repo root where ./secrets/secrets.nix exists
secrets_file="./secrets/secrets.nix"

# Function to get a key using nix eval
get_key() {
    local type=$1 name=$2 key_path
    if [[ "$type" == "user" ]]; then
        key_path="keys.definedUsers.$name"
    else
        key_path="keys.definedHosts.$name"
    fi

    echo "[Debug] Evaluating JSON: (import ${secrets_file} {}).${key_path}" >&2
    local json keys
    json=$(nix eval --json --impure --expr "(import ${secrets_file} {}).${key_path}" \
                    2>/dev/null) || {
        echo "Error: cannot eval ${key_path}" >&2; exit 1
    }
    mapfile -t keys < <(echo "$json" | jq -r '.[]')
    if (( ${#keys[@]} == 0 )); then
        echo "Error: no keys for $type '$name'" >&2; exit 1
    fi
    for k in "${keys[@]}"; do
        k=$(echo "$k" | tr -d '\r\n')
        echo "[Debug] Retrieved key for $type '$name': $k" >&2
        echo "$k"
    done
}

recipients_args=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --host|--user)
            mode=$1; shift
            name=$1; shift
            # read each key line without word-splitting
            mapfile -t user_keys < <(get_key "${mode#--}" "$name")
            for key in "${user_keys[@]}"; do
                recipients_args+=(-r "$key")
                echo "[Debug] Added recipient: $key" >&2
            done
            ;;
        --key)
            shift
            if [[ -z "${1:-}" || "$1" == --* ]]; then echo "Error: Missing key for --key" >&2; exit 1; fi
            recipients_args+=(-r "$1")
            echo "[Debug] Added raw key recipient: $1" >&2 # Debug: Show added raw key
            shift
            ;;
        *)
            echo "Error: Unknown argument '$1'. Use --host <name>, --user <name>, or --key <age_key>." >&2
            exit 1
            ;;
    esac
done

if [[ ${#recipients_args[@]} -eq 0 ]]; then
    echo "Error: No recipients specified. Use --host <name>, --user <name>, or --key <age_key>." >&2
    exit 1
fi

# Output the constructed -r flags for the age command, quoting each key
quoted=""
for ((i=0; i<${#recipients_args[@]}; i+=2)); do
    # recipients_args[i] is "-r", [i+1] is the key (may contain a space)
    quoted+="${recipients_args[i]} \"${recipients_args[i+1]}\" "
done
echo "$quoted"