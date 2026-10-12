"""Generates infrastructure/configs/monitoring/dashboards/main.json ("Главное"): everything on one page.

Usage: python3 scripts/dashboard-main.py infrastructure/configs/monitoring/dashboards/main.json
"""
import json
import sys

DS = {"type": "prometheus", "uid": "VictoriaMetrics"}
LAYER = ('* on (namespace) group_left (label_bulbashenko_com_layer, label_bulbashenko_com_app) '
         'max by (namespace, label_bulbashenko_com_layer, label_bulbashenko_com_app) (kube_namespace_labels)')
PRIMARY = '* on (pod) group_left () (cnpg_pg_replication_in_recovery == 0)'

panels = []
y = 0
pid = 0


def nid():
    global pid
    pid += 1
    return pid


def row(title):
    global y
    panels.append({"id": nid(), "type": "row", "title": title, "collapsed": False,
                   "gridPos": {"x": 0, "y": y, "w": 24, "h": 1}, "panels": []})
    y += 1


def steps(*pairs):
    return {"mode": "absolute", "steps": [{"color": c, "value": v} for v, c in pairs]}


GOOD0 = steps((None, "green"), (1, "red"))  # 0 is fine, anything else red


def stat(title, expr, x, w=4, h=4, unit="none", thr=GOOD0, desc="", decimals=None, mappings=None):
    fc = {"unit": unit, "thresholds": thr, "color": {"mode": "thresholds"}}
    if decimals is not None:
        fc["decimals"] = decimals
    if mappings:
        fc["mappings"] = mappings
    return {"id": nid(), "type": "stat", "title": title, "description": desc, "datasource": DS,
            "gridPos": {"x": x, "y": y, "w": w, "h": h},
            "fieldConfig": {"defaults": fc, "overrides": []},
            "options": {"reduceOptions": {"calcs": ["lastNotNull"]}, "colorMode": "background",
                        "graphMode": "none", "textMode": "value"},
            "targets": [{"refId": "A", "datasource": DS, "expr": expr, "instant": True}]}


def ts(title, targets, x, w=12, h=8, unit="none", stack=False, desc="", minv=None, maxv=None):
    fc = {"unit": unit, "custom": {"stacking": {"mode": "normal" if stack else "none"},
                                   "fillOpacity": 15 if stack else 0, "showPoints": "never"}}
    if minv is not None:
        fc["min"] = minv
    if maxv is not None:
        fc["max"] = maxv
    return {"id": nid(), "type": "timeseries", "title": title, "description": desc, "datasource": DS,
            "gridPos": {"x": x, "y": y, "w": w, "h": h},
            "fieldConfig": {"defaults": fc, "overrides": []},
            "options": {"legend": {"displayMode": "table", "placement": "right", "calcs": ["lastNotNull", "max"]},
                        "tooltip": {"mode": "multi", "sort": "desc"}},
            "targets": [{"refId": chr(65 + i), "datasource": DS, "expr": e, "legendFormat": l}
                        for i, (e, l) in enumerate(targets)]}


def table(title, expr, x, w=24, h=8, desc="", rename=None, value_map=None, unit="none"):
    defaults = {"unit": unit, "custom": {"cellOptions": {"type": "color-text"}}}
    if value_map:
        defaults["mappings"] = value_map
    return {"id": nid(), "type": "table", "title": title, "description": desc, "datasource": DS,
            "gridPos": {"x": x, "y": y, "w": w, "h": h},
            "fieldConfig": {"defaults": defaults, "overrides": []},
            "options": {"sortBy": [{"displayName": "Value", "desc": True}]},
            "targets": [{"refId": "A", "datasource": DS, "expr": expr, "instant": True, "format": "table"}],
            "transformations": [{"id": "organize", "options": {"excludeByName": {"Time": True},
                                                               "renameByName": rename or {}}}]}


def add(*ps):
    panels.extend(ps)


