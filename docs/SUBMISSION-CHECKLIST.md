# Popis za predaju — evidencija po ishodima učenja (I1–I6, 100 bodova)

Što treba **dokumentirati i evidentirati u završnom dokumentu** da se dobiju
maksimalni bodovi. Za svaki element: gdje je u repou + što priložiti (screenshot /
log / naredba). Status: ✅ u kodu/dokumentaciji · 📸 treba snimiti dokaz.

> **Repo:** https://github.com/HakerMile/devops-projekt
> Prije snimanja dokaza izvrši validaciju iz zadnjeg poglavlja.

---

## I1 — Procjena upotrebe kontejnera i servisa (16)

| Element (bodovi) | Evidencija u repou | U dokument priložiti |
|---|---|---|
| Usporedba kontejnera i VM (4) | `docs/architecture.md` §1 | ✅ tablica usporedbe + obrazloženje izbora |
| Odabir servisa i uloga (4) | `docs/architecture.md` §2 | ✅ tablica servisa + zašto svaki |
| Arhitektura i međuservisna komunikacija (4) | `docs/architecture.md` §3–4, README dijagram | ✅ dijagram toka + portovi/protokoli |
| Usklađenost s ciljevima (4) | `docs/architecture.md` §5 | ✅ mapiranje ciljeva → rješenja |

## I2 — Sigurno upravljanje kontejnerskim slikama (16)

| Element (bodovi) | Evidencija | U dokument |
|---|---|---|
| Prakse sigurnosti pri izradi (4) | `*/Containerfile`, `docs/devsecops.md` §2 | ✅ multi-stage, `.dockerignore`, bez tajni |
| Minimalna slika i non-root (4) | `Containerfile` (`USER node`), alpine | 📸 `docker run --rm <img> id` → uid=1000; `docker image ls` (veličina) |
| Skeniranje ranjivosti i evidencija (4) | `docs/security/image-scan-report.md`, `docs/security/scans/`, `scripts/trivy-scan.sh` | ✅ izvješće + 📸 Trivy output |
| Tagging i politika objave (4) | `docs/devsecops.md` §2, CI `build-scan-push` | ✅ immutable SHA/semver, nikad `latest` |

## I3 — Ubrzana isporuka aplikacije (17)

| Element (bodovi) | Evidencija | U dokument |
|---|---|---|
| Automatizirani build i test (4) | `.github/workflows/ci-cd.yaml` (`test`, `smoke-test`, `build-scan-push`) | 📸 zeleni Actions run |
| Build i objava u registru (4) | CI `build-scan-push` → GHCR | 📸 GHCR Packages stranica s tagovima |
| Standardiziran deployment (3) | `infra/k8s/` + `kubectl apply -k`, CI `deploy` | ✅ kustomize + upute |
| Reproducibilna i pouzdana isporuka (3) | `package-lock.json`, `npm ci`, immutable tagovi | ✅ obrazloženje |
| Mjerljiv napredak brzine (3) | `docs/devsecops.md` §7 | ✅ DORA metrike + 📸 trajanje pipelinea |

## I4 — Primjena DevSecOps metodologije (17)

| Element (bodovi) | Evidencija | U dokument |
|---|---|---|
| Sigurnosne provjere u CI/CD (4) | `iac-scan`, Trivy image scan, SARIF | 📸 Security tab / scan logovi |
| Quality gate prije objave/deploya (4) | `build-scan-push` (`exit-code 1`) | ✅ + 📸 (po želji demo pada na ranjivosti) |
| Tajne i konfiguracija bez hardcodinga (3) | `Secret`/`ConfigMap`, `.gitignore`, GH Secrets | ✅ `docs/devsecops.md` §4 |
| Obrazloženje DevSecOps alata i praksi (3) | `docs/devsecops.md` §1,§6 | ✅ tablica alata + zašto |
| Dosljednost nalaza i korektivnih mjera (3) | `docs/devsecops.md` §3 | ✅ tablica nalaz → mjera |

## I5 — Rješavanje problema isporuke (17)

| Element (bodovi) | Evidencija | U dokument |
|---|---|---|
| Realni incidentni scenariji (4) | `docs/runbook.md` (pad baze, loš tag, neispravan secret) | ✅ |
| Dijagnostika i analiza uzroka (4) | runbook: dijagnostika po scenariju | ✅ |
| Korektivne mjere i validacija (3) | runbook: mjera + validacija | ✅ |
| Kvaliteta runbook dokumentacije (3) | `docs/runbook.md` | ✅ |
| Sistematičan troubleshooting (3) | runbook: opći tok na kraju | ✅ + 📸 (po želji demonstriraj jedan scenarij) |

## I6 — Orkestracija u složenijem scenariju (17)

