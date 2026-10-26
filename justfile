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

tofu := "sops exec-env secrets.sops.env"

# OpenTofu plan (credentials from terraform/secrets.sops.env)
plan:
    cd terraform && {{tofu}} 'tofu init -input=false >/dev/null && tofu plan -input=false -compact-warnings'

# OpenTofu apply: owner only. Then ships the new encrypted state as an auto-merging PR.
apply:
    cd terraform && {{tofu}} 'tofu apply -input=false'
    just _ship-state

# commit terraform.tfstate on a state/* branch and open an auto-merge PR
_ship-state:
    #!/usr/bin/env bash
    set -euo pipefail
    f=terraform/terraform.tfstate
    if git ls-files --error-unmatch "$f" >/dev/null 2>&1 && git diff --quiet -- "$f"; then
      echo "state unchanged"; exit 0
    fi
    grep -q '"encrypted_data"' "$f" || { echo "refusing: $f is not encrypted" >&2; exit 1; }
    b="state/$(date -u +%Y%m%d-%H%M%S)"
    git switch -q -c "$b"
    git add "$f"
    git commit -q -m "Update encrypted state after apply"
    git -c credential.helper= -c credential.helper='!gh auth git-credential' push -q -u origin "$b"
    gh pr create --base main --title "State after apply ($b)" --body "Encrypted terraform.tfstate written by \`just apply\`."
    gh pr merge --auto --merge --delete-branch
    echo "Staying on $b. After the PR merges: git switch main && git pull"


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
    echo "pre-auth key stored (expires in 30 min): run just apply now"

# pin <app> to <sha> on main (default: the app's latest main; an older sha rolls back); prod gets it with the release
promote app sha="":
    gh workflow run promote.yml -R bulbashenko-com/infra -f app={{app}} -f sha={{sha}}
    @echo "runs: https://github.com/bulbashenko-com/infra/actions/workflows/promote.yml"

# preview a pin (diff + commit message) locally without writing anything
promote-dry app sha="":
    DRY_RUN=1 scripts/promote.sh {{app}} {{sha}}

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

# after `just apply` created the tunnel: store its connector token as a SOPS Secret for cloudflared
tunnel-token:
    #!/usr/bin/env bash
    set -euo pipefail
    f=infrastructure/configs/cloudflared/tunnel-token.sops.yaml
    mkdir -p "$(dirname "$f")"
    tok=$(cd terraform && sops exec-env secrets.sops.env 'tofu output -raw tunnel_hel1_token')
    printf 'apiVersion: v1\nkind: Secret\nmetadata:\n  name: tunnel-token\n  namespace: cloudflared\ntype: Opaque\nstringData:\n  token: %s\n' "$tok" \
      | sops encrypt --filename-override "$f" --input-type yaml --output-type yaml /dev/stdin > "$f"
    unset tok
    echo "wrote $f"