def advance(h):
    global y
    y += h


# ---------------------------------------------------------------- Состояние
row("Состояние")
add(
    stat("Алерты (firing)",
         'count(ALERTS{alertstate="firing", alertname!~"Watchdog|InfoInhibitor"}) or vector(0)', 0,
         desc="Сработавшие алерты, кроме служебных. Список: Alerting > Alert rules."),
    stat("Таргеты вниз", 'count(up == 0) or vector(0)', 4, desc="Что vmagent не может опросить; таблица внизу."),
    stat("Поды не готовы", 'sum(kube_pod_status_ready{condition="false"}) or vector(0)', 8),
    stat("Рестарты за 1 ч", 'round(sum(increase(kube_pod_container_status_restarts_total[1h]))) or vector(0)', 12),
    stat("OOMKilled сейчас",
         'count(kube_pod_container_status_last_terminated_reason{reason="OOMKilled"} == 1) or vector(0)', 16,
         desc="Контейнеры, чей последний перезапуск был из-за нехватки памяти (упёрлись в limit)."),
    stat("Flux: не Ready", 'count(flux_resource_info{ready="False"}) or vector(0)', 20,
         desc="Объекты Flux, которые не применились: смерженный PR не доехал до кластера."),
)
advance(4)

# ---------------------------------------------------------------- Деплои
GH = {"type": "grafana-github-datasource", "uid": "github"}
ORG = "bulbashenko-com"
row("Деплои")
add(
    stat("Сейчас деплоится",
         '(count(flux_resource_info{kind=~"Kustomization|HelmRelease", ready="Unknown"}) or vector(0)) + '
         '(count(kube_deployment_status_replicas_updated < kube_deployment_spec_replicas) or vector(0)) + '
         '(count(kube_statefulset_status_replicas_updated < kube_statefulset_replicas) or vector(0))', 0, w=4,
         thr=steps((None, "green"), (1, "blue")),
         desc="Объекты Flux в процессе применения плюс Deployment/StatefulSet, у которых ещё не все поды новые."),
    table("Версии и статус (Flux)",
          'max by (kind, name, ready, suspended, revision) (flux_resource_info{kind=~"Kustomization|HelmRelease"})',
          4, w=20, h=8, desc="revision = коммит/версия, которую Flux применил. ready=Unknown — идёт применение.",
          rename={"kind": "Тип", "name": "Имя", "ready": "Ready", "suspended": "Пауза", "revision": "Версия"}),
)
advance(4)
add(
    stat("Обычно длится деплой",
         'histogram_quantile(0.5, sum by (le) (rate(gotk_reconcile_duration_seconds_bucket{kind="Kustomization", name=~"site|auth|mail|teamspeak"}[7d])))',
         0, w=4, unit="s", thr=steps((None, "blue")),
         desc="Медиана синхронизации Kustomization приложений за 7 дней (включая ожидание готовности подов). Не ETA, а ориентир."),
)
advance(4)
add(
    {"id": nid(), "type": "bargauge", "title": "Выкатка: новые поды готовы", "datasource": DS,
     "description": "Доля подов новой версии, которые уже обновлены и доступны. Меньше 100% — выкатка идёт или застряла.",
     "gridPos": {"x": 0, "y": y, "w": 12, "h": 8},
     "fieldConfig": {"defaults": {"unit": "percentunit", "min": 0, "max": 1,
                                  "thresholds": steps((None, "orange"), (1, "green")), "color": {"mode": "thresholds"}},
                     "overrides": []},
     "options": {"orientation": "horizontal", "displayMode": "basic", "showUnfilled": True,
                 "reduceOptions": {"calcs": ["lastNotNull"]}},
     "targets": [
         {"refId": "A", "datasource": DS, "instant": True, "legendFormat": "{{namespace}}/{{deployment}}",
          "expr": 'clamp_max(min by (namespace, deployment) (kube_deployment_status_replicas_updated) / '
                  'max by (namespace, deployment) (kube_deployment_spec_replicas > 0), 1) '
                  '* on (namespace) group_left () max by (namespace) (kube_namespace_labels{label_bulbashenko_com_layer=~"app|platform"})'},
         {"refId": "B", "datasource": DS, "instant": True, "legendFormat": "{{namespace}}/{{statefulset}}",
          "expr": 'clamp_max(min by (namespace, statefulset) (kube_statefulset_status_replicas_updated) / '
                  'max by (namespace, statefulset) (kube_statefulset_replicas > 0), 1) '
                  '* on (namespace) group_left () max by (namespace) (kube_namespace_labels{label_bulbashenko_com_layer=~"app|platform"})'},
     ]},
    {"id": nid(), "type": "table", "title": "Ждут мержа (открытые PR в организации)", "datasource": GH,
     "description": "Deploy-PR в infra и остальные открытые PR. Мерж deploy-PR = деплой.",
     "gridPos": {"x": 12, "y": y, "w": 12, "h": 8},
     "fieldConfig": {"defaults": {}, "overrides": [
         {"matcher": {"id": "byName", "options": "title"},
          "properties": [{"id": "links", "value": [{"title": "Открыть PR", "url": "${__data.fields.url}", "targetBlank": True}]}]}]},
     "options": {"sortBy": [{"displayName": "created_at", "desc": True}]},
     "targets": [{"refId": "A", "datasource": GH, "queryType": "Pull_Requests", "owner": ORG, "repository": "",
                  "options": {"query": "is:open", "timeField": 4}}],
     "transformations": [{"id": "organize", "options": {
         "includeByName": {"repository": True, "number": True, "title": True, "author_login": True,
                           "is_draft": True, "created_at": True},
         "indexByName": {"repository": 0, "number": 1, "title": 2, "author_login": 3, "is_draft": 4, "created_at": 5},
         "renameByName": {"repository": "Репозиторий", "number": "#", "title": "PR", "author_login": "Автор",
                          "is_draft": "Черновик", "created_at": "Открыт"}}}]},
)
advance(8)


