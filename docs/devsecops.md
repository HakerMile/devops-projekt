# DevSecOps prakse, alati i sigurnosne kontrole

Objašnjava **kako je sigurnost ugrađena u cijeli lifecycle** (shift-left), koji
su alati korišteni i zašto, te kako se nalazi prate i rješavaju. Pokriva ishode
**I2** (sigurno upravljanje slikama) i **I4** (DevSecOps metodologija), uz osvrt
na **I3** (mjerljiva, ubrzana isporuka).

## 1. Pristup (shift-left)

Sigurnosne kontrole su pomaknute što ranije u tok isporuke:

```
kod → (test) → (IaC scan) → build → (image scan GATE) → push → deploy → (runtime guardrails)
       I3        I4           I2/I3     I2/I4 quality gate   I3      I6        I4/I6
```

Svaki korak ima automatiziranu provjeru koja može **zaustaviti** isporuku prije
nego problem dođe u produkciju.

## 2. Sigurnost pri izradi slika (I2)

| Praksa | Implementacija | Datoteka |
|--------|----------------|----------|
| Multi-stage build | `deps` → `dev` → `runtime` (samo runtime se objavljuje) | `*/Containerfile` |
| Minimalna bazna slika | `node:22-alpine` (mali otisak, manje CVE-ova) | `*/Containerfile` |
| Non-root korisnik | `USER node` (uid 1000) | `*/Containerfile` |
| Samo prod ovisnosti | `npm ci --omit=dev` u finalnoj slici | `*/Containerfile` |
| Bez tajni u slici | tajne kroz env/Secret, `.dockerignore` izuzima `.env` | `*/.dockerignore` |
| Reproducibilnost | `package-lock.json` + `npm ci` | `*/package-lock.json` |
| Runtime hardening | `runAsNonRoot`, `drop ALL`, `readOnlyRootFilesystem`, `seccomp` | `infra/k8s/*` |

### Tagging i politika objave slika
- **Immutable tagovi:** `git-<sha>` (svaki build) + `vX.Y.Z` (release). **Nikad `latest`** u produkciji.
- **Registry:** GHCR (`ghcr.io/hakermile/ticketing-<servis>`).
- **Pravilo objave:** slika se **pusha tek nakon prolaska Trivy gatea**; deploy
  uvijek cilja konkretan, skeniran SHA tag (omogućava pouzdan rollback).

## 3. Skeniranje ranjivosti i evidencija (I2/I4)

| Sloj | Naredba/alat | Kada |
|------|--------------|------|
| Bazne + app slike | `trivy image` | CI (`build-scan-push`) + lokalno (`scripts/trivy-scan.sh`) |
| Ovisnosti (npm) | `trivy fs` | lokalno; CI build |
| IaC misconfig | `trivy config` | CI (`iac-scan`) + lokalno |
| SARIF u GitHub Security | `upload-sarif` | CI |

- **Quality gate:** `--severity HIGH,CRITICAL --ignore-unfixed --exit-code 1` —
  build pada na fixabilnim HIGH/CRITICAL ranjivostima **prije** `docker push`.
- **Evidencija:** sirovi outputi u `docs/security/scans/`, sažetak u
  [`docs/security/image-scan-report.md`](security/image-scan-report.md),
  reproducibilno kroz `./scripts/trivy-scan.sh`.

### Nalazi i korektivne mjere (dosljednost)
| Nalaz | Severity | Odluka / mjera |
|-------|----------|----------------|
| App npm ovisnosti | 0 HIGH/CRITICAL | Gate **PASS** — nema akcije |
| `redis:7-alpine` | čisto | nema akcije |
| `node:22-alpine` (picomatch) | HIGH (fix dostupan) | Prati upstream; rebuild na noviji digest osnove |
| `postgres:16-alpine` (go stdlib/libxml2) | 1 CRITICAL + više HIGH | Third-party bazna slika; **prihvaćen rizik uz praćenje**, pin na noviji digest kad fix uđe upstream; ne blokira app slike |
| `KSV-0014` postgres rootfs nije read-only | HIGH | **Svjesna iznimka** — Postgres piše izvan PVC-a; rizik smanjen non-root + drop ALL + seccomp |
| `KSV-0125` trusted registries / UID<10000 (LOW/MED) | LOW/MED | Informativno; UID 1000/999 prihvaćeno, registry ograničen na GHCR |

