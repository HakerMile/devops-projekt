# Production deployment (Kubernetes / OpenShift)

Manifesti za produkcijski deployment **Secure Event Ticketing Platform** aplikacije.
Pokriva sve servise, sigurnosne kontrole (RBAC, NetworkPolicy, PSA, non-root),
health probe, resource limite, Ingress i rolling update/rollback.

## Sadržaj `infra/k8s/`

| Datoteka                   | Objekti                                                    |
|----------------------------|------------------------------------------------------------|
| `00-namespace.yaml`        | Namespace + Pod Security Admission labele                  |
| `01-resourcequota.yaml`    | ResourceQuota + LimitRange (CPU/memory)                    |
| `02-rbac.yaml`             | ServiceAccount + Role + RoleBinding (least-privilege)      |
| `03-configmap.yaml`        | App konfiguracija + PostgreSQL init schema                 |
| `04-secret.example.yaml`   | **Template** za DB credentials (ne deployati direktno)     |
| `10-postgres.yaml`         | PVC + Deployment + Service                                 |
| `11-redis.yaml`            | Deployment + Service                                       |
| `12-api.yaml`              | Deployment (2 replike) + Service                           |
| `13-worker.yaml`           | Deployment                                                 |
| `14-frontend.yaml`         | Deployment (2 replike) + Service                           |
| `20-ingress.yaml`          | Ingress (`ticketing.local`, `/` + `/api`)                  |
| `30-networkpolicy.yaml`    | Default-deny + per-tier allow pravila                      |
| `kustomization.yaml`       | Agregira sve osim Secreta                                  |

## Preduvjeti

- Kubernetes klaster (k3s / kind / minikube / managed) ili OpenShift
- `kubectl` (+ opcionalno `kustomize`)
- ingress-nginx controller instaliran (za Ingress)
- Container slike izgrađene i objavljene u registry (vidi dolje)

## 1. Build i objava slika

Manifesti referenciraju `ghcr.io/hakermile/ticketing-<servis>:1.0.0`. Prilagodi
registry/tag svojem okruženju.

```bash
# build (zadani runtime target = minimalna non-root slika)
docker build -t ghcr.io/hakermile/ticketing-api:1.0.0 ./api
docker build -t ghcr.io/hakermile/ticketing-worker:1.0.0 ./worker
docker build -t ghcr.io/hakermile/ticketing-frontend:1.0.0 ./frontend

# skeniranje prije objave (quality gate - vidi docs/security/image-scan-report.md)
trivy image --severity HIGH,CRITICAL --exit-code 1 ghcr.io/hakermile/ticketing-api:1.0.0

# push
docker push ghcr.io/hakermile/ticketing-api:1.0.0
docker push ghcr.io/hakermile/ticketing-worker:1.0.0
docker push ghcr.io/hakermile/ticketing-frontend:1.0.0
```

> **Politika tagova:** koristi nepromjenjive verzijske tagove (`1.0.0`,
> `git-<sha>`) — nikad `latest` u produkciji. Tako rollback uvijek cilja
> poznatu, skeniranu sliku.

## 2. Kreiraj Secret (bez hardkodiranih lozinki)

Secret se **ne** nalazi u Gitu ni u `kustomization.yaml`. Kreira se zasebno:

```bash
kubectl create namespace secure-event-ticketing

kubectl -n secure-event-ticketing create secret generic ticketing-db-credentials \
  --from-literal=POSTGRES_USER=ticketing_user \
  --from-literal=POSTGRES_PASSWORD="$(openssl rand -base64 24)"
```

## 3. Deploy svih servisa

```bash
# jednom naredbom kroz kustomize
kubectl apply -k infra/k8s/

# (alternativno) pojedinačno, redoslijedom
kubectl apply -f infra/k8s/00-namespace.yaml
kubectl apply -f infra/k8s/   # ostatak
```

Provjeri:

```bash
kubectl -n secure-event-ticketing get pods,svc,ingress
kubectl -n secure-event-ticketing rollout status deploy/api
```

## 4. Vanjski pristup

```bash
# dodaj host u /etc/hosts (zamijeni IP-em ingress controllera)
echo "127.0.0.1 ticketing.local" | sudo tee -a /etc/hosts

curl http://ticketing.local/api/healthz
curl http://ticketing.local/api/events
# UI: http://ticketing.local
```

### OpenShift varijanta

Umjesto Ingressa koristi Route:

```bash
oc -n secure-event-ticketing expose service frontend --hostname=ticketing.apps.<cluster>
oc -n secure-event-ticketing expose service api --path=/api --hostname=ticketing.apps.<cluster>
```

OpenShift po defaultu pokreće kontejnere s nasumičnim UID-om; slike su već
non-root i kompatibilne s `restricted` SCC-om.

## 5. Rolling update i rollback

```bash
# rolling update na novu verziju (maxUnavailable=0 -> bez downtimea)
kubectl -n secure-event-ticketing set image deploy/api api=ghcr.io/hakermile/ticketing-api:1.1.0
kubectl -n secure-event-ticketing rollout status deploy/api

# povijest i rollback
kubectl -n secure-event-ticketing rollout history deploy/api
kubectl -n secure-event-ticketing rollout undo deploy/api
kubectl -n secure-event-ticketing rollout undo deploy/api --to-revision=2
```

## Sigurnosne kontrole (sažetak)

- **Non-root** kontejneri, `allowPrivilegeEscalation: false`, `drop ALL` caps,
  `readOnlyRootFilesystem` (app servisi), `seccompProfile: RuntimeDefault`
- **Pod Security Admission** na namespaceu (`baseline` enforce, `restricted` warn)
- **RBAC**: dedicirani ServiceAccount, bez auto-mounta tokena, minimalni Role
- **NetworkPolicy**: default-deny ingress + eksplicitni allow per tier;
  baza/redis dostupni samo iz `api`/`worker`
- **Secret odvojen** od konfiguracije i izvan Gita
- **ResourceQuota + LimitRange** spriječavaju resource iscrpljivanje
- **Liveness/Readiness/Startup probe** na ključnim servisima

Incidentni postupci: [`docs/runbook.md`](../../docs/runbook.md).
Izvješće skeniranja slika: [`docs/security/image-scan-report.md`](../../docs/security/image-scan-report.md).