def runs(title, repo, workflows, x, w):
    return {"id": nid(), "type": "table", "title": title, "datasource": GH, "timeFrom": "3d",
            "description": "Запуски GitHub Actions за 3 дня. Длительность = updated_at − run_started_at.",
            "gridPos": {"x": x, "y": y, "w": w, "h": 7},
            "fieldConfig": {"defaults": {}, "overrides": [
                {"matcher": {"id": "byName", "options": "name"},
                 "properties": [{"id": "links", "value": [{"title": "Открыть запуск", "url": "${__data.fields.html_url}", "targetBlank": True}]}]},
                {"matcher": {"id": "byName", "options": "Длительность"}, "properties": [{"id": "unit", "value": "ms"}]},
                {"matcher": {"id": "byName", "options": "conclusion"},
                 "properties": [{"id": "custom.cellOptions", "value": {"type": "color-text"}},
                                {"id": "mappings", "value": [{"type": "value", "options": {
                                    "success": {"color": "green", "text": "✓"}, "failure": {"color": "red", "text": "✗"},
                                    "cancelled": {"color": "gray", "text": "отменён"}, "skipped": {"color": "gray", "text": "пропущен"}}}]}]},
                {"matcher": {"id": "byName", "options": "status"},
                 "properties": [{"id": "mappings", "value": [{"type": "value", "options": {
                     "in_progress": {"color": "blue", "text": "идёт"}, "queued": {"color": "blue", "text": "в очереди"},
                     "completed": {"text": "готово"}}}]}]}]},
            "options": {"sortBy": [{"displayName": "run_started_at", "desc": True}]},
            "targets": [{"refId": chr(65 + i), "datasource": GH, "queryType": "Workflow_Runs", "owner": ORG,
                         "repository": repo, "options": {"workflow": wf, "workflowID": wf, "branch": "main"}}
                        for i, wf in enumerate(workflows)],
            "transformations": [
                {"id": "merge", "options": {}},
                {"id": "calculateField", "options": {"mode": "binary", "alias": "Длительность",
                                                     "binary": {"left": "updated_at", "operator": "-", "right": "run_started_at"}}},
                {"id": "organize", "options": {
                    "includeByName": {"name": True, "head_sha": True, "event": True, "status": True, "conclusion": True,
                                      "run_started_at": True, "Длительность": True},
                    "indexByName": {"name": 0, "status": 1, "conclusion": 2, "head_sha": 3, "event": 4,
                                    "run_started_at": 5, "Длительность": 6},
                    "renameByName": {"name": "Workflow", "head_sha": "Коммит", "event": "Событие", "status": "Статус",
                                     "conclusion": "Итог", "run_started_at": "Старт"}}}]}


