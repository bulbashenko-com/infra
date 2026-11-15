#!/usr/bin/env bash
# One-time (owner, needs admin on the org): makes GitHub enforce the process in docs/workflow.md.
#   infra main: merge commits only; required checks = CI + dashboards/kubeconform/render + both staging verdicts.
#   infra dev:  CI + dashboards/kubeconform/render.
#   site:       auto-merge allowed, merge commits only, ruleset like auth's (PR + checks `check`, `build`).
# Guard: the staging verdicts become required only once Flux has posted both as success on dev's tip; requiring them
# earlier would block every release PR forever. Re-run after the first release if it stops there.
set -euo pipefail
org=bulbashenko-com
ci=(secrets tofu-fmt manifests yaml dashboards kubeconform render)

checks_json() { printf '%s\n' "$@" | jq -R '{context: .}' | jq -s .; }
# set_checks <repo> <ruleset id> <checks...>: replaces the required checks, merge methods = merge only.
set_checks() {
  local repo=$1 id=$2; shift 2
  gh api "repos/$org/$repo/rulesets/$id" |
    jq --argjson checks "$(checks_json "$@")" '{name, target, enforcement, conditions, bypass_actors,
      rules: [.rules[] |
        if .type == "required_status_checks" then .parameters.required_status_checks = $checks
        elif .type == "pull_request" then .parameters.allowed_merge_methods = ["merge"]
        else . end]}' |
    gh api -X PUT "repos/$org/$repo/rulesets/$id" --input - >/dev/null
  echo "$repo ruleset $id: $*"
}
ruleset_id() { gh api "repos/$org/$1/rulesets" -q ".[] | select(.name == \"$2\") | .id"; }

# infra dev
set_checks infra "$(ruleset_id infra 'dev branch')" "${ci[@]}"

# infra main: the staging verdicts only when they are live
tip=$(gh api "repos/$org/infra/commits/dev" -q .sha)
verdicts=$(gh api "repos/$org/infra/commits/$tip/status" -q '[.statuses[] | select(.context | startswith("staging/")) | select(.state == "success") | .context] | unique | join(" ")')
if [[ " $verdicts " == *" staging/auth-e2e "* && " $verdicts " == *" staging/site-e2e "* ]]; then
  set_checks infra "$(ruleset_id infra main)" "${ci[@]}" staging/auth-e2e staging/site-e2e
else
  set_checks infra "$(ruleset_id infra main)" "${ci[@]}"
  echo "NOT YET: staging/auth-e2e and staging/site-e2e are not both green on dev ${tip:0:7} (found: ${verdicts:-none})."
  echo "         They appear after the first release (Flux posts them). Run \`just rulesets\` again then."
fi

# site: like auth
gh api -X PATCH "repos/$org/site" -F allow_auto_merge=true -F allow_squash_merge=false -F allow_rebase_merge=false \
  -F allow_merge_commit=true >/dev/null
if [ -z "$(ruleset_id site main)" ]; then
  gh api "repos/$org/auth/rulesets/$(ruleset_id auth main)" |
    jq '{name, target, enforcement, conditions, bypass_actors: [],
         rules: [.rules[] |
           if .type == "required_status_checks" then .parameters.required_status_checks = [{context: "check"}, {context: "build"}]
           elif .type == "pull_request" then .parameters.allowed_merge_methods = ["merge"]
           else . end]}' |
    gh api -X POST "repos/$org/site/rulesets" --input - >/dev/null
fi
echo "site: auto-merge on, merge commits only, ruleset main requires check + build"
