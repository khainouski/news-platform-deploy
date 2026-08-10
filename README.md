# news-platform-deploy

GitOps deployment repo for News Explorer's production platform.

- **Deploys** — the app, Postgres, and the observability stack (Prometheus, Tempo, Loki, Grafana)
- **How** — Argo CD watches this repo and applies every change to the cluster automatically;
  nothing here is ever applied by hand
- **Doesn't** — build the app image (`news-explorer`) or provision the cluster
  (`news-explorer-infra`); this repo only owns what's deployed on top of both

## Repository layout

- **`apps/news-explorer/`** — this repo's own Helm chart for the app
  - `values.yaml` — image, resources, ingress host, sync schedule
  - `templates/deployment.yaml`, `service.yaml`, `ingress.yaml` — the running app
  - `templates/sync-cronjob.yaml` — hourly feed sync
  - `templates/migrate-job.yaml` — runs schema migrations before every deploy (Argo CD PreSync hook)
- **`argocd/`** — what Argo CD manages, one YAML file per thing
  - `root-application.yaml` — applied once by hand at bootstrap, never touched again (see [Architecture](#architecture))
  - `applications/*.yaml` — one file per component (see [Applications](#applications)).
    **To redeploy the app, edit `applications/news-explorer.yaml`** — bump `image.tag`, commit,
    push (see [Common operations](#common-operations))
- **`platform/`** — config for everything that isn't the app itself, one subfolder per component:
  `monitoring/` (Prometheus, Tempo, Loki, Grafana, Alloy), `postgresql/`, `cert-manager/`,
  `traefik/`, `argocd/` (its own ingress)

## Architecture

```text
news-explorer-infra (Terraform + cloud-init)
      │  one-time: installs k3s, bootstraps Argo CD, applies
      │  argocd/root-application.yaml by hand
      ▼
Argo CD "root" Application (app-of-apps)
      │  watches THIS repo — argocd/applications/, recurse
      │  auto-syncs every child Application (prune + selfHeal)
      ▼
argocd/applications/*.yaml   (~12 Application manifests, one per component)
      │  each points at either this repo's own path (apps/news-explorer, platform/*)
      │  or a third-party Helm chart + a $values file committed here
      ▼
k3s cluster (single DigitalOcean Droplet)
  ├─ apps          news-explorer   — Deployment/Service/Ingress + hourly sync CronJob
  │                                  + PreSync migrate Job
  ├─ database      postgresql      — Bitnami chart, standalone architecture
  ├─ monitoring    prometheus · tempo · loki · grafana · alloy
  ├─ cert-manager  cert-manager + 2 ClusterIssuers (staging verified first, then prod)
  ├─ kube-system   traefik-config  — patches k3s's bundled Traefik (HTTP→HTTPS redirect)
  └─ argocd        argocd-ingress  — Ingress for Argo CD's own UI

exposed hostnames (Traefik + cert-manager/Let's Encrypt):
  goskills.xyz          → news-explorer
  grafana.goskills.xyz  → Grafana
  argocd.goskills.xyz   → Argo CD UI

observability is cross-linked, not three separate silos:
  Tempo's metrics-generator turns spans into RED metrics, remote-written into Prometheus
  Grafana's Loki datasource extracts trace_id from log lines to jump straight into Tempo
```

## Applications

| Application | Namespace | Source | Role |
|---|---|---|---|
| `news-explorer` | `apps` | this repo — `apps/news-explorer` | The app: Deployment, Service, Ingress, hourly sync CronJob, PreSync migrate Job |
| `postgresql` | `database` | Bitnami chart | The app's database, standalone architecture |
| `prometheus` | `monitoring` | prometheus-community chart | Metrics — scrapes `/metrics` via pod annotations, 15d retention |
| `tempo` | `monitoring` | grafana chart | Traces — OTLP/gRPC receiver; metrics-generator also feeds span-derived RED metrics back into Prometheus |
| `loki` | `monitoring` | grafana chart | Logs — `SingleBinary` mode, filesystem storage |
| `alloy` | `monitoring` | grafana chart | Log shipper — tails every pod's stdout via Kubernetes service discovery, pushes to Loki |
| `grafana` | `monitoring` | grafana chart | Dashboards — Prometheus/Loki/Tempo datasources, with log↔trace correlation via `trace_id` |
| `grafana-dashboards` | `monitoring` | this repo — `platform/monitoring/dashboards` | 3 provisioned dashboards (HTTP RED, Go runtime, tracing), picked up by Grafana's sidecar |
| `cert-manager` | `cert-manager` | jetstack chart | TLS certificate automation |
| `cluster-issuer` | `cert-manager` | this repo — `platform/cert-manager/cluster-issuer` | 2 `ClusterIssuer`s (Let's Encrypt staging + prod) |
| `traefik-config` | `kube-system` | this repo — `platform/traefik` | `HelmChartConfig` patch onto k3s's bundled Traefik |
| `argocd-ingress` | `argocd` | this repo — `platform/argocd` | Exposes the Argo CD UI at `argocd.goskills.xyz` |

Exact chart versions and pinned image digests live in each `argocd/applications/*.yaml` and
`platform/*/*-values.yaml` — not duplicated here, so this table can't drift out of sync with them.

## Secrets

Nothing in this repo is a real credential. Postgres (`postgresql-credentials`,
`news-explorer-postgres-credentials`) and Grafana (`grafana-admin-credentials`) passwords are
generated once, directly on the cluster, by `news-explorer-infra`'s cloud-init (`openssl rand` +
`kubectl create secret`) — before Argo CD ever syncs a chart that references them via
`existingSecret`. That's a deliberate workaround, not an oversight: Argo CD renders every chart
via `helm template` with no live-cluster access, so a chart's own "generate a random password once,
then reuse it" logic (which depends on Helm's `lookup` seeing the existing Secret) silently mints
a *new* password on every sync instead of keeping the old one — hit for real on both the
`postgresql` and `grafana` charts here before landing on `existingSecret`.

**Reading a password out of the cluster** (`admin`/`admin-user` is the username in both cases):

```shell
# Grafana - https://grafana.goskills.xyz
ssh root@$DROPLET_IP "k3s kubectl -n monitoring get secret grafana-admin-credentials -o jsonpath='{.data.admin-password}' | base64 -d; echo"

# Argo CD - https://argocd.goskills.xyz (argocd-initial-admin-secret is created by Argo CD's own
# installer, not by cloud-init - same read pattern either way)
ssh root@$DROPLET_IP "k3s kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo"
```

`$DROPLET_IP` is `terraform output -raw droplet_ipv4` from `news-explorer-infra`.

## Common operations

**Bootstrap from zero** — see `news-explorer-infra`'s README. `terraform apply` provisions the
Droplet; cloud-init does the rest (k3s, Argo CD, the secrets above, and the one
`root-application.yaml`). Nothing in *this* repo is ever applied by hand.

**Release a new `news-explorer` version** (see [Repository layout](#repository-layout) for which
file):
1. Merge to `news-explorer`'s `main` — CI builds and pushes `ghcr.io/khainouski/news-explorer:sha-<commit>`.
2. Commit + push the new tag.
3. Argo CD's automated sync picks it up — no manual `kubectl`/`helm` needed. (`helm lint`/
   `helm upgrade --install` from `apps/news-explorer/README.md` still work for a local dry run.)

**Add a new platform component** — add one `argocd/applications/<name>.yaml` (any existing one is
a template) and, if it needs non-default values, a `platform/<name>/*-values.yaml`. The root
Application discovers it on its next sync automatically — nothing else to register.

## Related repositories

| Repository | Role |
|---|---|
| [`news-explorer`](https://github.com/khainouski/news-explorer) | App code, Dockerfile, CI — builds and pushes the image this repo deploys |
| [`news-explorer-infra`](https://github.com/khainouski/news-explorer-infra) | Terraform — provisions the Droplet this repo's cluster runs on, and bootstraps it via cloud-init |
| `news-explorer-client` | Synthetic load generator — drives traffic against the deployment this repo manages, so Grafana has real data to show |