add(runs("CI/CD: site", "site", ["deploy.yml"], 0, 8),
    runs("CI/CD: auth", "auth", ["test.yml", "image.yml"], 8, 8),
    runs("CI/CD: infra (deploy-PR и проверки)", "infra", ["promote.yml", "ci.yml"], 16, 8))
advance(7)
add(runs("CI/CD: mail", "mail", ["ci.yml"], 0, 12),
    runs("CI/CD: teamspeak", "teamspeak", ["ci.yml"], 12, 12))
advance(7)

# ---------------------------------------------------------------- Бэкапы и данные
row("Бэкапы и данные")
H26 = steps((None, "green"), (26, "red"))
add(
    stat("Бэкап Postgres, ч назад",
         '(time() - max(barman_cloud_cloudnative_pg_io_last_available_backup_timestamp)) / 3600', 0,
         unit="h", thr=H26, decimals=1, desc="Последний успешный base backup в Garage (ScheduledBackup 03:00)."),
    stat("WAL архивирован, мин назад",
         'max(cnpg_pg_stat_archiver_seconds_since_last_archival ' + PRIMARY + ') / 60', 4,
         unit="m", thr=steps((None, "green"), (15, "red")), decimals=1,
         desc="На primary. CNPG закрывает WAL-сегмент минимум раз в 5 минут."),
    stat("Off-site копия, ч назад",
         '(time() - max(kube_cronjob_status_last_successful_time{cronjob="offsite-backup"})) / 3600', 8,
         unit="h", thr=H26, decimals=1, desc="CronJob data/offsite-backup 04:00 → Storage Box."),
    stat("Бэкап томов, ч назад",
         '(time() - min(kube_cronjob_status_last_successful_time{cronjob="volume-backup"})) / 3600', 12,
         unit="h", thr=H26, decimals=1, desc="Самый старый из headscale/teamspeak volume-backup 03:30."),
    stat("Отставание реплики", 'max(cnpg_pg_replication_lag)', 16,
         unit="s", thr=steps((None, "green"), (60, "orange"), (300, "red"))),
    stat("Реплик стримит", 'max(cnpg_pg_replication_streaming_replicas ' + PRIMARY + ')', 20,
         thr=steps((None, "red"), (1, "green")), desc="Сколько реплик подключено к primary (ожидается 1)."),
)
advance(4)
add(
    stat("Garage здоров", 'min(cluster_healthy)', 0, thr=steps((None, "red"), (1, "green")),
         mappings=[{"type": "value", "options": {"0": {"text": "нет"}, "1": {"text": "да"}}}],
         desc="cluster_healthy: все узлы и разделы в порядке."),
    stat("Garage узлов на связи", 'min(cluster_connected_nodes)', 4, thr=steps((None, "red"), (3, "green"))),
    stat("Туннель: соединений", 'sum(cloudflared_tunnel_ha_connections)', 8,
         thr=steps((None, "red"), (1, "orange"), (4, "green")),
         desc="HA-соединения cloudflared с Cloudflare (2 пода × до 4). 0 = сайт недоступен снаружи."),
    stat("Сертификат истекает, дн",
         'min(certmanager_certificate_expiration_timestamp_seconds - time()) / 86400', 12,
         unit="d", thr=steps((None, "red"), (14, "orange"), (21, "green")), decimals=0,
         desc="Ближайший срок среди Certificate cert-manager; продление идёт за 30 дней."),
    stat("Свободно на дисках, мин", 'min(node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"})',
         16, unit="percentunit", thr=steps((None, "red"), (0.15, "orange"), (0.25, "green")), decimals=0),
    stat("Память узлов, макс", 'max(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)', 20,
         unit="percentunit", thr=steps((None, "green"), (0.8, "orange"), (0.9, "red")), decimals=0),
)
advance(4)
add(
    ts("Размер баз", [('max by (datname) (cnpg_pg_database_size_bytes{datname!~"postgres|template.*"})', "{{datname}}")],
       0, w=8, unit="bytes"),
    ts("Соединения к Postgres", [('sum by (datname) (cnpg_backends_total ' + PRIMARY + ')', "{{datname}}")],
       8, w=8, stack=True),
    ts("Garage: свободно на дисках",
       [('min by (pod) (garage_local_disk_avail{volume="data"})', "{{pod}}")], 16, w=8, unit="bytes"),
)
advance(8)

