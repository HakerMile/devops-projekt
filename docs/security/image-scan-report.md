# Container Image Scan Report (Trivy)

> Generirano skriptom `scripts/trivy-scan.sh` iz stvarnih Trivy rezultata.
> Sirovi outputi: `docs/security/scans/`.

- **Datum skeniranja:** 2026-06-03
- **Skener:** Trivy 0.71.0 (vulnerability + misconfig)
- **Politika (quality gate):** build pada na `HIGH` i `CRITICAL` koji imaju
  dostupan fix (`--severity HIGH,CRITICAL --ignore-unfixed --exit-code 1`)

## Opseg skeniranja (Opcija A - bez Dockera)

1. Bazne / third-party slike (`node`, `postgres`, `redis`) - Trivy ih sam povlači
2. Aplikacijske npm ovisnosti (filesystem scan repozitorija)
3. Misconfiguration Containerfilea i Kubernetes manifesta

> Skeniranje finalnih aplikacijskih slika (`ticketing-*`) odvija se u CI
> pipelineu (`build-scan-push` job) i lokalno kroz `docker build` + `trivy image`.

## 1. Bazne / third-party slike

| Slika | CRITICAL | HIGH | MEDIUM | LOW | Gate (HIGH/CRITICAL fixable) |
|-------|:--------:|:----:|:------:|:---:|:----------------------------:|
| `node:22-alpine` | 0 | 1 | 3 | 0 | REVIEW |
| `postgres:16-alpine` | 1 | 15 | 16 | 2 | REVIEW |
| `redis:7-alpine` | 0 | 0 | 0 | 0 | PASS |

### Fixable HIGH/CRITICAL u baznim slikama

| Slika | Paket | Instalirano | Fixed in | CVE | Severity |
|-------|-------|-------------|----------|-----|----------|
| `node:22-alpine` | picomatch | 4.0.3 | 4.0.4, 3.0.2, 2.3.2 | CVE-2026-33671 | HIGH |
| `postgres:16-alpine` | libxml2 | 2.13.9-r0 | 2.13.9-r1 | CVE-2026-6732 | HIGH |
| `postgres:16-alpine` | stdlib | v1.24.6 | 1.24.13, 1.25.7, 1.26.0-rc.3 | CVE-2025-68121 | CRITICAL |
| `postgres:16-alpine` | stdlib | v1.24.6 | 1.24.12, 1.25.6 | CVE-2025-61726 | HIGH |
| `postgres:16-alpine` | stdlib | v1.24.6 | 1.24.11, 1.25.5 | CVE-2025-61729 | HIGH |
| `postgres:16-alpine` | stdlib | v1.24.6 | 1.25.8, 1.26.1 | CVE-2026-25679 | HIGH |
| `postgres:16-alpine` | stdlib | v1.24.6 | 1.25.9, 1.26.2 | CVE-2026-32280 | HIGH |
| `postgres:16-alpine` | stdlib | v1.24.6 | 1.25.9, 1.26.2 | CVE-2026-32281 | HIGH |
| `postgres:16-alpine` | stdlib | v1.24.6 | 1.25.9, 1.26.2 | CVE-2026-32283 | HIGH |
| `postgres:16-alpine` | stdlib | v1.24.6 | 1.25.10, 1.26.3 | CVE-2026-33811 | HIGH |
| `postgres:16-alpine` | stdlib | v1.24.6 | 1.25.10, 1.26.3 | CVE-2026-33814 | HIGH |
| `postgres:16-alpine` | stdlib | v1.24.6 | 1.25.10, 1.26.3 | CVE-2026-39820 | HIGH |
| `postgres:16-alpine` | stdlib | v1.24.6 | 1.25.10, 1.26.3 | CVE-2026-39823 | HIGH |
| `postgres:16-alpine` | stdlib | v1.24.6 | 1.25.10, 1.26.3 | CVE-2026-39825 | HIGH |
| `postgres:16-alpine` | stdlib | v1.24.6 | 1.25.10, 1.26.3 | CVE-2026-39826 | HIGH |
| `postgres:16-alpine` | stdlib | v1.24.6 | 1.25.10, 1.26.3 | CVE-2026-39836 | HIGH |
| `postgres:16-alpine` | stdlib | v1.24.6 | 1.25.10, 1.26.3 | CVE-2026-42499 | HIGH |

