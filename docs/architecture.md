# Arhitektura i projektne odluke

Dokument objašnjava **zašto kontejneri**, **koji servisi i njihove uloge**,
**kako međusobno komuniciraju** te **kako pristup podržava ciljeve projekta**.
Pokriva ishod učenja **I1** (i daje kontekst za I2/I4/I6).

## 1. Kontejneri vs. virtualne mašine (VM)

| Kriterij | Kontejneri (ovaj projekt) | Virtualne mašine |
|----------|---------------------------|------------------|
| Izolacija | Procesna (namespaces/cgroups), dijele kernel | Puna, vlastiti kernel/OS |
| Veličina artefakta | MB (npr. `node:22-alpine` ~150 MB) | GB (cijeli OS image) |
| Vrijeme pokretanja | sekunde | desetci sekundi do minute |
| Gustoća (density) | Visoka — više servisa po hostu | Niža — overhead OS-a po VM-u |
| Reproducibilnost | Visoka — slika + tag + lockfile | Niža — provisioning skripte/snapshotovi |
| Orkestracija | Standardna (Kubernetes/OpenShift) | Teža, manje granularna |
| Otisak za CI/CD | Mali, brz build/scan/push | Velik, sporiji |

**Zašto kontejneri za ovu aplikaciju:** pet malih, neovisnih servisa koji se
često mijenjaju i moraju biti identični lokalno i u produkciji. Kontejneri daju:
- **paritet okruženja** (isti artefakt lokalno → CI → Kubernetes),
- **brzu, reproducibilnu isporuku** (mali immutable image, multi-stage build),
- **prirodnu orkestraciju** (Deploymenti, probe, autoscaling, rolling update),
- **manju napadnu površinu** (minimalna slika, non-root, drop capabilities).

**Kada bi VM bila bolja:** potreba za punom kernel izolacijom (multi-tenant
povjerenje), legacy aplikacije koje traže cijeli OS, ili kernel moduli/specifični
drajveri. Za ovu mikroservisnu aplikaciju ti uvjeti ne vrijede → kontejneri su
opravdan izbor.

## 2. Servisi i njihove uloge

| Servis | Uloga | Tehnologija | Stanje | Mreža |
|--------|-------|-------------|--------|-------|
| `frontend` | Web UI (pregled evenata, kupnja) + `/config`, `/healthz` | Node.js/Express | stateless | web tier |
| `api` | REST: `/events`, `/tickets/purchase`, `/tickets/orders`, `/healthz`, `/readyz` | Node.js/Express | stateless | web+data |
| `worker` | Pozadinska obrada queue poruka → upis u bazu | Node.js | stateless | data tier |
| `postgres` | Trajna pohrana narudžbi | PostgreSQL 16 | **stateful** (PVC) | data tier |
| `redis` | Queue (i cache) za asinkronu obradu narudžbi | Redis 7 | ephemeral | data tier |

**Obrazloženje odabira:**
- **Razdvajanje web/api** — UI i poslovna logika skaliraju neovisno; API je
  jedini ulaz prema podatkovnom sloju.
- **Worker + Redis (asinkrono)** — kupnja se ne blokira na upis u bazu; API samo
  stavi narudžbu u queue (`202 Accepted`), worker je obrađuje. Otpornost na nalete
  prometa i privremene ispade baze (poruke čekaju u queueu).
- **PostgreSQL** — transakcijska, relacijska pohrana s ograničenjima (`CHECK`,
  `UNIQUE`) za integritet narudžbi.
- **Redis** — jednostavan, brz queue (`LPUSH`/`BRPOP`); ujedno može služiti kao cache.

## 3. Međuservisna komunikacija

```
   Browser
     │  HTTP :3000 (UI), HTTP :8080 (/api preko Ingressa, isti origin)
     ▼
  frontend ──(/config → apiBaseUrl)──►  api
                                         │  LPUSH (Redis :6379)
                                         ▼
                                       redis ──BRPOP──►  worker
                                         ▲                  │ INSERT
                                         │                  ▼
                                   api SELECT ◄──────────  postgres :5432
```

- **Sinkrono (HTTP/REST):** browser→frontend, browser→api, api↔(readyz provjere).
- **Asinkrono (queue):** api→redis→worker (razdvaja kupnju od perzistencije).
- **Baza:** api čita narudžbe (`SELECT`), worker piše (`INSERT ... ON CONFLICT`).
- **Portovi:** frontend 3000, api 8080, postgres 5432, redis 6379.
- **Konfiguracija veza:** kroz env varijable (`POSTGRES_HOST`, `REDIS_HOST`, …),
  identično lokalno (Compose service imena) i u Kubernetesu (Service imena).

### Granice povjerenja / segmentacija
- **Lokalno (Compose):** dvije mreže — `frontend` (frontend+api) i `backend`
  (api+worker+postgres+redis). Frontend nema rutu do baze/redisa.
- **Produkcija (Kubernetes):** `NetworkPolicy` default-deny + per-tier allow;
  baza i redis primaju promet **samo** od api/worker; worker nema ulazni promet.

## 4. Tok podataka — kupnja karte (end-to-end)

1. Korisnik u UI-u odabere event i pošalje kupnju.
2. `frontend` poziva `api POST /tickets/purchase`.
3. `api` validira ulaz, kreira narudžbu, `LPUSH` u Redis queue, vrati `202` + `orderId`.
4. `worker` `BRPOP`-a poruku, upiše narudžbu u PostgreSQL sa statusom `processed`.
5. `api GET /tickets/orders` čita obrađene narudžbe iz baze.

## 5. Usklađenost s ciljevima projekta

| Cilj projekta (DevSecOps) | Kako je adresiran |
|---------------------------|-------------------|
| Sigurna isporuka | Multi-stage, non-root, Trivy gate, PSA, RBAC, NetworkPolicy |
| Upravljanje slikama | Minimalne slike, immutable tagovi, skeniranje + evidencija |
| Orkestracija | Kubernetes manifesti: probe, resursi, Ingress, rolling update/rollback |
| Observability | `/healthz`, `/readyz`, liveness/readiness probe, strukturirani logovi |
| Troubleshooting | Runbook s realnim incidentnim scenarijima (`docs/runbook.md`) |
| Ubrzana isporuka | CI/CD: test → scan → build → push → deploy, reproducibilno |

## 6. Skalabilnost i otpornost
- `frontend` i `api` imaju **2 replike** + RollingUpdate (`maxUnavailable: 0`) → bez downtimea.
- `worker` se može horizontalno skalirati (više potrošača istog queuea).
- `redis` razdvaja proizvodnju i potrošnju → otpornost na nalete i kratke ispade baze.
- `postgres` je jedina stateful komponenta (PVC); za HA preporuka je StatefulSet
  + replikacija (dokumentirano u runbooku kao buduće poboljšanje).

Povezani dokumenti: [`README.md`](../README.md),
[`docs/devsecops.md`](devsecops.md), [`infra/k8s/README.md`](../infra/k8s/README.md).