# ---------------------------------------------------------------- Узлы
row("Узлы")
NODE = ' * on (instance) group_left (nodename) node_uname_info'
add(
    ts("Память", [('(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)' + NODE, "{{nodename}}")],
       0, w=8, unit="percentunit", minv=0, maxv=1),
    ts("CPU", [('(1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])))' + NODE, "{{nodename}}")],
       8, w=8, unit="percentunit", minv=0, maxv=1),
    ts("Диск / занято",
       [('(1 - node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"})' + NODE,
         "{{nodename}}")], 16, w=8, unit="percentunit", minv=0, maxv=1),
)
advance(8)
add(
    table("Контейнеры ближе всего к лимиту памяти",
          'topk(10, max by (namespace, pod, container) (container_memory_working_set_bytes{container!=""}) / '
          'max by (namespace, pod, container) (kube_pod_container_resource_limits{resource="memory"}))',
          0, w=12, unit="percentunit", desc="working set / limit. Близко к 100% → OOMKilled."),
    ts("Сеть узлов (приём + отдача)",
       [('sum by (instance) (rate(node_network_receive_bytes_total{device!~"lo|veth.*|cni.*|flannel.*|tailscale.*"}[5m]) '
         '+ rate(node_network_transmit_bytes_total{device!~"lo|veth.*|cni.*|flannel.*|tailscale.*"}[5m]))' + NODE,
         "{{nodename}}")], 12, w=12, unit="Bps"),
)
advance(8)

# ---------------------------------------------------------------- По слоям и приложениям
row("По слоям и приложениям")
CPU = 'sum by (label_bulbashenko_com_%s) (rate(container_cpu_usage_seconds_total{container!="",pod!=""}[5m]) ' + LAYER + ')'
MEM = 'sum by (label_bulbashenko_com_%s) (container_memory_working_set_bytes{container!="",pod!=""} ' + LAYER + ')'
add(
    ts("CPU по слоям", [(CPU % "layer", "{{label_bulbashenko_com_layer}}")], 0, w=6, unit="cores", stack=True),
    ts("Память по слоям", [(MEM % "layer", "{{label_bulbashenko_com_layer}}")], 6, w=6, unit="bytes", stack=True),
    ts("CPU по приложениям", [(CPU % "app", "{{label_bulbashenko_com_app}}")], 12, w=6, unit="cores", stack=True),
    ts("Память по приложениям", [(MEM % "app", "{{label_bulbashenko_com_app}}")], 18, w=6, unit="bytes", stack=True),
)
advance(8)