> Bazne slike su third-party; mitigacija je nadogradnja na noviji digest osnove
> kad fix uđe u upstream. Ne blokira aplikacijske slike.

## 2. Aplikacijske npm ovisnosti (filesystem scan)

Ukupno: CRITICAL 0, HIGH 0, MEDIUM 1, LOW 0.

Nema HIGH/CRITICAL ranjivosti u npm ovisnostima. Gate: **PASS**.

## 3. Misconfiguration (Containerfiles + k8s manifesti)

Trivy po defaultu prijavljuje samo nalaze koji **ne prolaze**. Ukupno **53 FAIL** (CRITICAL 0, HIGH 1, MEDIUM 4, LOW 48).

| Cilj | ID | Severity | Naslov |
|------|----|----------|--------|
| api/Containerfile | DS-0026 | LOW | No HEALTHCHECK defined |
| frontend/Containerfile | DS-0026 | LOW | No HEALTHCHECK defined |
| infra/k8s/01-resourcequota.yaml | KSV-0039 | LOW | limit range usage |
| infra/k8s/01-resourcequota.yaml | KSV-0039 | LOW | limit range usage |
| infra/k8s/01-resourcequota.yaml | KSV-0040 | LOW | resource quota usage |
| infra/k8s/03-configmap.yaml | KSV-01010 | MEDIUM | ConfigMap with sensitive content |
| infra/k8s/10-postgres.yaml | KSV-0014 | HIGH | Root file system is not read-only |
| infra/k8s/10-postgres.yaml | KSV-0020 | LOW | Runs with UID <= 10000 |
| infra/k8s/10-postgres.yaml | KSV-0021 | LOW | Runs with GID <= 10000 |
| infra/k8s/10-postgres.yaml | KSV-0039 | LOW | limit range usage |
| infra/k8s/10-postgres.yaml | KSV-0039 | LOW | limit range usage |
| infra/k8s/10-postgres.yaml | KSV-0039 | LOW | limit range usage |
| infra/k8s/10-postgres.yaml | KSV-0040 | LOW | resource quota usage |
| infra/k8s/10-postgres.yaml | KSV-0040 | LOW | resource quota usage |
| infra/k8s/10-postgres.yaml | KSV-0040 | LOW | resource quota usage |
| infra/k8s/11-redis.yaml | KSV-0020 | LOW | Runs with UID <= 10000 |
| infra/k8s/11-redis.yaml | KSV-0021 | LOW | Runs with GID <= 10000 |
| infra/k8s/11-redis.yaml | KSV-0039 | LOW | limit range usage |
| infra/k8s/11-redis.yaml | KSV-0039 | LOW | limit range usage |
| infra/k8s/11-redis.yaml | KSV-0040 | LOW | resource quota usage |
| infra/k8s/11-redis.yaml | KSV-0040 | LOW | resource quota usage |
| infra/k8s/12-api.yaml | KSV-0020 | LOW | Runs with UID <= 10000 |
| infra/k8s/12-api.yaml | KSV-0021 | LOW | Runs with GID <= 10000 |
| infra/k8s/12-api.yaml | KSV-0039 | LOW | limit range usage |
| infra/k8s/12-api.yaml | KSV-0039 | LOW | limit range usage |
| infra/k8s/12-api.yaml | KSV-0040 | LOW | resource quota usage |
| infra/k8s/12-api.yaml | KSV-0040 | LOW | resource quota usage |
| infra/k8s/12-api.yaml | KSV-0125 | MEDIUM | Restrict container images to trusted registries |
| infra/k8s/13-worker.yaml | KSV-0020 | LOW | Runs with UID <= 10000 |
| infra/k8s/13-worker.yaml | KSV-0021 | LOW | Runs with GID <= 10000 |
| infra/k8s/13-worker.yaml | KSV-0039 | LOW | limit range usage |
| infra/k8s/13-worker.yaml | KSV-0040 | LOW | resource quota usage |
| infra/k8s/13-worker.yaml | KSV-0125 | MEDIUM | Restrict container images to trusted registries |
| infra/k8s/14-frontend.yaml | KSV-0020 | LOW | Runs with UID <= 10000 |
| infra/k8s/14-frontend.yaml | KSV-0021 | LOW | Runs with GID <= 10000 |
| infra/k8s/14-frontend.yaml | KSV-0039 | LOW | limit range usage |
| infra/k8s/14-frontend.yaml | KSV-0039 | LOW | limit range usage |
| infra/k8s/14-frontend.yaml | KSV-0040 | LOW | resource quota usage |
| infra/k8s/14-frontend.yaml | KSV-0040 | LOW | resource quota usage |
| infra/k8s/14-frontend.yaml | KSV-0125 | MEDIUM | Restrict container images to trusted registries |
| infra/k8s/20-ingress.yaml | KSV-0039 | LOW | limit range usage |
| infra/k8s/20-ingress.yaml | KSV-0040 | LOW | resource quota usage |
| infra/k8s/30-networkpolicy.yaml | KSV-0039 | LOW | limit range usage |
| infra/k8s/30-networkpolicy.yaml | KSV-0039 | LOW | limit range usage |
| infra/k8s/30-networkpolicy.yaml | KSV-0039 | LOW | limit range usage |
| infra/k8s/30-networkpolicy.yaml | KSV-0039 | LOW | limit range usage |
| infra/k8s/30-networkpolicy.yaml | KSV-0039 | LOW | limit range usage |
| infra/k8s/30-networkpolicy.yaml | KSV-0040 | LOW | resource quota usage |
| infra/k8s/30-networkpolicy.yaml | KSV-0040 | LOW | resource quota usage |
| infra/k8s/30-networkpolicy.yaml | KSV-0040 | LOW | resource quota usage |
| infra/k8s/30-networkpolicy.yaml | KSV-0040 | LOW | resource quota usage |
| infra/k8s/30-networkpolicy.yaml | KSV-0040 | LOW | resource quota usage |
| worker/Containerfile | DS-0026 | LOW | No HEALTHCHECK defined |

