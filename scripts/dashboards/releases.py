"""Релизы: what runs where, what waits for the next release, what was released when."""
from .lib import GITHUB, ORG, SHA_FROM_IMAGE, SHA_FROM_REVISION, Dashboard, nav, release_markers, steps

def labelled(expr, app, repo, env, src, regex, sha_regex=None):
    # Adds app/env/repo labels, a short `version` (7 characters of a SHA, or a chart version) and the full `sha`
    # (for the link to the commit).
    out = (f'label_replace(label_replace(label_replace(label_replace({expr}, "version", "$1", "{src}", "{regex}"), '
           f'"app", "{app}", "", ""), "env", "{env}", "", ""), "repo", "{repo}", "", "")')
    if sha_regex:
        out = f'label_replace({out}, "sha", "$1", "{src}", "{sha_regex}")'
    return out


def flux(kind, ns, name, metric="max by (revision)"):
    return f'{metric} (flux_resource_info{{kind="{kind}", exported_namespace="{ns}", name="{name}"}})'


def image(ns):
    return f'max by (image) (kube_pod_container_info{{namespace="{ns}", container="site"}})'


SHA = ".*sha1:([0-9a-f]{7}).*"
TAG = ".*:([0-9a-f]{7})[0-9a-f]*$"
VERSIONS = "max by (app, env, version, repo, sha) (" + " or ".join([
    labelled(image("site"), "Сайт", "site", "прод", "image", TAG, SHA_FROM_IMAGE),
    labelled(image("site-staging"), "Сайт", "site", "staging", "image", TAG, SHA_FROM_IMAGE),
    labelled(flux("Kustomization", "flux-system", "auth"), "Вход (SSO)", "auth", "прод", "revision", SHA, SHA_FROM_REVISION),
    labelled(flux("Kustomization", "auth-staging", "auth"), "Вход (SSO)", "auth", "staging", "revision", SHA, SHA_FROM_REVISION),
    labelled(flux("Kustomization", "flux-system", "mail"), "Почта", "mail", "прод", "revision", SHA, SHA_FROM_REVISION),
    labelled(flux("Kustomization", "flux-system", "teamspeak"), "TeamSpeak", "teamspeak", "прод", "revision", SHA,
             SHA_FROM_REVISION),
    labelled(flux("HelmRelease", "nextcloud", "nextcloud"), "Облако (версия чарта)", "", "прод", "revision", "(.*)"),
    labelled(flux("GitRepository", "flux-system", "flux-system"), "Конфиг кластера (infra)", "infra", "прод", "revision",
             SHA, SHA_FROM_REVISION),
    labelled(flux("GitRepository", "flux-system", "infra-dev"), "Конфиг кластера (infra)", "infra", "staging", "revision",
             SHA, SHA_FROM_REVISION),
]) + ")"

# Apps whose staging runs something production does not yet: what the next release will bring.
WAITING = ('(count(max by (image) (kube_pod_container_info{namespace="site-staging", container="site"}) '
           'unless on (image) max by (image) (kube_pod_container_info{namespace="site", container="site"})) or vector(0)) + '
           '(count(' + flux("Kustomization", "auth-staging", "auth") + ' unless on (revision) '
           + flux("Kustomization", "flux-system", "auth") + ') or vector(0))')


def build():
    d = Dashboard("releases", "Релизы",
                  "Что сейчас работает в проде и на staging, что ждёт следующего релиза и когда были прошлые. "
                  "Релиз = merge PR «Release» dev → main в infra (docs/workflow.md).", refresh="1m", time_from="now-7d")
    nav(d)
    release_markers(d)

    d.row("Сейчас")
    d.line(
        d.stat("Приложений ждут релиза", WAITING,
               "Сколько приложений на staging уже новее, чем в проде (сайт, вход). 0 — прод и staging совпадают; "
               "иначе их принесёт следующий релиз.", w=6, h=8,
               thresholds=steps((None, "green"), (1, "blue"))),
        d.table("Версии: прод и staging", VERSIONS,
                "Короткий коммит (или версия чарта), который сейчас работает. У одного приложения разные коммиты в "
                "проде и на staging — на staging уже новая версия, в прод она попадёт с релизом. У конфига кластера "
                "коммиты всегда разные (у main свои merge-коммиты), это нормально. Клик по версии — коммит в GitHub.",
                w=18, h=8, sort="Что",
                columns={"app": "Что", "env": "Где", "version": "Версия", "repo": "repo", "sha": "sha"},
                links={"Версия": ("Открыть коммит в GitHub", GITHUB + "/${__data.fields.repo}/commit/${__data.fields.sha}")},
                hidden=("repo", "sha")),
    )
    d.line(
        d.github("Открытый релиз", "PR «Release» dev → main: что войдёт в прод. Пусто — всё уже в проде. "
                 "Merge этого PR и есть релиз; после него придёт сообщение в Telegram.",
                 {"queryType": "Pull_Requests", "owner": ORG, "repository": "infra",
                  "options": {"query": "is:open label:release base:main", "timeField": 4}},
                 w=24, h=4, columns={"title": "Релиз", "number": "PR", "created_at": "Открыт", "url": "url"},
                 link_field="url", link_title="Открыть PR"),
    )

    d.row("История")
    d.line(
        d.github("Последние релизы", "Каждый merge в main получает тег vГГГГ.ММ.ДД и страницу с описанием и итогом "
                 "выкатки («Применён за N мин» или ошибка). Клик — страница релиза; оттуда же откат.",
                 {"queryType": "Releases", "owner": ORG, "repository": "infra", "options": {}},
                 w=12, h=10, columns={"name": "Релиз", "published_at": "Когда", "url": "url"},
                 link_field="url", link_title="Открыть релиз", sort="published_at"),
        d.github("Выкатки (GitHub Actions)", "Запуски release-tag: каждый ждёт, пока Flux применит релиз. "
                 "Зелёный — применён, красный — ошибка или таймаут (подробности в запуске).",
                 {"queryType": "Workflow_Runs", "owner": ORG, "repository": "infra",
                  "options": {"workflow": "release-tag.yml", "workflowID": "release-tag.yml", "branch": "main"}},
                 w=12, h=10, columns={"head_sha": "Коммит", "conclusion": "Итог", "run_started_at": "Старт",
                                      "html_url": "html_url"},
                 link_field="html_url", link_title="Открыть запуск", sort="run_started_at", time_from="30d"),
    )
    return d.render()
