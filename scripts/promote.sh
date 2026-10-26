#!/usr/bin/env bash
# Opens (or refreshes) the production deploy PR that pins <app> to <sha>.
# One rolling PR per app on branch deploy/<app>: a newer commit replaces the pending one.
# The owner decides: merge = Flux deploys it, close = production keeps the current version.
#
# Usage: scripts/promote.sh <app> [sha]   (sha defaults to the app's latest main)
# Runs in .github/workflows/promote.yml with a GitHub App token (GH_TOKEN), so the PR gets CI.
# DRY_RUN=1 prints the change and the PR body without writing anything (works with a read-only token).
set -euo pipefail

app=${1:?usage: promote.sh <app> [sha]}
sha=${2:-}
org=bulbashenko-com
infra=$org/infra
branch=deploy/$app

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

mapfile -t pins < <(pinned < "$file")
[ ${#pins[@]} -eq 1 ] || { echo "expected one pinned SHA in $file, found: ${pins[*]:-none}" >&2; exit 1; }
old=${pins[0]}

[ -n "$sha" ] || sha=$(gh api "repos/$org/$app/commits/main" -q .sha)
[[ $sha =~ ^[0-9a-f]{40}$ ]] || { echo "not a full commit SHA: $sha" >&2; exit 1; }
case $(compare main "$sha") in
  identical|behind) ;;
  *) echo "$app@$sha is not on main" >&2; exit 1 ;;
esac
short=${sha:0:7}

if [ "$sha" = "$old" ]; then
  echo "$app is already at $short in production"; exit 0
fi

if [ -n "$image" ] && ! docker manifest inspect "$image:$sha" >/dev/null 2>&1; then
  echo "image $image:$sha not found (did the app's image build finish?)" >&2; exit 1
fi

cmp=$(gh api "repos/$org/$app/compare/$old...$sha")
status=$(jq -r .status <<<"$cmp")
if [ -n "$deploy_paths" ] && [ "$status" = ahead ] &&
   ! jq -r '.files[].filename' <<<"$cmp" | grep -qE "$deploy_paths"; then
  echo "$app ${old:0:7}..$short changes nothing Flux deploys; no PR"; exit 0
fi

# An open PR that already pins this commit or a newer one wins (dispatches can arrive out of order).
pr=$(gh pr list -R "$infra" --head "$branch" --state open --json number -q '.[0].number // empty')
if [ -n "$pr" ]; then
  queued=$(gh api "repos/$infra/contents/$file?ref=$branch" -q .content | base64 -d | pinned | head -1)
  if [ "$queued" = "$sha" ] || [ "$(compare "$sha" "$queued")" = ahead ]; then
    echo "PR #$pr already pins ${queued:0:7}; nothing to do"; exit 0
  fi
fi

# The new file content; the working tree is never modified.
content=$(sed -E "s/${pin_re}/\1${sha}/" "$file"; echo x); content=${content%x}

# PR text: what production gets compared to what it runs now.
# Subject: the merged PR's title when there is one (merge commits say only "Merge pull request #N ...").
subject=$(gh api "repos/$org/$app/commits/$sha/pulls" -q '.[0] // empty | "\(.title) (#\(.number))"')
[ -n "$subject" ] || subject=$(gh api "repos/$org/$app/commits/$sha" -q '.commit.message | split("\n")[0]')
title="Deploy $app $short: $subject"
[ ${#title} -le 100 ] || title="${title:0:97}..."
body=$(
  echo "Pins **$app** in production to [\`$short\`](https://github.com/$org/$app/commit/$sha): $subject"
  echo
  case $status in
    behind)   echo "> [!WARNING]"; echo "> **Rollback:** this commit is older than what production runs now."; echo ;;
    diverged) echo "> [!WARNING]"; echo "> Production runs \`${old:0:7}\`, which is not an ancestor of this commit."; echo ;;
  esac
  echo "| | |"
  echo "|---|---|"
  echo "| In production now | [\`${old:0:7}\`](https://github.com/$org/$app/commit/$old) |"
  echo "| After merge | [\`$short\`](https://github.com/$org/$app/commit/$sha) |"
  jq -r --arg url "https://github.com/$org/$app/compare/$old...$sha" '"| Diff | [" +
    (if .status == "behind" then "rolls back \(.behind_by) commit(s)"
     else "\(.ahead_by) commit(s), \(.files | length) file(s)" end) + "](\($url)) |"' <<<"$cmp"
  [ -z "$image" ] || echo "| Image | \`$image:$sha\` |"
  echo "| Pinned in | \`$file\` |"
  if [ "$status" = ahead ]; then
    echo
    echo "### Commits"
    echo
    jq -r '.commits | reverse | .[] |
      "- [`\(.sha[0:7])`](\(.html_url)) \(.commit.message | split("\n")[0]) (\(.author.login // .commit.author.name))"' <<<"$cmp"
  fi
  echo
  echo "Merge = Flux rolls it out on the next reconcile. Close = production stays on \`${old:0:7}\`;"
  echo "the next push to \`$app\` main opens a fresh PR. Opened by \`scripts/promote.sh\` (\`just promote $app [sha]\`)."
)
msg=$(printf 'Deploy %s %s\n\n%s\n\nSource: https://github.com/%s/%s/commit/%s\n' "$app" "$short" "$subject" "$org" "$app" "$sha")

if [ -n "${DRY_RUN:-}" ]; then
  diff -u --label "a/$file" --label "b/$file" "$file" - <<<"${content%$'\n'}" || true
  printf '\n--- title\n%s\n--- body\n%s\n' "$title" "$body"
  exit 0
fi

# Commit through the API: signed as the App, no git credentials needed. Parent = main as checked out.
tree=$(jq -n --arg base "$(git rev-parse 'HEAD^{tree}')" --arg path "$file" --arg content "$content" \
  '{base_tree: $base, tree: [{path: $path, mode: "100644", type: "blob", content: $content}]}' |
  gh api "repos/$infra/git/trees" --input - -q .sha)
commit=$(jq -n --arg msg "$msg" --arg tree "$tree" --arg parent "$(git rev-parse HEAD)" \
  '{message: $msg, tree: $tree, parents: [$parent]}' |
  gh api "repos/$infra/git/commits" --input - -q .sha)
if gh api "repos/$infra/git/ref/heads/$branch" >/dev/null 2>&1; then
  gh api -X PATCH "repos/$infra/git/refs/heads/$branch" -f sha="$commit" -F force=true >/dev/null
else
  gh api "repos/$infra/git/refs" -f ref="refs/heads/$branch" -f sha="$commit" >/dev/null
fi

if [ -n "$pr" ]; then
  gh pr edit "$pr" -R "$infra" --title "$title" --body "$body" >/dev/null
  echo "updated PR #$pr: $title"
else
  gh pr create -R "$infra" --base main --head "$branch" --title "$title" --body "$body" --label deploy
fi
