"""Building blocks for the Grafana dashboards in infrastructure/configs/monitoring/dashboards/.

Rules (docs/workflow.md, "Где смотреть"):
- one question per dashboard, a handful of panels, titles in plain Russian;
- every panel has a description (the (i) next to its title): what it shows, and when to worry. The generator
  refuses a panel without one.
"""

VM = {"type": "prometheus", "uid": "VictoriaMetrics"}
LOGS = {"type": "victoriametrics-logs-datasource", "uid": "victorialogs"}
GH = {"type": "grafana-github-datasource", "uid": "github"}
ORG = "bulbashenko-com"
GRAFANA = "https://grafana.int.bulbashenko.com"


def steps(*pairs):
    """Thresholds: steps((None, "green"), (1, "red")) = below 1 green, from 1 red."""
    return {"mode": "absolute", "steps": [{"color": c, "value": v} for v, c in pairs]}


def value_text(mapping):
    """Value mappings {raw: (text, color)}: shows words instead of numbers."""
    return [{"type": "value", "options": {str(k): {"text": t, "color": c, "index": i}
                                          for i, (k, (t, c)) in enumerate(mapping.items())}}]


OK_BAD = value_text({1: ("работает", "green"), 0: ("проблема", "red")})


class Dashboard:
    def __init__(self, uid, title, description, refresh="30s", time_from="now-6h"):
        self.uid, self.title, self.description = uid, title, description
        self.refresh, self.time_from = refresh, time_from
        self.panels, self.y, self.next_id = [], 0, 1
        self.annotations, self.variables, self.links = [], [], []
        self._row_h = 0

    # ------------------------------------------------------------------ layout
    def row(self, title):
        self._close_row()
        self.panels.append({"id": self._id(), "type": "row", "title": title, "collapsed": False,
                            "gridPos": {"x": 0, "y": self.y, "w": 24, "h": 1}, "panels": []})
        self.y += 1

    def line(self, *panels):
        """Places panels side by side on one line; each panel carries its width and height."""
        self._close_row()
        x = 0
        for p in panels:
            p["gridPos"] = {"x": x, "y": self.y, "w": p.pop("_w"), "h": p.pop("_h")}
            x += p["gridPos"]["w"]
            assert x <= 24, f"{self.title}: line wider than 24 ({p['title']})"
            self.panels.append(p)
            self._row_h = max(self._row_h, p["gridPos"]["h"])

    def _close_row(self):
        self.y += self._row_h
        self._row_h = 0

    def _id(self):
        self.next_id += 1
        return self.next_id

    # ------------------------------------------------------------------ panels
    def _panel(self, kind, title, desc, w, h, datasource, targets, **extra):
        assert desc and len(desc) > 20, f"{self.title}: panel '{title}' needs a description"
        p = {"id": self._id(), "type": kind, "title": title, "description": desc, "datasource": datasource,
             "targets": targets, "_w": w, "_h": h}
        p.update(extra)
        return p

    def stat(self, title, expr, desc, w=4, h=4, unit="none", thresholds=None, mappings=None, decimals=None,
             text="value", legend=None, link=None):
        defaults = {"unit": unit, "thresholds": thresholds or steps((None, "green"), (1, "red")),
                    "color": {"mode": "thresholds"}, "mappings": mappings or []}
        if link:
            # (title, url): clicking the value opens it; ${__field.labels.<name>} reads the series' labels.
            defaults["links"] = [{"title": link[0], "url": link[1], "targetBlank": True}]
        if decimals is not None:
            defaults["decimals"] = decimals
        target = {"refId": "A", "datasource": VM, "expr": expr, "instant": True}
        if legend:
            target["legendFormat"] = legend
        return self._panel("stat", title, desc, w, h, VM, [target],
                           fieldConfig={"defaults": defaults, "overrides": []},
                           options={"reduceOptions": {"calcs": ["lastNotNull"]}, "colorMode": "background",
                                    "graphMode": "none", "textMode": text, "justifyMode": "center"})

    def timeseries(self, title, targets, desc, w=12, h=8, unit="none", stack=False, minv=None, maxv=None,
                   thresholds=None):
        defaults = {"unit": unit, "custom": {"stacking": {"mode": "normal" if stack else "none"},
                                             "fillOpacity": 20 if stack else 5, "showPoints": "never",
                                             "lineWidth": 2}}
        if minv is not None:
            defaults["min"] = minv
        if maxv is not None:
            defaults["max"] = maxv
        if thresholds:
            defaults["thresholds"] = thresholds
            defaults["custom"]["thresholdsStyle"] = {"mode": "line+area"}
        return self._panel("timeseries", title, desc, w, h, VM,
                           [{"refId": chr(65 + i), "datasource": VM, "expr": e, "legendFormat": l}
                            for i, (e, l) in enumerate(targets)],
                           fieldConfig={"defaults": defaults, "overrides": []},
                           options={"legend": {"displayMode": "list", "placement": "bottom"},
                                    "tooltip": {"mode": "multi", "sort": "desc"}})

    def table(self, title, expr, desc, w=24, h=8, columns=None, mappings=None, overrides=None, sort=None,
              transformations=None, unit="none", links=None, hidden=()):
        """Instant query as a table. columns: {label: header}, in order; other labels are hidden."""
        organize = {"excludeByName": {"Time": True, "Value": True, "__name__": True}}
        if columns:
            organize = {"includeByName": {k: True for k in columns},
                        "indexByName": {k: i for i, k in enumerate(columns)},
                        "renameByName": columns}
        defaults = {"unit": unit, "custom": {"cellOptions": {"type": "color-text"}, "align": "left"}}
        if mappings:
            defaults["mappings"] = mappings
        overrides = list(overrides or [])
        # links: {header: (title, url)}; the url may read other columns of the row: ${__data.fields.<header>}.
        for header, (link_title, url) in (links or {}).items():
            overrides.append({"matcher": {"id": "byName", "options": header},
                              "properties": [{"id": "links", "value": [{"title": link_title, "url": url,
                                                                         "targetBlank": True}]}]})
        # Columns a link needs but nobody needs to read.
        for header in hidden:
            overrides.append({"matcher": {"id": "byName", "options": header},
                              "properties": [{"id": "custom.hidden", "value": True}]})
        return self._panel("table", title, desc, w, h, VM,
                           [{"refId": "A", "datasource": VM, "expr": expr, "instant": True, "format": "table"}],
                           fieldConfig={"defaults": defaults, "overrides": overrides},
                           options={"showHeader": True, "cellHeight": "sm",
                                    "sortBy": [{"displayName": sort, "desc": False}] if sort else []},
                           transformations=(transformations or []) + [{"id": "organize", "options": organize}])

    def bars(self, title, targets, desc, w=12, h=8):
        """Horizontal 0..100% bars (instant), e.g. share of new pods ready."""
        return self._panel("bargauge", title, desc, w, h, VM,
                           [{"refId": chr(65 + i), "datasource": VM, "expr": e, "legendFormat": l, "instant": True}
                            for i, (e, l) in enumerate(targets)],
                           fieldConfig={"defaults": {"unit": "percentunit", "min": 0, "max": 1,
                                                     "thresholds": steps((None, "orange"), (1, "green")),
                                                     "color": {"mode": "thresholds"}}, "overrides": []},
                           options={"orientation": "horizontal", "displayMode": "basic", "showUnfilled": True,
                                    "reduceOptions": {"calcs": ["lastNotNull"]}})

    def logs(self, title, expr, desc, w=24, h=12, max_lines=500):
        """Log lines from VictoriaLogs (LogsQL)."""
        return self._panel("logs", title, desc, w, h, LOGS,
                           [{"refId": "A", "datasource": LOGS, "expr": expr, "queryType": "instant",
                             "maxLines": max_lines, "editorMode": "code"}],
                           options={"showTime": True, "wrapLogMessage": True, "sortOrder": "Descending",
                                    "enableLogDetails": True, "dedupStrategy": "none", "prettifyLogMessage": False})

    def log_counts(self, title, expr, legend, desc, w=12, h=8, stack=True):
        """A LogsQL stats query (`... | stats by (...) count()`) over time."""
        return self._panel("timeseries", title, desc, w, h, LOGS,
                           [{"refId": "A", "datasource": LOGS, "expr": expr, "queryType": "statsRange",
                             "legendFormat": legend, "editorMode": "code"}],
                           fieldConfig={"defaults": {"unit": "short", "custom": {
                               "drawStyle": "bars", "fillOpacity": 60, "stacking": {"mode": "normal" if stack else "none"},
                               "showPoints": "never"}}, "overrides": []},
                           options={"legend": {"displayMode": "list", "placement": "bottom"},
                                    "tooltip": {"mode": "multi", "sort": "desc"}})

    def github(self, title, desc, query, w=12, h=8, columns=None, link_field=None, link_title="Открыть",
               sort=None, time_from=None, transformations=None):
        """A table from the GitHub datasource (pull requests, releases, workflow runs)."""
        overrides = []
        if link_field:
            first = next(iter(columns))
            overrides.append({"matcher": {"id": "byName", "options": columns[first]},
                              "properties": [{"id": "links", "value": [{"title": link_title, "targetBlank": True,
                                                                         "url": "${__data.fields." + link_field + "}"}]}]})
        organize = {"includeByName": {k: True for k in columns},
                    "indexByName": {k: i for i, k in enumerate(columns)}, "renameByName": columns}
        if link_field:
            # Kept in the data (the link reads it), hidden in the table.
            overrides.append({"matcher": {"id": "byName", "options": columns[link_field]},
                              "properties": [{"id": "custom.hidden", "value": True}]})
        extra = {}
        if time_from:
            extra["timeFrom"] = time_from
        return self._panel("table", title, desc, w, h, GH, [dict(query, refId="A", datasource=GH)],
                           fieldConfig={"defaults": {"custom": {"align": "left"}}, "overrides": overrides},
                           options={"showHeader": True, "cellHeight": "sm",
                                    "sortBy": [{"displayName": columns[sort], "desc": True}] if sort else []},
                           transformations=(transformations or []) + [{"id": "organize", "options": organize}],
                           **extra)

    def text(self, title, markdown, w=24, h=3):
        """A short explanation; the content is the description."""
        return self._panel("text", title, markdown, w, h, None, [],
                           options={"mode": "markdown", "content": markdown})

    # ------------------------------------------------------------------ extras
    def annotation(self, name, expr, title, text, color):
        self.annotations.append({"name": name, "enable": True, "iconColor": color, "datasource": VM, "expr": expr,
                                 "step": "60s", "titleFormat": title, "textFormat": text, "useValueForTime": False})

    def link(self, title, url):
        self.links.append({"title": title, "url": url, "type": "link", "targetBlank": False, "icon": "dashboard"})

    def render(self):
        self._close_row()
        return {
            "uid": self.uid, "title": self.title, "description": self.description, "tags": ["bulbashenko"],
            "timezone": "browser", "schemaVersion": 39, "refresh": self.refresh, "editable": True,
            "graphTooltip": 1, "time": {"from": self.time_from, "to": "now"},
            "links": self.links, "panels": self.panels,
            "templating": {"list": self.variables},
            "annotations": {"list": [{"builtIn": 1, "type": "dashboard", "name": "Annotations & Alerts",
                                      "datasource": {"type": "grafana", "uid": "-- Grafana --"}, "enable": True,
                                      "hide": True, "iconColor": "rgba(0, 211, 255, 1)"}] + self.annotations},
        }