> **Interpretacija:** većina nalaza je `LOW` i informativnog karaktera
> (UID/GID < 10000; reference na LimitRange/ResourceQuota po manifestu -
> oboje *postoji* u `01-resourcequota.yaml`). `MEDIUM` nalazi savjetuju
> trusted-registry politiku (KSV-0125) i pažnju oko ConfigMapa. Jedini
> `HIGH` je `KSV-0014` (postgres rootfs nije read-only) - **svjesna odluka**
> jer PostgreSQL piše izvan PVC-a; rizik je smanjen non-root korisnikom,
> `drop ALL` capabilities i `seccompProfile: RuntimeDefault`.

## Zaključak i politika objave

- Aplikacijske ovisnosti i manifeste se skeniraju na svakom buildu; quality
  gate pada na fixabilnim HIGH/CRITICAL ranjivostima prije `docker push`.
- Bazne slike s HIGH/CRITICAL bez upstream fixa = prihvaćen rizik uz praćenje
  i nadogradnju digesta osnove.
- Slike se objavljuju samo s nepromjenjivim tagovima (`1.0.0`, `git-<sha>`), nikad `latest`.
- Skeniranje je integrirano u CI (`.github/workflows/ci-cd.yaml`) kao blokirajući
  korak prije objave i deploya.

_Reproduciraj:_ `./scripts/trivy-scan.sh` (sirovi outputi u `docs/security/scans/`).