# ---------------------------------------------------------------- Трафик
row("Трафик")
add(
    ts("Запросы по сервисам", [('sum by (service) (rate(traefik_service_requests_total[5m]))', "{{service}}")],
       0, w=8, unit="reqps", stack=True),
    ts("Ошибки 5xx по сервисам",
       [('sum by (service) (rate(traefik_service_requests_total{code=~"5.."}[5m])) > 0', "{{service}}")],
       8, w=8, unit="reqps"),
    ts("Задержка p95",
       [('histogram_quantile(0.95, sum by (le, service) (rate(traefik_service_request_duration_seconds_bucket[5m])))',
         "{{service}}")], 16, w=8, unit="s"),
)
advance(8)

# ---------------------------------------------------------------- Почта и GitOps
row("Почта и GitOps")
add(
    stat("Stalwart опрашивается", 'max(up{namespace="mail"}) or vector(0)', 0, w=4,
         thr=steps((None, "red"), (1, "green")),
         mappings=[{"type": "value", "options": {"0": {"text": "нет"}, "1": {"text": "да"}}}],
         desc="Метрики Stalwart включаются в его WebUI (Settings › Telemetry › Metrics › Prometheus)."),
    stat("Stalwart память", 'sum(container_memory_working_set_bytes{namespace="mail", container!=""})', 4, w=4,
         unit="bytes", thr=steps((None, "blue"))),
    stat("Stalwart рестарты 24 ч",
         'round(sum(increase(kube_pod_container_status_restarts_total{namespace="mail"}[24h]))) or vector(0)', 8, w=4),
    table("Flux: объекты не Ready", 'flux_resource_info{ready!="True"}', 12, w=12, h=4,
          desc="Пусто = всё применено."),
)
advance(4)

# ---------------------------------------------------------------- Таргеты
row("Таргеты")
add(table("Что опрашивает vmagent", 'min by (job, namespace) (up)', 0, w=24, h=8,
          value_map=[{"type": "value", "options": {"0": {"text": "DOWN", "color": "red"},
                                                     "1": {"text": "up", "color": "green"}}}]))
advance(8)

dash = {
    "uid": "bulbashenko-main", "title": "Главное", "tags": ["bulbashenko"], "timezone": "browser",
    "schemaVersion": 39, "refresh": "1m", "time": {"from": "now-6h", "to": "now"}, "editable": True,
    "description": "Всё важное о кластере hel1 на одной странице: состояние, бэкапы и данные, узлы, слои, трафик, "
                   "почта, GitOps. Пороги совпадают с алертами (infrastructure/configs/monitoring/rules.yaml).",
    "panels": panels,
    "annotations": {"list": [
        {"name": "Деплой (Flux)", "enable": True, "iconColor": "blue", "datasource": DS,
         "expr": 'max by (kind, name, revision) (flux_resource_info{kind=~"Kustomization|HelmRelease"}) '
                 'unless max by (kind, name, revision) (flux_resource_info{kind=~"Kustomization|HelmRelease"} offset 3m)',
         "step": "60s", "titleFormat": "Деплой {{name}}", "textFormat": "{{kind}} {{name}} → {{revision}}",
         "useValueForTime": False},
        {"name": "Выкатка подов", "enable": True, "iconColor": "purple", "datasource": DS,
         "expr": 'changes(kube_deployment_metadata_generation[2m]) > 0 or changes(kube_statefulset_metadata_generation[2m]) > 0',
         "step": "60s", "titleFormat": "Выкатка {{namespace}}/{{deployment}}{{statefulset}}",
         "textFormat": "Новая версия спецификации", "useValueForTime": False},
    ]},
}
json.dump(dash, open(sys.argv[1], "w"), indent=1, ensure_ascii=False)
print(len(panels), "panels")
