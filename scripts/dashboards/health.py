"""Здоровье: is everything all right, right now? The Grafana home page."""
from .lib import Dashboard, OK_BAD, nav, release_markers, steps, value_text

PRIMARY = 'and on (pod) (cnpg_pg_replication_in_recovery == 0)'


def up(ns):
    # 1 when every Deployment/StatefulSet in the namespace has all its replicas available, 0 otherwise.
    return (f'min(clamp_max((kube_deployment_status_replicas_available{{namespace="{ns}"}} '
            f'/ (kube_deployment_spec_replicas{{namespace="{ns}"}} > 0)) or '
            f'(kube_statefulset_status_replicas_available{{namespace="{ns}"}} '
            f'/ (kube_statefulset_replicas{{namespace="{ns}"}} > 0)), 1)) >= bool 1')


def build():
    d = Dashboard("health", "Здоровье",
                  "Всё ли в порядке прямо сейчас. Зелёное — норма; красное и жёлтое сначала приходит в Telegram. "
                  "Подробности: «Выкатка» (что меняется), «Логи» (почему).")
    nav(d)
    release_markers(d)

    d.row("Сервисы")
    services = (("Сайт", "site", "bulbashenko.com"), ("Вход (SSO)", "auth", "auth.bulbashenko.com, Ory"),
                ("Почта", "mail", "Stalwart"), ("Облако", "nextcloud", "Nextcloud"),
                ("TeamSpeak", "teamspeak", "TeamSpeak"), ("VPN", "headscale", "Headscale, mesh"))
    d.line(*[d.stat(name, up(ns),
                    f"{what}: все поды в namespace {ns} запущены и готовы. «Проблема» — какой-то под не поднялся "
                    f"или перезапускается: смотри «Логи» с namespace={ns}.",
                    mappings=OK_BAD, thresholds=steps((None, "red"), (1, "green")))
             for name, ns, what in services])

    d.row("Данные и обязательства")
    hours = steps((None, "green"), (26, "red"))
    d.line(
        d.stat("Алертов сейчас",
               'count(ALERTS{alertstate="firing", alertname!~"Watchdog|InfoInhibitor", severity=~"warning|critical"}) or vector(0)',
               "Сколько предупреждений и аварий горит сейчас (то же уходит в Telegram). 0 — всё спокойно. "
               "Список — в таблице внизу.", thresholds=steps((None, "green"), (1, "orange"))),
        d.stat("Бэкап базы, ч назад",
               '(time() - max(barman_cloud_cloudnative_pg_io_last_available_backup_timestamp)) / 3600',
               "Когда сделан последний полный бэкап Postgres (каждую ночь в 03:00). Больше 26 часов — бэкап не "
               "прошёл, будет алерт.", unit="h", thresholds=hours, decimals=1),
        d.stat("Копия вне кластера, ч назад",
               '(time() - max(kube_cronjob_status_last_successful_time{cronjob="offsite-backup"})) / 3600',
               "Когда бэкапы последний раз скопированы на Hetzner Storage Box (04:00). Больше 26 часов — копия "
               "не обновляется.", unit="h", thresholds=hours, decimals=1),
        d.stat("Сертификаты, дней до конца",
               'min(certmanager_certificate_expiration_timestamp_seconds - time()) / 86400',
               "Сколько дней до истечения ближайшего TLS-сертификата. cert-manager продлевает за 30 дней; меньше 14 — "
               "продление ломается.", unit="d", decimals=0,
               thresholds=steps((None, "red"), (14, "orange"), (21, "green"))),
        d.stat("Диск, свободно (худший узел)",
               'min(node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"})',
               "Свободное место на самом заполненном узле. Меньше 15% — пора чистить или расширять.",
               unit="percentunit", decimals=0, thresholds=steps((None, "red"), (0.15, "orange"), (0.25, "green"))),
        d.stat("Память, занято (худший узел)",
               'max(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)',
               "Занятая память на самом загруженном узле. Выше 90% — поды начнут убиваться по памяти.",
               unit="percentunit", decimals=0, thresholds=steps((None, "green"), (0.8, "orange"), (0.9, "red"))),
    )
    d.line(
        d.stat("Связь с Cloudflare",
               'sum(cloudflared_tunnel_ha_connections) or vector(0)',
               "Соединения туннеля cloudflared с Cloudflare. 0 — сайты недоступны снаружи; норма 4–8.",
               thresholds=steps((None, "red"), (1, "orange"), (4, "green"))),
        d.stat("Хранилище файлов (Garage)", 'min(cluster_healthy) or vector(0)',
               "Garage — хранилище картинок сайта, бэкапов и файлов. «Проблема» — узел хранилища отвалился.",
               mappings=OK_BAD, thresholds=steps((None, "red"), (1, "green"))),
        d.stat("Реплика базы отстаёт, с", 'max(cnpg_pg_replication_lag) or vector(0)',
               "На сколько секунд вторая копия Postgres отстаёт от основной. Больше минуты — проблема с сетью или "
               "диском; при аварии основной копии потеряется столько данных.",
               unit="s", thresholds=steps((None, "green"), (60, "orange"), (300, "red"))),
        d.stat("Изменения не применились",
               'count(flux_resource_info{ready="False", suspended!="True", reason!="DependencyNotReady"}) or vector(0)',
               "Сколько объектов Flux не смогли применить то, что в git. 0 — кластер совпадает с git. Иначе — "
               "дашборд «Выкатка».", thresholds=steps((None, "green"), (1, "red"))),
        d.stat("Перезапуски за час",
               'round(sum(increase(kube_pod_container_status_restarts_total[1h]))) or vector(0)',
               "Сколько раз контейнеры перезапускались за час. Единичные — нормально при выкатке; десятки — что-то "
               "падает в цикле, ищи в «Логи».", thresholds=steps((None, "green"), (3, "orange"), (10, "red"))),
        d.stat("Убиты по памяти",
               'count(kube_pod_container_status_last_terminated_reason{reason="OOMKilled"} == 1) or vector(0)',
               "Контейнеры, которые последний раз перезапустились, потому что упёрлись в лимит памяти. Не 0 — "
               "поднять лимит или искать утечку.", thresholds=steps((None, "green"), (1, "orange"))),
    )

    d.row("Трафик сайтов")
    d.line(
        d.timeseries("Запросы в секунду", [('sum by (service) (rate(traefik_service_requests_total[5m]))', "{{service}}")],
                     "Сколько запросов приходит к каждому сервису через Traefik. Резкий провал до нуля — сервис "
                     "недоступен; всплеск — нагрузка или бот.", w=8, unit="reqps", stack=True),
        d.timeseries("Ошибки сервера (5xx)",
                     [('sum by (service) (rate(traefik_service_requests_total{code=~"5.."}[5m])) > 0', "{{service}}")],
                     "Ответы с ошибкой на стороне сервера. Пусто — ошибок нет. Устойчивые 5xx — смотри «Логи» "
                     "этого сервиса.", w=8, unit="reqps"),
        d.timeseries("Время ответа (95% запросов быстрее)",
                     [('histogram_quantile(0.95, sum by (le, service) (rate(traefik_service_request_duration_seconds_bucket[5m])))',
                       "{{service}}")],
                     "За сколько отвечают 95% запросов. Выше секунды — пользователи замечают тормоза.",
                     w=8, unit="s", thresholds=steps((None, "transparent"), (1, "orange"))),
    )

    d.row("Что горит")
    d.line(d.table(
        "Алерты сейчас",
        'max by (alertname, severity, namespace) (ALERTS{alertstate="firing", alertname!~"Watchdog|InfoInhibitor", '
        'severity=~"warning|critical"})',
        "Сработавшие алерты (то же, что пришло в Telegram). Пусто — ничего не горит. critical = сделать сейчас, "
        "warning = посмотреть сегодня.",
        h=7, columns={"severity": "Важность", "alertname": "Алерт", "namespace": "Где"},
        mappings=value_text({"critical": ("авария", "red"), "warning": ("предупреждение", "orange")})))
    return d.render()
