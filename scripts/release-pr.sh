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

deploys=() changes=() security=0 other=0
for c in "${commits[@]}"; do
  sha=${c%%$'\t'*} subject=${c#*$'\t'}
  if [[ $subject =~ ^Merge\ pull\ request\ \#([0-9]+) ]]; then
    n=${BASH_REMATCH[1]}
    t=$(gh pr view "$n" -R "$repo" --json title -q .title)
    labels=$(gh pr view "$n" -R "$repo" --json labels -q '[.labels[].name] | join(" ")')
    if [[ $t == Back-merge\ * ]]; then continue; fi
    if [[ " $labels " == *" security "* ]]; then security=$((security + 1)); else other=$((other + 1)); fi
    if [[ $t == Deploy\ * ]]; then deploys+=("- $t (#$n)"); else changes+=("- $t (#$n)"); fi
  elif [[ $subject == Deploy\ * ]]; then
    if git log -1 --format=%B "$sha" | grep -qx 'Security-Update: yes'; then
      security=$((security + 1)); deploys+=("- 🛡 ${subject} (${sha:0:7})")
    else
      other=$((other + 1)); deploys+=("- ${subject} (${sha:0:7})")
    fi
  else
    other=$((other + 1)); changes+=("- ${subject} (${sha:0:7})")
  fi
done

files=$(git diff --name-only origin/main origin/dev)
# What staging already ran: apps/staging and the shared apps/base. Docs and the CI tooling (live on dev already)
# and repo metadata (dotfiles) are not deployed. Everything else first takes effect in production with this
# release; list it by directory.
prod_only=$(grep -vE '^(apps/staging/|apps/base/|\.github/|scripts/|docs/|justfile$|\.[^/]+$|.*\.md$)' <<<"$files" |
  awk -F/ '{ print (NF > 2 ? $1 "/" $2 "/" : NF == 2 ? $1 "/" : $0) }' | sort -u || true)
# auth's production pin (clusters/hel1/auth.yaml) moves together with the staging one, and that version passed
# staging's e2e: when only pin lines changed there, it is not untested.
if grep -qx 'clusters/hel1/auth.yaml' <<<"$files" &&
   ! git diff -U0 origin/main origin/dev -- clusters/hel1/auth.yaml | grep -E '^[-+] ' | grep -vqE '^[-+] +(commit|newTag): [0-9a-f]{40}$'; then
  others=$(grep -vx 'clusters/hel1/auth.yaml' <<<"$files" | grep '^clusters/hel1/' || true)
  [ -n "$others" ] || prod_only=$(grep -vx 'clusters/hel1/' <<<"$prod_only" || true)
fi

# A release of security updates only, all of it tested in staging and nothing for OpenTofu: it merges itself once
# staging is green (.github/workflows/release-gate.yml). Anything else waits for the owner.
security_release=false
if [ "$security" -gt 0 ] && [ "$other" -eq 0 ] && [ -z "$prod_only" ] && ! grep -q '^terraform/' <<<"$files"; then
  security_release=true
fi

since=$(git log -1 --format=%cs origin/main)
if $security_release; then title="Security release: ${#commits[@]} update(s) since $since"
else title="Release: ${#commits[@]} change(s) since $since"; fi
body=$(
  if $security_release; then
    echo "🛡 **Только обновления безопасности.** Смержится сам, как только staging и все проверки зелёные; в Telegram придёт сообщение."
  else
    echo "Всё, что накопилось в \`dev\` (staging) с прошлого релиза. **Merge = релиз в prod.**"
  fi
  echo
  if [ ${#deploys[@]} -gt 0 ]; then echo "### Приложения"; printf '%s\n' "${deploys[@]}"; echo; fi
  if [ ${#changes[@]} -gt 0 ]; then echo "### Изменения"; printf '%s\n' "${changes[@]}"; echo; fi
  if [ -n "$prod_only" ]; then
    echo "> [!WARNING]"
    echo "> В staging не проверялось, впервые применится в prod этим релизом:"
    sed 's/^/> - `/; s/$/`/' <<<"$prod_only"
    echo ">"
    echo "> Что именно изменится в кластере — в комментарии «Что изменится в кластере» ниже."
    echo
  fi
  if grep -q '^terraform/' <<<"$files"; then
    echo "> [!NOTE]"
    echo "> Есть изменения в \`terraform/\`: план — в комментарии OpenTofu ниже; CI применит его после мержа."
    echo
  fi
  echo "### Перед merge"
  echo "- Проверки \`staging/auth-e2e\` и \`staging/site-e2e\` — результат e2e в staging для этого коммита (их ставит Flux)."
  echo "- Посмотреть руками: https://bulbashenko.dev, https://auth.bulbashenko.dev (только через mesh)."
  echo
  echo "### Что произойдёт после merge"
  echo "1. Тег \`vYYYY.MM.DD\` и страница в Releases, сообщение «выкатывается» в Telegram."
  echo "2. Flux заберёт \`main\` в течение минуты и применит; на merge-коммите появятся статусы \`prod/*\`."
  echo "3. Обычно 2–5 минут (Nextcloud до 25). Итог — в Telegram и в Release. Смотреть вживую: [Grafana → Выкатка](https://grafana.int.bulbashenko.com/d/rollout)."
  echo "4. Если сломалось: Actions → **rollback** → тег предыдущего релиза → merge PR отката."
  echo
  echo "Метод мержа — только merge commit. Как всё устроено: [docs/workflow.md](https://github.com/$repo/blob/dev/docs/workflow.md). Текст обновляет \`scripts/release-pr.sh\`."
)

if [ -n "${DRY_RUN:-}" ]; then printf '%s\n\n%s\n' "$title" "$body"; exit 0; fi
if [ -n "$pr" ]; then
  gh pr edit "$pr" -R "$repo" --title "$title" --body "$body" >/dev/null
  echo "updated release PR #$pr"
else
  pr=$(gh pr create -R "$repo" --base main --head dev --title "$title" --body "$body" --reviewer "$owner" --label release)
  echo "opened $pr"
fi
if $security_release; then
  gh pr edit "$pr" -R "$repo" --add-label security-only >/dev/null
else
  gh pr edit "$pr" -R "$repo" --remove-label security-only >/dev/null 2>&1 || true
fi