def nav(d):
    """The same four links on every dashboard, so they read as one set."""
    for title, uid in (("Здоровье", "health"), ("Релизы", "releases"), ("Выкатка", "rollout"), ("Логи", "logs")):
        if uid != d.uid:
            d.link(title, f"/d/{uid}")


RELEASE_MARKER = ('max by (revision) (flux_resource_info{kind="GitRepository", exported_namespace="flux-system", '
                  'name="flux-system"}) unless max by (revision) (flux_resource_info{kind="GitRepository", '
                  'exported_namespace="flux-system", name="flux-system"} offset 2m)')


def release_markers(d):
    d.annotation("Релиз", RELEASE_MARKER, "Релиз", "main → {{revision}}", "green")


GITHUB = f"https://github.com/{ORG}"
# Full commit SHA of a Flux revision ("refs/heads/main@sha1:<sha>", "sha1:<sha>") or of an image tag (":<sha>").
SHA_FROM_REVISION = ".*sha1:([0-9a-f]{40}).*"
SHA_FROM_IMAGE = ".*:([0-9a-f]{40})$"


def with_repo(expr):
    """Adds `repo`: the GitHub repository a Flux object's revision belongs to (from its source)."""
    return ('label_replace(label_replace(' + expr + ', "repo", "infra", "source_name", "flux-system|infra-dev"), '
            '"repo", "$1", "source_name", "(auth|mail|teamspeak)")')