## 4. Tajne i konfiguracija bez hardkodiranja (I4)

- **Lokalno:** `.env` (iz `.env.example`), izuzet `.gitignore`-om; bez stvarnih lozinki u repou.
- **Produkcija:** Kubernetes `Secret` (`ticketing-db-credentials`) kreiran
  **out-of-band** (`kubectl create secret` / CI iz GitHub Secreta); **nije** u Gitu
  ni u `kustomization.yaml`. Template `04-secret.example.yaml` sadrži samo placeholder.
- **Razdvajanje:** ne-tajna konfiguracija u `ConfigMap`, kredencijali u `Secret`.
- **CI:** `KUBE_CONFIG`, `POSTGRES_PASSWORD` kroz GitHub Secrets; `GITHUB_TOKEN`
  s minimalnim `packages: write` opsegom.

## 5. Sigurnosne kontrole u CI/CD i runtimeu (I4/I6)

| Kontrola | Gdje |
|----------|------|
| Automatizirani testovi (gate) | `test` job |
| E2E smoke test (workflow) | `smoke-test` job (Compose) |
| IaC misconfig scan | `iac-scan` job |
| Image scan quality gate + SARIF | `build-scan-push` job |
| Least-privilege CI token | `permissions:` po jobu |
| Pod Security Admission | namespace labele (`baseline`/`restricted`) |
| RBAC (dedicirani SA, bez token automounta) | `infra/k8s/02-rbac.yaml` |
| NetworkPolicy segmentacija | `infra/k8s/30-networkpolicy.yaml` |
| Rolling update + auto-rollback | `deploy` job + Deployment strategija |

## 6. Alati i obrazloženje

| Alat | Uloga | Zašto |
|------|-------|-------|
| **Docker/Podman + Compose** | Lokalni build i okruženje | Paritet s produkcijom, jedna naredba za cijeli stack |
| **Trivy** | Scan slika/ovisnosti/IaC | Jedan alat, brz, pokriva vuln+secret+misconfig; preporučen u zadatku |
| **GitHub Actions** | CI/CD orkestracija | Nativno uz repo, service containers za E2E, SARIF integracija |
| **Kubernetes** | Produkcijska orkestracija | Probe, resursi, rolling update, mrežne politike, RBAC |
| **Pod Security Admission** | Runtime baseline | Spriječava privilegirane/nesigurne podove bez dodatnih alata |

## 7. Mjerljiv napredak brzine isporuke (I3)

Predložene metrike (DORA-style) koje se mogu očitati iz pipelinea:

| Metrika | Kako izmjeriti | Cilj |
|---------|----------------|------|
| Lead time za promjenu | vrijeme od commita do `deploy` job završetka (Actions trajanje) | < 15 min |
| Deployment frequency | broj uspješnih `deploy` runova / tjedan | na svaki merge u `main` |
| Change failure rate | udio deploya koji izazovu rollback (`rollout undo`) | nizak |
| MTTR | vrijeme do oporavka (rollback/runbook) | minute |
| Trajanje builda | Actions duration `build-scan-push` (uz GHA cache) | minimizirati kroz cache |

Standardizacija (isti Containerfile, lockfile, kustomize) + automatizacija
(jedan workflow) čine isporuku **reproducibilnom i mjerljivom** umjesto ručne.

Povezani dokumenti: [`docs/architecture.md`](architecture.md),
[`docs/runbook.md`](runbook.md),
[`docs/security/image-scan-report.md`](security/image-scan-report.md).
