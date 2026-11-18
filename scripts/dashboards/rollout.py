"""Выкатка: what is changing in the cluster right now, and did it work?"""
from .lib import GITHUB, SHA_FROM_REVISION, Dashboard, nav, release_markers, steps, value_text, with_repo

INFRA_KS = 'flux_resource_info{kind="Kustomization", exported_namespace="flux-system", source_name="flux-system"}'
REPO = 'flux_resource_info{kind="GitRepository", exported_namespace="flux-system", name="flux-system"}'
FAILING = ('count(flux_resource_info{kind=~"Kustomization|HelmRelease", ready="False", suspended!="True", '
           'reason!="DependencyNotReady"}) or vector(0)')
ROLLING = ('(count(' + INFRA_KS + ' unless on (revision) ' + REPO + ') or vector(0)) + '
           '(count(flux_resource_info{kind=~"Kustomization|HelmRelease", ready="Unknown"}) or vector(0)) + '
           '(count(flux_resource_info{kind=~"Kustomization|HelmRelease", reason="DependencyNotReady"}) or vector(0)) + '
           '(count(kube_deployment_status_replicas_updated < kube_deployment_spec_replicas) or vector(0)) + '
           '(count(kube_statefulset_status_replicas_updated < kube_statefulset_replicas) or vector(0))')
STATE = f'(({FAILING}) > bool 0) * 2 + (({FAILING}) == bool 0) * (({ROLLING}) > bool 0)'
APPS = "site|site-staging|auth|auth-staging|mail|nextcloud|headscale"


def commit(expr):
    """A Flux source's revision with `short` (7 characters, shown) and `sha` (full, for the link)."""
    return ('label_replace(label_replace(' + expr + ', "short", "$1", "revision", ".*sha1:([0-9a-f]{7}).*"), '
            '"sha", "$1", "revision", "' + SHA_FROM_REVISION + '")')


