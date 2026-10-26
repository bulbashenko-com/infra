#!/usr/bin/env bash
# Keeps the release PR dev -> main open with a current description, and back-merges hotfixes.
# dev is staging (everything lands there), main is production (what the hel1 cluster runs); merging the release
# PR is the release. Runs in .github/workflows/release.yml after every push to dev or main.
# DRY_RUN=1 prints the PR text instead of writing.
set -euo pipefail

repo=bulbashenko-com/infra
owner=bulbashenko
git fetch -q origin dev main

# Hotfixes merged straight into main go back to dev through a short-lived branch (never main itself as the
# head). Release merges are merge commits and are skipped by --no-merges, so they never trigger this.
hotfixes=$(git rev-list --no-merges origin/dev..origin/main)
if [ -n "$hotfixes" ] && [ -z "${DRY_RUN:-}" ]; then
  tip=$(git rev-parse origin/main)
  branch=backmerge/${tip:0:7}
  if ! gh pr list -R "$repo" --base dev --state open --json headRefName -q '.[].headRefName' | grep -qx "$branch"; then
    gh api "repos/$repo/git/refs" -f ref="refs/heads/$branch" -f sha="$tip" >/dev/null
    pr=$(gh pr create -R "$repo" --base dev --head "$branch" --title "Back-merge main ${tip:0:7}" \
      --body "Hotfixes merged straight into \`main\` (production), brought back to \`dev\` so the next release keeps them.")
    gh pr merge "$pr" --auto --merge
  fi
fi

mapfile -t commits < <(git log --first-parent --format='%H%x09%s' origin/main..origin/dev)
pr=$(gh pr list -R "$repo" --base main --head dev --state open --json number -q '.[0].number // empty')
if [ ${#commits[@]} -eq 0 ]; then
  echo "main has everything on dev"; exit 0
fi

deploys=() changes=()
for c in "${commits[@]}"; do
  sha=${c%%$'\t'*} subject=${c#*$'\t'}
  if [[ $subject =~ ^Merge\ pull\ request\ \#([0-9]+) ]]; then
    n=${BASH_REMATCH[1]} t=$(gh pr view "$n" -R "$repo" --json title -q .title)
    if [[ $t == Deploy\ * ]]; then deploys+=("- $t (#$n)"); else changes+=("- $t (#$n)"); fi
  elif [[ $subject == Deploy\ * ]]; then
    deploys+=("- ${subject} (${sha:0:7})")
  else
    changes+=("- ${subject} (${sha:0:7})")
  fi
done

files=$(git diff --name-only origin/main origin/dev)
# What staging already ran: apps/staging and the shared apps/base. Docs and the CI tooling (live on dev already)
# and repo metadata (dotfiles) are not deployed. Everything else first takes effect in production with this
# release; list it by directory.
prod_only=$(grep -vE '^(apps/staging/|apps/base/|\.github/|scripts/|justfile$|\.[^/]+$|.*\.md$)' <<<"$files" |
  awk -F/ '{ print (NF > 2 ? $1 "/" $2 "/" : NF == 2 ? $1 "/" : $0) }' | sort -u || true)

title="Release: ${#commits[@]} change(s) since $(git log -1 --format=%cs origin/main)"
body=$(
  echo "Всё, что накопилось в \`dev\` (staging) с прошлого релиза. **Merge = релиз в prod**: Flux раскатит \`main\`."
  echo
  if [ ${#deploys[@]} -gt 0 ]; then echo "### Приложения"; printf '%s\n' "${deploys[@]}"; echo; fi
  if [ ${#changes[@]} -gt 0 ]; then echo "### Изменения"; printf '%s\n' "${changes[@]}"; echo; fi
  if [ -n "$prod_only" ]; then
    echo "> [!WARNING]"
    echo "> В staging не проверялось, впервые применится в prod этим релизом:"
    sed 's/^/> - `/; s/$/`/' <<<"$prod_only"
    echo
  fi
  if grep -q '^terraform/' <<<"$files"; then
    echo "> [!NOTE]"
    echo "> Есть изменения в \`terraform/\`: план — в комментарии OpenTofu ниже; CI применит его после мержа."
    echo
  fi
  echo "Метод мержа — только merge commit (история нужна, чтобы следующий релиз видел, что уже выкачено)."
  echo "Откат: revert merge-коммита релиза в \`main\`. Обновляется \`scripts/release-pr.sh\`."
)

if [ -n "${DRY_RUN:-}" ]; then printf '%s\n\n%s\n' "$title" "$body"; exit 0; fi
if [ -n "$pr" ]; then
  gh pr edit "$pr" -R "$repo" --title "$title" --body "$body" >/dev/null
  echo "updated release PR #$pr"
else
  gh pr create -R "$repo" --base main --head dev --title "$title" --body "$body" --reviewer "$owner" --label release
fi
