# Secure Event Ticketing Platform (Sample DevSecOps Project)

Referentni uzorak aplikacije za kolegij **Uvod u DevOps - DevSecOps** (Algebra
Bernays). Pokriva cijeli tok: lokalni razvoj kroz Compose i produkcijski
deployment kroz Kubernetes manifeste.

### Dokumentacija
- [`docs/PREREQUISITES.md`](docs/PREREQUISITES.md) — instalacija okruženja (Docker, kubectl, kind, Trivy)
- [`docs/architecture.md`](docs/architecture.md) — arhitektura, kontejneri vs VM, servisi i komunikacija (I1)
- [`docs/devsecops.md`](docs/devsecops.md) — sigurnosne kontrole, alati, tajne, nalazi→mjere (I2/I4)
- [`infra/k8s/README.md`](infra/k8s/README.md) — produkcijski deployment (I6)
- [`docs/runbook.md`](docs/runbook.md) — incidentni runbook (I5)
- [`docs/security/image-scan-report.md`](docs/security/image-scan-report.md) — Trivy izvješće (I2)
- [`docs/SUBMISSION-CHECKLIST.md`](docs/SUBMISSION-CHECKLIST.md) — popis evidencije za predaju (I1–I6)

## Arhitektura

| Servis      | Uloga                                              | Tehnologija        |
|-------------|----------------------------------------------------|--------------------|
| `frontend`  | Web UI za pregled evenata i kupnju karata          | Node.js / Express  |
| `api`       | REST API za evente, narudžbe i health provjere     | Node.js / Express  |
| `worker`    | Pozadinska obrada queue poruka (narudžbe → baza)   | Node.js            |
| `postgres`  | Trajna pohrana narudžbi                            | PostgreSQL 16      |
| `redis`     | Queue / cache sloj                                 | Redis 7            |

### Tok podataka

```
            (browser :3000)
  frontend  ───────────────►  api ──push──►  redis ──pop──►  worker
                               │  /tickets/purchase            │
                               └──────────────────────────────┴──► postgres
                                  (api čita narudžbe)   (worker upisuje narudžbe)
```

### Mrežna segmentacija

Stack koristi dvije izolirane bridge mreže:

- **`frontend`** mreža: `frontend` + `api`
- **`backend`** mreža: `api` + `worker` + `postgres` + `redis`

`api` je jedini servis koji je član obje mreže i djeluje kao kontrolirani most
između web sloja i sloja podataka. **`frontend` nema rutu do `postgres` ni
`redis`.**

## Preduvjeti

- Docker Engine + Docker Compose v2 (`docker compose ...`)
  *ili* Podman + `podman compose`
- Slobodni portovi na hostu: `3000` (frontend) i `8080` (api)

## Sigurnosni elementi (kontejnerizacija, 1. dio)

- Multi-stage build (`Containerfile` po servisu) s minimalnom `node:22-alpine`
  runtime slikom
- Non-root runtime korisnik (`USER node`, uid 1000)
- U finalnoj slici samo produkcijske ovisnosti (`npm ci --omit=dev`)
- Health checkovi za svih 5 servisa
- Razdvojena konfiguracija kroz `.env` (lokalno) — bez hardkodiranih tajni u kodu
- Mrežna segmentacija (web tier ⟂ data tier)

---

## Pokretanje lokalnog okruženja

1. **Pripremi konfiguraciju** (jednom):

   ```bash
   cp .env.example .env
   ```

2. **Pokreni cijeli stack jednom naredbom:**

   ```bash
   docker compose up --build
   ```

   Dodaj `-d` za rad u pozadini (detached):

   ```bash
   docker compose up --build -d
   ```

3. **Provjeri status i health svih servisa:**

   ```bash
   docker compose ps
   ```

   Pričekaj da svi servisi budu `healthy`. Compose poštuje `depends_on` redoslijed:
   `postgres` i `redis` → `api` → `frontend` / `worker`.

### Hot-reload (brzi razvoj)

`frontend`, `api` i `worker` se grade iz `dev` stagea (uključuje `nodemon`), a
njihov `src/` direktorij je bind-mountan u kontejner. Promjene koda se primjenjuju
automatski bez ponovnog buildanja slike.

> Promjena ovisnosti u `package.json` i dalje zahtijeva rebuild:
> `docker compose up --build <servis>`.

---

