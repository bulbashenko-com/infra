#!/usr/bin/env bash
# Fails if a secret-bearing file is committed without SOPS encryption.
# Rules:
#   1. Every *.sops.yaml / *.sops.json / *.sops.env must carry SOPS metadata.
#   2. Any other YAML that declares `kind: Secret` is rejected: secrets live only in *.sops.yaml.
set -euo pipefail
status=0
files=("$@")
if [ ${#files[@]} -eq 0 ]; then
  mapfile -t files < <(git ls-files '*.yaml' '*.yml' '*.json' '*.env')
fi
for f in "${files[@]}"; do
  [ -f "$f" ] || continue
  case "$f" in
    *.sops.yaml|*.sops.yml|*.sops.json|*.sops.env)
      if ! grep -qE '(^sops:|"sops":|^sops_version=)' "$f"; then
        echo "NOT ENCRYPTED: $f"; status=1
      fi ;;
    *.yaml|*.yml)
      if grep -qE '^kind:[[:space:]]*Secret[[:space:]]*$' "$f"; then
        echo "PLAINTEXT Secret manifest (use *.sops.yaml): $f"; status=1
      fi ;;
  esac
done
exit $status
