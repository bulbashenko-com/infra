"""Релизы: what runs where, what waits for the next release, what was released when."""
from .lib import ORG, Dashboard, nav, release_markers, steps

SHORT = '"version", "$1", "{src}", "{regex}"'


def labelled(expr, app, env, src, regex):
    # Adds app/env labels and a short `version` (7 characters of a SHA, or a chart version).
    return (f'label_replace(label_replace(label_replace({expr}, "version", "$1", "{src}", "{regex}"), '
            f'"app", "{app}", "", ""), "env", "{env}", "", "")')


def flux(kind, ns, name, metric="max by (revision)"):
    return f'{metric} (flux_resource_info{{kind="{kind}", exported_namespace="{ns}", name="{name}"}})'


def image(ns):
    return f'max by (image) (kube_pod_container_info{{namespace="{ns}", container="site"}})'


SHA = ".*sha1:([0-9a-f]{7}).*"
TAG = ".*:([0-9a-f]{7})[0-9a-f]*$"
VERSIONS = " or ".join([
    labelled(image("site"), "Сайт", "prod", "image", TAG),
    labelled(image("site-staging"), "Сайт", "staging", "image", TAG),
    labelled(flux("Kustomization", "flux-system", "auth"), "Вход (SSO)", "prod", "revision", SHA),
    labelled(flux("Kustomization", "auth-staging", "auth"), "Вход (SSO)", "staging", "revision", SHA),
    labelled(flux("Kustomization", "flux-system", "mail"), "Почта", "prod", "revision", SHA),
    labelled(flux("Kustomization", "flux-system", "teamspeak"), "TeamSpeak", "prod", "revision", SHA),
    labelled(flux("HelmRelease", "nextcloud", "nextcloud"), "Облако", "prod", "revision", "(.*)"),
    labelled(flux("GitRepository", "flux-system", "flux-system"), "Конфиг кластера (infra)", "prod", "revision", SHA),
    labelled(flux("GitRepository", "flux-system", "infra-dev"), "Конфиг кластера (infra)", "staging", "revision", SHA),
])

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
                "Короткий коммит (или версия чарта), который сейчас работает. Разные значения в строке — на staging "
                "уже новая версия, в прод она попадёт с релизом. У конфига кластера коммиты всегда разные (у main "
                "свои merge-коммиты), это нормально.", w=18, h=8,
                columns={"app": "Что", "prod": "Прод", "staging": "Staging"},
                transformations=[{"id": "groupingToMatrix", "options": {
                    "columnField": "env", "rowField": "app", "valueField": "version", "emptyValue": "empty"}},
                    {"id": "organize", "options": {"renameByName": {"app\\env": "app"}}}]),
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