| Element (bodovi) | Evidencija | U dokument |
|---|---|---|
| Deploy na Kubernetes/OpenShift (4) | `infra/k8s/`, `infra/k8s/README.md` | 📸 `kubectl get pods` (svi Ready) |
| Readiness/liveness i resursi (4) | probe + `resources` u svim Deploymentima, ResourceQuota | ✅ + 📸 `kubectl describe` |
| Ingress/Route i mrežna konfiguracija (3) | `20-ingress.yaml`, OpenShift Route upute | 📸 pristup kroz Ingress |
| Secrets, RBAC i segmentacija (3) | `02-rbac.yaml`, `30-networkpolicy.yaml`, Secret | ✅ + 📸 NetworkPolicy test |
| Rolling update i rollback (3) | Deployment strategija, CI auto-rollback, runbook | 📸 `rollout history` + `rollout undo` |

---

## Struktura završnog dokumenta (preporuka)

1. **Uvod** — opis aplikacije i ciljeva (kratko, iz README-a).
2. **Arhitektura (I1)** — iz `docs/architecture.md` (+ dijagram).
3. **Kontejnerizacija i sigurnost slika (I2)** — Containerfileovi, hardening, scan.
4. **CI/CD i ubrzana isporuka (I3)** — pipeline dijagram, metrike, screenshotovi.
5. **DevSecOps kontrole (I4)** — gateovi, tajne, alati, nalazi→mjere.
6. **Orkestracija (I6)** — Kubernetes manifesti, demo deploya, rolling update/rollback.
7. **Troubleshooting (I5)** — sažetak runbooka + demonstrirani scenarij.
8. **Prilozi** — screenshotovi, scan izvješće, linkovi na repo datoteke.

## Validacija koju treba pokrenuti i snimiti (dokazi 📸)

> Preduvjeti: Docker, kubectl, kind/minikube, Trivy (vidi `README.md` / `infra/k8s/README.md`).

```bash
# --- 1. dio: Compose ---
cp .env.example .env
docker compose up --build -d
docker compose ps                      # 📸 svi servisi "healthy"
curl localhost:8080/healthz            # 📸
curl localhost:8080/readyz             # 📸
curl -X POST localhost:8080/tickets/purchase -H 'Content-Type: application/json' \
  -d '{"eventId":"evt-1001","customerEmail":"student@example.com","quantity":2}'   # 📸
curl localhost:8080/tickets/orders     # 📸 status "processed"
# UI: http://localhost:3000            # 📸

# --- Slika: minimalna + non-root ---
docker build -t ticketing-api:local ./api
docker image ls ticketing-api:local    # 📸 veličina
docker run --rm ticketing-api:local id # 📸 uid=1000

# --- Trivy scan ---
./scripts/trivy-scan.sh                # 📸 + docs/security/image-scan-report.md

# --- 2. dio: Kubernetes ---
kind create cluster --name ticketing
for s in api worker frontend; do
  docker tag ticketing-$s:local ghcr.io/hakermile/ticketing-$s:1.0.0
  kind load docker-image ghcr.io/hakermile/ticketing-$s:1.0.0 --name ticketing
done
kubectl create ns secure-event-ticketing
kubectl -n secure-event-ticketing create secret generic ticketing-db-credentials \
  --from-literal=POSTGRES_USER=ticketing_user \
  --from-literal=POSTGRES_PASSWORD="$(openssl rand -base64 24)"
kubectl apply -k infra/k8s/
kubectl -n secure-event-ticketing get pods            # 📸 svi Ready
kubectl -n secure-event-ticketing describe deploy/api # 📸 probe + resursi

# --- Rolling update + rollback ---
kubectl -n secure-event-ticketing set image deploy/api api=ghcr.io/hakermile/ticketing-api:1.0.1
kubectl -n secure-event-ticketing rollout status deploy/api   # 📸
kubectl -n secure-event-ticketing rollout history deploy/api  # 📸
kubectl -n secure-event-ticketing rollout undo deploy/api     # 📸

# --- NetworkPolicy segmentacija (frontend NE smije do baze) ---
kubectl -n secure-event-ticketing exec deploy/frontend -- \
  sh -c 'timeout 3 nc -z postgres 5432; echo exit=$?'   # 📸 očekivano: blokirano
```

## Što još (opcionalno) podiže ocjenu
- **CI dokaz uživo:** povezati GHCR + GitHub Secrets (`KUBE_CONFIG`, `POSTGRES_PASSWORD`)
  i priložiti screenshot uspješnog `deploy` joba.
- **Demo gatea:** namjerno ubaciti ranjivu ovisnost i pokazati da Trivy ruši build.
- **Helm chart** (alternativa raw manifestima) — nije nužno, manifesti zadovoljavaju.
