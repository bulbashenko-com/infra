#!/usr/bin/env python3
"""Secrets for the CI cluster (.github/workflows/cluster-e2e.yml): prints Namespaces and Secrets to apply before Flux.

Values come from scripts/ci-secrets.yaml. Fails when that file and the SOPS Secrets the CI cluster deploys disagree on
a Secret or its keys (key names are plaintext in *.sops.yaml), so a new production secret cannot silently miss CI.

  scripts/ci-secrets.py            print the manifests
  scripts/ci-secrets.py --check    only compare (no values made)
"""
import re
import secrets
import subprocess
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
# Not deployed by the CI cluster: Flux's own key (bootstrap) and staging (clusters/ci drops it).
SKIP = ("bootstrap/", "apps/staging/", "apps/staging-platform/")


def sops_secrets():
    """{namespace/name: set(keys)} of every SOPS Secret the CI cluster deploys."""
    files = subprocess.check_output(["git", "ls-files", "*.sops.yaml"], cwd=ROOT, text=True).split()
    found = {}
    for f in files:
        if f.startswith(SKIP) or "/" not in f:
            continue
        for doc in yaml.safe_load_all((ROOT / f).read_text()):
            if not doc or doc.get("kind") != "Secret":
                continue
            ns = doc["metadata"].get("namespace") or kustomization_namespace(ROOT / f)
            if not ns:
                sys.exit(f"{f}: no namespace in the Secret or its kustomization.yaml")
            keys = set(doc.get("stringData") or {}) | set(doc.get("data") or {})
            found[f"{ns}/{doc['metadata']['name']}"] = keys
    return found


def kustomization_namespace(path):
    k = path.parent / "kustomization.yaml"
    return yaml.safe_load(k.read_text()).get("namespace") if k.exists() else None


def compare(spec, found):
    errors = []
    for name in sorted(set(found) - set(spec)):
        errors.append(f"{name}: in SOPS, missing from scripts/ci-secrets.yaml")
    for name in sorted(set(spec) - set(found)):
        errors.append(f"{name}: in scripts/ci-secrets.yaml, no such SOPS Secret")
    for name in sorted(set(spec) & set(found)):
        want, have = found[name], set(spec[name])
        if want != have:
            errors.append(f"{name}: keys differ; missing {sorted(want - have)}, extra {sorted(have - want)}")
    return errors


def rsa_key():
    return subprocess.check_output(["openssl", "genrsa", "2048"], stderr=subprocess.DEVNULL, text=True)


FORMATS = {
    None: lambda: secrets.token_hex(16),
    "hex64": lambda: secrets.token_hex(32),
    "gk": lambda: "GK" + secrets.token_hex(12),
    "rsa": rsa_key,
}


def render(spec):
    values = {}

    def value(m):
        name, fmt = m.group(1), m.group(2)
        key = (name, fmt)
        if key not in values:
            values[key] = FORMATS[fmt]()
        return values[key]

    docs, namespaces = [], set()
    for full, data in spec.items():
        ns, name = full.split("/", 1)
        namespaces.add(ns)
        string_data = {k: re.sub(r"\{\{(\w+)(?::(\w+))?\}\}", value, str(v)) for k, v in data.items()}
        docs.append({"apiVersion": "v1", "kind": "Secret", "type": "Opaque",
                     "metadata": {"name": name, "namespace": ns}, "stringData": string_data})
    ns_docs = [{"apiVersion": "v1", "kind": "Namespace", "metadata": {"name": n}} for n in sorted(namespaces)]
    return ns_docs + docs


def main():
    spec = yaml.safe_load((ROOT / "scripts/ci-secrets.yaml").read_text())["secrets"]
    errors = compare(spec, sops_secrets())
    if errors:
        sys.exit("scripts/ci-secrets.yaml is out of date:\n  " + "\n  ".join(errors))
    if "--check" in sys.argv:
        print(f"ok: {len(spec)} Secrets match")
        return
    yaml.safe_dump_all(render(spec), sys.stdout, sort_keys=False)


if __name__ == "__main__":
    main()
