# news-explorer — Helm chart

```bash
helm lint apps/news-explorer

helm upgrade --install news-explorer apps/news-explorer \
  --namespace apps --create-namespace \
  --set image.tag=sha-<commit>
```

## Values

| Key | Description | Default |
|---|---|---|
| `image.repository` | GHCR image | `ghcr.io/khainouski/news-explorer` |
| `image.tag` | Image tag — never `latest` for a real deployment | `"latest"` |
| `replicaCount` | Pod replicas | `1` |
| `resources` | Pod requests/limits | `100m/16Mi` – `200m/32Mi` |
| `service.port` | Service port | `8080` |
| `ingress.enabled` | Create an Ingress | `true` |
| `ingress.host` | Ingress host — empty matches any `Host` header | `""` |
| `ingress.path` | Ingress path | `"/"` |