def build():
    d = Dashboard("rollout", "Выкатка",
                  "Что меняется в кластере сейчас. После merge релиза: Flux за минуту замечает новый коммит main, "
                  "применяет его по частям (Kustomization), Kubernetes заменяет поды. Обычно 2–5 минут.")
    nav(d)
    release_markers(d)
    d.annotation("Новые поды", 'changes(kube_deployment_metadata_generation{namespace=~"' + APPS + '"}[2m]) > 0',
                 "Выкатка {{namespace}}/{{deployment}}", "Новая версия пода", "purple")

    d.row("Сейчас")
    d.line(
        d.stat("Состояние", STATE,
               "Готово — всё из git применено и все поды новые. Идёт — Flux применяет или поды заменяются (нормально "
               "2–5 минут после релиза или пина на staging). Ошибка — что-то не применилось: таблица ниже и Telegram.",
               w=8, h=6, mappings=value_text({0: ("Готово", "green"), 1: ("Идёт", "blue"), 2: ("Ошибка", "red")}),
               thresholds=steps((None, "green"), (1, "blue"), (2, "red"))),
        d.stat("В проде коммит", commit(REPO),
               "Коммит main, который Flux получил последним. Совпадает с merge-коммитом релиза — значит, Flux релиз "
               "увидел. Клик — коммит в GitHub.", w=5, h=6, text="name", legend="{{short}}",
               thresholds=steps((None, "blue")),
               link=("Открыть коммит в GitHub", GITHUB + "/infra/commit/${__field.labels.sha}")),
        d.stat("На staging коммит",
               commit('flux_resource_info{kind="GitRepository", exported_namespace="flux-system", name="infra-dev"}'),
               "Коммит dev, который Flux получил последним (staging). Меняется при каждом пине приложения и каждом "
               "PR в dev. Клик — коммит в GitHub.", w=5, h=6, text="name", legend="{{short}}",
               thresholds=steps((None, "blue")),
               link=("Открыть коммит в GitHub", GITHUB + "/infra/commit/${__field.labels.sha}")),
        d.stat("Последняя замена подов, назад",
               'time() - max(kube_replicaset_created{namespace=~"' + APPS + '"})',
               "Сколько прошло с последней выкатки новой версии приложения (где угодно: прод или staging).",
               w=6, h=6, unit="s", thresholds=steps((None, "blue"))),
    )
    d.line(d.table(
        "Части кластера (Flux)",
        'max by (exported_namespace, kind, name, ready, reason, short, sha, repo) (label_replace(label_replace(' +
        with_repo('flux_resource_info{kind=~"Kustomization|HelmRelease"}') + ', '
        '"short", "$1", "revision", "(?:.*sha1:)?([0-9a-f]{7}|[^@]*)[0-9a-f]*$"), '
        '"sha", "$1", "revision", "' + SHA_FROM_REVISION + '"))',
        "Каждая строка — часть кластера, которую Flux применяет отдельно. «Да» — применено и здорово; «идёт» — "
        "применяется; «нет» — ошибка, причина в колонке «Почему» (подробно — в Telegram и «Логи», namespace "
        "flux-system). Клик по версии — коммит в GitHub (у Helm-чартов это версия чарта, без ссылки).", h=10, sort="Где",
        columns={"exported_namespace": "Где", "name": "Что", "kind": "Тип", "ready": "Готово", "reason": "Почему",
                 "short": "Версия", "repo": "repo", "sha": "sha"},
        mappings=value_text({"True": ("да", "green"), "False": ("нет", "red"), "Unknown": ("идёт", "blue")}),
        links={"Версия": ("Открыть коммит в GitHub", GITHUB + "/${__data.fields.repo}/commit/${__data.fields.sha}")},
        hidden=("repo", "sha")))
    d.line(
        d.bars("Поды новой версии готовы", [
            ('clamp_max(min by (namespace, deployment) (kube_deployment_status_replicas_updated{namespace=~"' + APPS + '"}) / '
             'max by (namespace, deployment) (kube_deployment_spec_replicas{namespace=~"' + APPS + '"} > 0), 1)',
             "{{namespace}}/{{deployment}}")],
            "Какая доля подов каждого приложения уже на новой версии. 100% — выкатка этого приложения закончена; "
            "застряло ниже — новый под не стартует (миграция, образ, падение): смотри «Логи».", w=12, h=10),
        d.timeseries("Сколько Flux применяет (секунд)",
                     [('sum by (name) (rate(gotk_reconcile_duration_seconds_sum{kind="Kustomization"}[5m])) / '
                       'sum by (name) (rate(gotk_reconcile_duration_seconds_count{kind="Kustomization"}[5m])) > 0.5',
                       "{{name}}")],
                     "Среднее время одного применения части кластера. Пики во время релиза — нормально (ждёт, пока "
                     "поды станут готовы). Постоянно высоко — что-то медленно стартует.", w=12, h=10, unit="s"),
    )

    d.row("Staging: проверки перед релизом")
    d.line(
        d.table("e2e на staging",
                'max by (name, ready, reason, short, sha) (' +
                commit('flux_resource_info{kind="Kustomization", exported_namespace="auth-staging", name=~".*-e2e"}') + ')',
                "Прогон e2e для текущей версии на staging: вход (auth-e2e) и сайт (site-e2e). «Да» — прошли, релиз "
                "можно мержить; «идёт» — тесты бегут (сайт ~3 мин, вход ~12); «нет» — упали: «Логи», namespace "
                "auth-staging.", w=12, h=6,
                columns={"name": "Проверка", "ready": "Прошла", "reason": "Почему", "short": "Коммит dev", "sha": "sha"},
                mappings=value_text({"True": ("да", "green"), "False": ("нет", "red"), "Unknown": ("идёт", "blue")}),
                links={"Коммит dev": ("Открыть коммит в GitHub", GITHUB + "/infra/commit/${__data.fields.sha}")},
                hidden=("sha",)),
        d.table("Задания staging",
                'max by (job_name, namespace) (kube_job_status_succeeded{namespace=~"auth-staging|site-staging"}) * 1 '
                'or max by (job_name, namespace) (kube_job_status_failed{namespace=~"auth-staging|site-staging"} > 0) * -1',
                "Последние запуски e2e и ночного обновления данных staging (staging-refresh): успешно, идёт или упало.",
                w=12, h=6, columns={"namespace": "Где", "job_name": "Задание", "Value": "Итог"},
                mappings=value_text({1: ("успешно", "green"), 0: ("идёт", "blue"), -1: ("упало", "red")})),
    )

    d.row("Почему не работает")
    d.line(d.logs("Ошибки Flux за последний час",
                  'kubernetes.pod_namespace:="flux-system" level:="error"',
                  "Сообщения об ошибках контроллеров Flux: что именно не применилось и почему. Пусто — ошибок нет.",
                  h=10, max_lines=200))
    return d.render()
