#!/usr/bin/env bash
# Pins <app> to <sha> on dev: one commit, straight to dev, no PR. dev is staging; production (main) gets the pin
# with the next release (the PR dev -> main, see scripts/release-pr.sh).
#
# Usage: scripts/promote.sh <app> [sha]   (sha defaults to the app's latest main)
# Runs in .github/workflows/promote.yml with a GitHub App token (GH_TOKEN); the App may push to dev
# (ruleset bypass), so the commit is signed as the App and needs no git credentials.
# A request older than the current pin is skipped (dispatches can arrive out of order) unless FORCE=1,
# which manual runs set: that is how a rollback is done.
# DRY_RUN=1 prints the change and the commit message without writing anything (works with a read-only token).
set -euo pipefail

app=${1:?usage: promote.sh <app> [sha]}
sha=${2:-}
org=bulbashenko-com
infra=$org/infra
target=dev

# Where each app is pinned (all pins in the file must carry the same SHA), its image, and for
# Git-sourced apps the paths Flux reads (the GitRepository `ignore` list): other changes need no deploy.
image='' deploy_paths=''
case $app in
  site)      file=apps/production/site/kustomization.yaml; keys=newTag; image=ghcr.io/$org/site ;;
  auth)      file=clusters/hel1/auth.yaml; keys='commit|newTag'; image=ghcr.io/$org/auth-ui ;;
  mail)      file=clusters/hel1/mail.yaml; keys=commit; deploy_paths='^(kustomization\.yaml|deploy/k8s/)' ;;
  teamspeak) file=clusters/hel1/teamspeak.yaml; keys=commit; deploy_paths='^(kustomization\.yaml|deploy/k8s/)' ;;
  *) echo "unknown app: $app" >&2; exit 1 ;;
esac
pin_re="^([[:space:]]*(${keys}): )([0-9a-f]{40})$"

pinned() { sed -En "s/${pin_re}/\3/p" | sort -u; }
# compare <base> <head> -> identical | ahead | behind | diverged (head relative to base)
compare() { gh api "repos/$org/$app/compare/$1...$2" -q .status; }

[ -n "$sha" ] || sha=$(gh api "repos/$org/$app/commits/main" -q .sha)
[[ $sha =~ ^[0-9a-f]{40}$ ]] || { echo "not a full commit SHA: $sha" >&2; exit 1; }
case $(compare main "$sha") in
  identical|behind) ;;
  *) echo "$app@$sha is not on main" >&2; exit 1 ;;
esac
short=${sha:0:7}

if [ -n "$image" ] && ! docker manifest inspect "$image:$sha" >/dev/null 2>&1; then
  echo "image $image:$sha not found (did the app's image build finish?)" >&2; exit 1
fi

# One attempt against the current tip of $target; returns 2 when it moved underneath (retry).
# Called as `attempt || rc=$?`, where set -e does not apply: every API result is checked by hand.
fail() { echo "$*" >&2; exit 1; }
attempt() {
  local head current old cmp status subject msg content tree commit
  head=$(gh api "repos/$infra/git/ref/heads/$target" -q .object.sha) || fail "cannot read $target"
  current=$(gh api "repos/$infra/contents/$file?ref=$head" -q .content | base64 -d; echo x); current=${current%x}
  [ "$current" != "" ] || fail "cannot read $file at ${head:0:7}"

  mapfile -t pins < <(pinned <<<"$current")
  [ ${#pins[@]} -eq 1 ] || { echo "expected one pinned SHA in $file, found: ${pins[*]:-none}" >&2; exit 1; }
  old=${pins[0]}
  if [ "$sha" = "$old" ]; then echo "$app is already pinned to $short on $target"; return 0; fi

  cmp=$(gh api "repos/$org/$app/compare/$old...$sha") || fail "cannot compare $app ${old:0:7}...$short"
  status=$(jq -r .status <<<"$cmp")
  if [ "$status" = behind ] && [ -z "${FORCE:-}" ]; then
    echo "$app@$short is older than the pin ${old:0:7}; skipped (FORCE=1 to roll back)"; return 0
  fi
  if [ -n "$deploy_paths" ] && [ "$status" = ahead ] &&
     ! jq -r '.files[].filename' <<<"$cmp" | grep -qE "$deploy_paths"; then
    echo "$app ${old:0:7}..$short changes nothing Flux deploys; no commit"; return 0
  fi

  # Subject: the merged PR's title when there is one (merge commits say only "Merge pull request #N ...").
  subject=$(gh api "repos/$org/$app/commits/$sha/pulls" -q '.[0] // empty | "\(.title) (\(.html_url))"')
  [ -n "$subject" ] || subject=$(gh api "repos/$org/$app/commits/$sha" -q '.commit.message | split("\n")[0]')
  msg=$(
    echo "Deploy $app $short: $subject"
    echo
    case $status in
      behind)   echo "ROLLBACK from ${old:0:7}." ;;
      diverged) echo "${old:0:7} is not an ancestor of $short." ;;
      *)        jq -r '"\(.ahead_by) commit(s), \(.files | length) file(s) since '"${old:0:7}"':"' <<<"$cmp"
                jq -r '.commits | reverse | .[] | "- \(.sha[0:7]) \(.commit.message | split("\n")[0])"' <<<"$cmp" ;;
    esac
    echo
    echo "Source: https://github.com/$org/$app/compare/$old...$sha"
  )

  content=$(sed -E "s/${pin_re}/\1${sha}/" <<<"${current%$'\n'}"; echo x); content=${content%x}
  if [ -n "${DRY_RUN:-}" ]; then
    diff -u --label "a/$file" --label "b/$file" <(printf '%s' "$current") <(printf '%s' "$content") || true
    printf '\n--- commit message\n%s\n' "$msg"
    return 0
  fi

  tree=$(jq -n --arg base "$(gh api "repos/$infra/git/commits/$head" -q .tree.sha)" --arg path "$file" --arg content "$content" \
    '{base_tree: $base, tree: [{path: $path, mode: "100644", type: "blob", content: $content}]}' |
    gh api "repos/$infra/git/trees" --input - -q .sha) || fail "cannot create the tree"
  commit=$(jq -n --arg msg "$msg" --arg tree "$tree" --arg parent "$head" \
    '{message: $msg, tree: $tree, parents: [$parent]}' |
    gh api "repos/$infra/git/commits" --input - -q .sha) || fail "cannot create the commit"
  # Fast-forward only: if $target moved since we read it, start over on the new tip.
  if ! gh api -X PATCH "repos/$infra/git/refs/heads/$target" -f sha="$commit" -F force=false >/dev/null 2>&1; then
    return 2
  fi
  echo "$target: $(head -1 <<<"$msg") (${commit:0:7})"
}

for _ in 1 2 3 4 5; do
  rc=0; attempt || rc=$?
  [ $rc -eq 2 ] || exit $rc
  echo "$target moved; retrying" >&2
done
echo "$target kept moving; giving up" >&2; exit 1
