set shell := ["bash", "-euo", "pipefail", "-c"]

# list recipes
default:
    @just --list

# run all local checks (gitleaks, SOPS, fmt)
check:
    pre-commit run --all-files

# edit an encrypted file (creates it if missing)
secret file:
    sops {{file}}

# OpenTofu plan with the read-only credentials (CI posts the same on every PR touching terraform/)
plan:
    cd terraform && sops exec-env creds-plan.sops.env "sops exec-env secrets.sops.env 'tofu init -input=false >/dev/null && tofu plan -input=false -lock=false -compact-warnings'"

# break-glass only: CI applies on every release (.github/workflows/tofu.yml). Owner, read-write credentials.
apply-local:
    cd terraform && sops exec-env creds-apply.sops.env "sops exec-env secrets.sops.env 'tofu init -input=false >/dev/null && tofu apply -input=false'"

# one-time: tokens, age keys and GitHub secrets for OpenTofu in CI (owner; see the script header)
tofu-ci-bootstrap:
    scripts/tofu-ci-bootstrap.sh

# one-time Headscale pre-auth key (tag:core, 30 min) into terraform/secrets.sops.env; asks for your sudo password on hel1-edge
node-key:
    #!/usr/bin/env bash
    set -euo pipefail
    read -rsp "sudo password on hel1-edge: " pw; echo
    out=$(printf '%s\n' "$pw" | ssh bulbashenko@62.238.18.202 \
      'sudo -S -p "" docker exec headscale-gml9nuytnpijytqxqkundgva headscale preauthkeys create --tags tag:core --expiration 30m -o json')
    unset pw
    key=$(printf '%s' "$out" | jq -r '.key // empty' 2>/dev/null || true)
    if [ -z "$key" ]; then
      echo "no key in headscale output; its shape (values hidden):" >&2
      printf '%s' "$out" | jq -c 'paths(scalars) | map(tostring) | join(".")' 2>/dev/null >&2 || printf '%s\n' "$out" | sed 's/[A-Za-z0-9]\{20,\}/<redacted>/g' >&2
      exit 1
    fi
    printf '%s' "$key" | jq -Rs . | sops set --value-stdin terraform/secrets.sops.env '["TF_VAR_tailscale_authkey"]'
    echo "pre-auth key stored (expires in 30 min): commit it and release now (CI applies), or just apply-local"

# pin <app> to <sha> on dev (default: the app's latest main; an older sha rolls back); prod gets it with the release
promote app sha="":
    gh workflow run promote.yml -R bulbashenko-com/infra -f app={{app}} -f sha={{sha}}
    @echo "runs: https://github.com/bulbashenko-com/infra/actions/workflows/promote.yml"

# preview a pin (diff + commit message) locally without writing anything
promote-dry app sha="":
    DRY_RUN=1 scripts/promote.sh {{app}} {{sha}}

# refresh staging from production's latest content export: bumps REVISION on dev through an auto-merging PR
staging-refresh:
    #!/usr/bin/env bash
    set -euo pipefail
    f=apps/staging/site/kustomization.yaml
    git fetch -q origin dev
    rev=$(git show origin/dev:$f | sed -nE 's/^ *- REVISION=([0-9]+)$/\1/p')
    next=$((rev + 1)) branch=staging-refresh-$next
    content=$(git show origin/dev:$f | sed -E "s/^( *- REVISION=)[0-9]+$/\1$next/")
    git switch -q -c "$branch" origin/dev
    printf '%s\n' "$content" > "$f"
    git commit -q -m "Refresh staging (revision $next)" -- "$f"
    git push -q -u origin "$branch"
    gh pr create --base dev --head "$branch" --title "Refresh staging (revision $next)" --body "Re-runs the staging-refresh Job (apps/staging/site/refresh.sh)."
    gh pr merge "$branch" --auto --merge
    git switch -q -

kube_admin := env_var('HOME') / ".kube/hel1-admin.yaml"

# one-time: install Flux Operator, the cluster SOPS key and the FluxInstance (owner, admin kubeconfig)
bootstrap-flux:
    #!/usr/bin/env bash
    set -euo pipefail
    export KUBECONFIG={{kube_admin}}
    helm upgrade --install flux-operator oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator \
      --version 0.61.0 --namespace flux-system --create-namespace --wait
    sops decrypt bootstrap/hel1/sops-age.sops.yaml | kubectl apply -f -
    kubectl apply -f clusters/hel1/flux-instance.yaml
    kubectl -n flux-system wait fluxinstance/flux --for=condition=Ready --timeout=5m
    kubectl -n flux-system get fluxinstance,kustomizations,helmreleases

# write ~/.kube/hel1-readonly.yaml for AI agents from the claude-readonly ServiceAccount (owner)
kubeconfig-readonly:
    #!/usr/bin/env bash
    set -euo pipefail
    export KUBECONFIG={{kube_admin}}
    out="$HOME/.kube/hel1-readonly.yaml"
    server=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
    ca=$(kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')
    token=$(kubectl -n access get secret claude-readonly-token -o jsonpath='{.data.token}' | base64 -d)
    umask 077
    printf '%s\n' "apiVersion: v1" "kind: Config" \
      "clusters: [{name: hel1, cluster: {server: $server, certificate-authority-data: $ca}}]" \
      "users: [{name: claude-readonly, user: {token: $token}}]" \
      "contexts: [{name: hel1-readonly, context: {cluster: hel1, user: claude-readonly}}]" \
      "current-context: hel1-readonly" > "$out"
    unset token
    KUBECONFIG="$out" kubectl auth can-i --list >/dev/null && echo "wrote $out"

# compact cluster status (read-only kubeconfig)
status:
    #!/usr/bin/env bash
    set -euo pipefail
    export KUBECONFIG="$HOME/.kube/hel1-readonly.yaml"
    kubectl get nodes --no-headers
    flux get all -A --status-selector ready=false 2>/dev/null | grep -v '^$' || true
    kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded --no-headers 2>/dev/null || true

# after the apply that created the tunnel: store its connector token as a SOPS Secret for cloudflared
tunnel-token:
    #!/usr/bin/env bash
    set -euo pipefail
    f=infrastructure/configs/cloudflared/tunnel-token.sops.yaml
    mkdir -p "$(dirname "$f")"
    # Straight from the API (needs Tunnel Write, so the apply credentials): the token is a secret and stays out of
    # the OpenTofu state.
    id=$(cd terraform && sops exec-env creds-plan.sops.env "sops exec-env secrets.sops.env 'tofu output -raw tunnel_hel1_id'")
    tok=$(sops exec-env terraform/creds-apply.sops.env "curl -fsS -H \"Authorization: Bearer \$CLOUDFLARE_API_TOKEN\" https://api.cloudflare.com/client/v4/accounts/e6a72845a55a3840d8b52c2d7fdf3004/cfd_tunnel/$id/token" | jq -er .result)
    printf 'apiVersion: v1\nkind: Secret\nmetadata:\n  name: tunnel-token\n  namespace: cloudflared\ntype: Opaque\nstringData:\n  token: %s\n' "$tok" \
      | sops encrypt --filename-override "$f" --input-type yaml --output-type yaml /dev/stdin > "$f"
    unset tok
    echo "wrote $f"
