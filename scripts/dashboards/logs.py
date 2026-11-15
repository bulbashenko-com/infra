"""Логи: logs of every pod and the cluster's events, in one place (VictoriaLogs)."""
from .lib import LOGS, Dashboard, nav, release_markers

ERRORS = '(level:in("error", "ERROR", "fatal", "FATAL", "panic") or _msg:~"(?i)\\\\b(error|exception|fatal|panic)\\\\b")'


def build():
    d = Dashboard("logs", "Логи",
                  "Логи всех подов кластера за 14 дней и события Kubernetes. Сверху выбери namespace (приложение) и, "
                  "если нужно, текст для поиска.", refresh="", time_from="now-1h")
    nav(d)
    release_markers(d)
    d.variables = [
        {"name": "namespace", "label": "Namespace", "type": "query", "datasource": LOGS,
         "query": {"type": "fieldValue", "field": "kubernetes.pod_namespace", "query": "*", "limit": 100,
                   "refId": "namespace"},
         "includeAll": True, "allValue": "*", "multi": False, "current": {"text": "All", "value": "$__all"},
         "refresh": 2, "sort": 1},
        {"name": "search", "label": "Текст", "type": "textbox", "query": "", "current": {"text": "", "value": ""}},
    ]
    scope = 'kubernetes.pod_namespace:~"${namespace:regex}" ${search:raw}'

    d.row("Сколько ошибок")
    d.line(
        d.log_counts("Строки с ошибками по приложениям", f'{ERRORS} | stats by (kubernetes.pod_namespace) count()',
                     "{{kubernetes.pod_namespace}}",
                     "Сколько строк логов похожи на ошибку (level=error или слова error/exception/fatal), по "
                     "namespace. Всплеск — что-то сломалось в это время; кликни по namespace в переменной сверху."),
        d.log_counts("Ответы сайтов с ошибкой (5xx)",
                     'kubernetes.container_name:="traefik" DownstreamStatus:>=500 | stats by (RequestHost) count()',
                     "{{RequestHost}}",
                     "Запросы, на которые сервис ответил ошибкой 5xx, по домену (access-лог Traefik). Пусто — ошибок "
                     "нет."),
    )

    d.row("Логи")
    d.line(d.logs("Логи выбранного namespace", scope,
                  "Последние строки логов (новые сверху). Клик по строке — все поля: pod, контейнер, метки. "
                  "Поиск: поле «Текст» сверху принимает слова или LogsQL (например level:error).", h=16))
    d.line(d.logs("Только ошибки", f'{scope} {ERRORS}',
                  "То же, но только строки, похожие на ошибку. Хорошее начало, когда что-то сломалось.", h=12))

    d.row("События Kubernetes")
    d.line(d.logs("Предупреждения Kubernetes",
                  'kubernetes.container_name:="event-exporter" type:="Warning"',
                  "События уровня Warning: образ не скачался, под не помещается, проба не проходит, том не "
                  "подключился. Kubernetes хранит их час; здесь — 14 дней.", h=10, max_lines=300))
    return d.render()
