#!/usr/bin/env bash
# Keeps the release PR main -> production open with a current description, and back-merges hotfixes.
# main is staging (everything lands there), production is what the hel1 cluster runs; merging the release PR
# is the release. Runs in .github/workflows/release.yml after every push to main or production.
# DRY_RUN=1 prints the PR text instead of writing.
set -euo pipefail

repo=bulbashenko-com/infra
owner=bulbashenko
git fetch -q origin main production

# Hotfixes merged straight into production go back to main through a short-lived branch (never the production
# branch itself: delete-branch-on-merge would try to remove it). Release merges are merge commits and are
# skipped by --no-merges, so they never trigger this.
hotfixes=$(git rev-list --no-merges origin/main..origin/production)
if [ -n "$hotfixes" ] && [ -z "${DRY_RUN:-}" ]; then
  tip=$(git rev-parse origin/production)
  branch=backmerge/${tip:0:7}
  if ! gh pr list -R "$repo" --base main --state open --json headRefName -q '.[].headRefName' | grep -qx "$branch"; then
    gh api "repos/$repo/git/refs" -f ref="refs/heads/$branch" -f sha="$tip" >/dev/null
    pr=$(gh pr create -R "$repo" --base main --head "$branch" --title "Back-merge production ${tip:0:7}" \
      --body "Hotfixes merged straight into \`production\`, brought back to \`main\` so the next release keeps them.")
    gh pr merge "$pr" --auto --merge
  fi
fi

mapfile -t commits < <(git log --first-parent --format='%H%x09%s' origin/production..origin/main)
pr=$(gh pr list -R "$repo" --base production --head main --state open --json number -q '.[0].number // empty')
if [ ${#commits[@]} -eq 0 ]; then
  echo "production has everything on main"; exit 0
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

files=$(git diff --name-only origin/production origin/main)
cluster_wide=$(grep -E '^(infrastructure/|apps/edge/|clusters/hel1/(flux-instance|flux-operator|infrastructure|edge)\.yaml)' <<<"$files" || true)

title="Release: ${#commits[@]} change(s) since $(git log -1 --format=%cs origin/production)"
body=$(
  echo "Всё, что накопилось в \`main\` (staging) с прошлого релиза. **Merge = релиз в prod**: Flux раскатит \`production\`."
  echo
  if [ ${#deploys[@]} -gt 0 ]; then echo "### Приложения"; printf '%s\n' "${deploys[@]}"; echo; fi
  if [ ${#changes[@]} -gt 0 ]; then echo "### Изменения"; printf '%s\n' "${changes[@]}"; echo; fi
  if [ -n "$cluster_wide" ]; then
    echo "> [!WARNING]"
    echo "> Кластерные изменения: в staging их проверить нельзя, они впервые применятся этим релизом."
    sed 's/^/> - `/; s/$/`/' <<<"$cluster_wide"
    echo
  fi
  if grep -q '^terraform/' <<<"$files"; then
    echo "> [!NOTE]"
    echo "> Есть изменения в \`terraform/\`: после релиза \`just plan\` / \`just apply\`."
    echo
  fi
  echo "Метод мержа — только merge commit (история нужна, чтобы следующий релиз видел, что уже выкачено)."
  echo "Откат: revert merge-коммита релиза в \`production\`. Обновляется \`scripts/release-pr.sh\`."
)

if [ -n "${DRY_RUN:-}" ]; then printf '%s\n\n%s\n' "$title" "$body"; exit 0; fi
if [ -n "$pr" ]; then
  gh pr edit "$pr" -R "$repo" --title "$title" --body "$body" >/dev/null
  echo "updated release PR #$pr"
else
  gh pr create -R "$repo" --base production --head main --title "$title" --body "$body" --reviewer "$owner" --label release
fi