## Gašenje lokalnog okruženja

- **Zaustavi i ukloni kontejnere + mreže (podaci u bazi ostaju sačuvani):**

  ```bash
  docker compose down
  ```

- **Ukloni i perzistentne podatke (resetiraj bazu):**

  ```bash
  docker compose down -v
  ```

- **Samo zaustavi bez uklanjanja (kasnije `docker compose start`):**

  ```bash
  docker compose stop
  ```

---

## Brza validacija funkcionalnosti

1. **Health / readiness API:**

   ```bash
   curl http://localhost:8080/healthz
   curl http://localhost:8080/readyz
   ```

2. **Dohvati evente:**

   ```bash
   curl http://localhost:8080/events
   ```

3. **Pošalji narudžbu** (API je stavlja u Redis queue, worker je upisuje u bazu):

   ```bash
   curl -X POST http://localhost:8080/tickets/purchase \
     -H "Content-Type: application/json" \
     -d '{"eventId":"evt-1001","customerEmail":"student@example.com","quantity":2}'
   ```

4. **Provjeri obrađene narudžbe** (dolaze iz PostgreSQL-a nakon obrade workera):

   ```bash
   curl http://localhost:8080/tickets/orders
   ```

5. **UI:** otvori <http://localhost:3000> i kupi kartu kroz formu.

---

## Korisne naredbe za troubleshooting

```bash
docker compose logs -f api          # prati logove jednog servisa
docker compose logs -f worker
docker compose exec postgres psql -U ticketing_user -d ticketing -c '\dt'
docker compose exec redis redis-cli LLEN ticket_orders
docker compose up --build api       # rebuild + restart samo jednog servisa
```

## Build produkcijske (minimalne) slike

Compose namjerno gradi `dev` stage radi hot-reloada. Minimalna non-root
produkcijska slika (zadani `runtime` target) gradi se ovako:

```bash
docker build -t ticketing-api:local -f ./api/Containerfile ./api
docker build -t ticketing-frontend:local -f ./frontend/Containerfile ./frontend
docker build -t ticketing-worker:local -f ./worker/Containerfile ./worker
```

Ove slike se kasnije skeniraju (Trivy) i deployaju na Kubernetes/OpenShift
u 2. dijelu projekta.

## Produkcija (2. dio projekta)

Kubernetes/OpenShift manifesti i upute za deployment nalaze se u
[`infra/k8s/`](infra/k8s/README.md). Pokrivaju sve servise + Secret/ConfigMap
odvojenu konfiguraciju, liveness/readiness/startup probe, resource
requests/limits + ResourceQuota, ServiceAccount + RBAC, NetworkPolicy
segmentaciju, Ingress i rolling update/rollback.

- Deployment upute: [`infra/k8s/README.md`](infra/k8s/README.md)
- Incidentni runbook: [`docs/runbook.md`](docs/runbook.md)
- Izvješće skeniranja slika (Trivy): [`docs/security/image-scan-report.md`](docs/security/image-scan-report.md)

## CI/CD pipeline

[`.github/workflows/ci-cd.yaml`](.github/workflows/ci-cd.yaml) automatizira cijeli
tok: **build → Trivy security gate → push u registry → deploy na Kubernetes**.

| Job | Što radi |
|-----|----------|
| `iac-scan` | Trivy `config` scan Containerfilea i k8s manifesta (misconfig gate) |
| `build-scan-push` | Po servisu (api/worker/frontend): build `runtime` slike → Trivy scan (HIGH/CRITICAL gate, SARIF u Security tab) → push na GHCR |
| `deploy` | Kreira DB Secret iz GH Secreta, `kubectl apply -k`, postavlja nove slike po SHA, čeka rollout (auto-rollback na grešci), smoke check `/readyz` |

Build + scan se izvršavaju na svakom push/PR; **push slika i deploy** samo na
`main` i `v*` tagovima. Slike se tagiraju nepromjenjivim commit SHA (+ semver na tagu).

**Potrebne GitHub postavke** (Settings → Secrets and variables):
- Secret `KUBE_CONFIG` — base64 kubeconfig ciljanog klastera
- Secret `POSTGRES_PASSWORD` — lozinka baze (pipeline kreira k8s Secret)
- (opc.) Variable `POSTGRES_USER` — default `ticketing_user`
- `GITHUB_TOKEN` se koristi automatski za push na GHCR
