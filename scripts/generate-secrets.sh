#!/usr/bin/env bash
set -euo pipefail
umask 077

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
deployment_root=$(cd -- "$script_dir/.." && pwd)
secret_dir="$deployment_root/secrets"

command -v openssl >/dev/null 2>&1 || {
  echo "openssl is required to generate deployment secrets" >&2
  exit 1
}

mkdir -p "$secret_dir"
for name in db_root_password admin_password; do
  path="$secret_dir/$name.txt"
  if [[ -e "$path" ]]; then
    echo "preserving existing secrets/$name.txt"
    continue
  fi
  openssl rand -base64 36 | tr -d '\n' >"$path"
  printf '\n' >>"$path"
  chmod 0600 "$path"
  echo "created secrets/$name.txt"
done
