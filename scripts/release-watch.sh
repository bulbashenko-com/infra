#!/usr/bin/env bash
# Follows a release on main until Flux reports every production Kustomization as applied (commit statuses prod/<name>,
# posted by Flux, apps/staging-platform/notify.yaml), or one fails, or time runs out. Prints a one-line verdict and
# writes `state` (success|failure|timeout), `minutes` and `details` (HTML lines) to $GITHUB_OUTPUT when set.
# Usage: scripts/release-watch.sh <sha> <started-at RFC 3339> [timeout minutes, default 35]
set -euo pipefail
sha=${1:?usage: release-watch.sh <sha> <started-at> [timeout-minutes]}
started=${2:?}
limit=${3:-35}
repo=${GITHUB_REPOSITORY:-bulbashenko-com/infra}

# The Kustomizations Flux reports for: the event sources of the Alert prod-status (one list, no copy to keep in sync).
mapfile -t expected < <(yq -r 'select(.kind == "Alert" and .metadata.name == "prod-status") | .spec.eventSources[].name' \
  apps/staging-platform/notify.yaml | sed 's#^#prod/#')
[ ${#expected[@]} -gt 0 ] || { echo "no prod-status Alert in apps/staging-platform/notify.yaml" >&2; exit 1; }

deadline=$(( $(date +%s) + limit * 60 ))
state=timeout
while :; do
  statuses=$(gh api "repos/$repo/commits/$sha/statuses?per_page=100")
  done_count=0 failed=() details=()
  for ctx in "${expected[@]}"; do
    # The newest status per context comes first.
    s=$(jq -r --arg c "$ctx" '[.[] | select(.context == $c)][0] // empty | "\(.state)\t\(.description)\t\(.updated_at)"' <<<"$statuses")
    st=${s%%$'\t'*}
    case $st in
      success) done_count=$((done_count + 1)); details+=("✅ ${ctx#prod/}") ;;
      failure|error) failed+=("$ctx"); details+=("🔴 ${ctx#prod/}: $(cut -f2 <<<"$s")") ;;
      *) details+=("⏳ ${ctx#prod/}") ;;
    esac
  done
  if [ ${#failed[@]} -gt 0 ]; then state=failure; break; fi
  if [ "$done_count" -eq ${#expected[@]} ]; then state=success; break; fi
  if [ "$(date +%s)" -ge "$deadline" ]; then state=timeout; break; fi
  echo "$(date -u +%T) $done_count/${#expected[@]} applied"
  sleep 20
done

minutes=$(( ( $(date +%s) - $(date -d "$started" +%s) + 59 ) / 60 ))
printf '%s after %s min\n' "$state" "$minutes"
printf '%s\n' "${details[@]}"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "state=$state"
    echo "minutes=$minutes"
    echo "details<<EOF_DETAILS"
    printf '%s\n' "${details[@]}"
    echo "EOF_DETAILS"
  } >> "$GITHUB_OUTPUT"
fi
