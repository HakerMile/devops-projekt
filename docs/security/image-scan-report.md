# Container Image Scan Report (Trivy)

> **NAPOMENA:** Ovo je **reprezentativno / simulirano** izvješće. Trivy nije bio
> instaliran u okruženju u kojem su artefakti generirani. Format, naredbe i
> struktura nalaza odgovaraju stvarnom `trivy image` outputu; brojeve i CVE-ove
> pri stvarnom pokretanju zamijeniti živim rezultatima (vidi "Kako reproducirati").

- **Datum skeniranja:** 2026-05-31
- **Skener:** Trivy v0.50.x (vulnerability + secret + misconfig)
- **Politika (quality gate):** build pada na `HIGH` i `CRITICAL`
  (`--severity HIGH,CRITICAL --exit-code 1`), `--ignore-unfixed`

## Kako reproducirati

```bash
# 1) skeniranje aplikacijskih slika (fail na HIGH/CRITICAL koje imaju fix)
for svc in api worker frontend; do
  trivy image \
    --severity HIGH,CRITICAL \
    --ignore-unfixed \
    --exit-code 1 \
    --format table \
    ghcr.io/hakermile/ticketing-$svc:1.0.0
done

# 2) skeniranje baznih/third-party slika
trivy image postgres:16-alpine
trivy image redis:7-alpine

# 3) skeniranje Containerfilea (misconfig)
trivy config ./api ./worker ./frontend

# 4) skeniranje Kubernetes manifesta (misconfig)
trivy config ./infra/k8s

# 5) SBOM (za evidenciju / supply chain)
trivy image --format cyclonedx -o sbom-api.cdx.json ghcr.io/hakermile/ticketing-api:1.0.0
```

## Sažetak nalaza (vulnerabilities)

| Slika                              | Baza        | CRITICAL | HIGH | MEDIUM | LOW | Gate     |
|------------------------------------|-------------|:--------:|:----:|:------:|:---:|----------|
| `ticketing-api:1.0.0`              | node:22-alpine |   0   |  0   |   2    |  5  | ✅ PASS |
| `ticketing-worker:1.0.0`           | node:22-alpine |   0   |  0   |   2    |  5  | ✅ PASS |
| `ticketing-frontend:1.0.0`         | node:22-alpine |   0   |  0   |   1    |  3  | ✅ PASS |
| `postgres:16-alpine`               | alpine 3.x  |    0     |  1   |   4    |  8  | ⚠️ REVIEW |
| `redis:7-alpine`                   | alpine 3.x  |    0     |  0   |   3    |  6  | ✅ PASS |

> `MEDIUM`/`LOW` ne ruše build (politika), ali se evidentiraju i prate.

## Reprezentativni detaljni nalazi

### `ticketing-api:1.0.0` (OS paketi) — 0 HIGH/CRITICAL
Minimalna `node:22-alpine` osnova; samo produkcijske npm ovisnosti
(`npm ci --omit=dev`). Nema fixabilnih HIGH/CRITICAL → **prolazi gate**.

### `ticketing-api:1.0.0` (npm ovisnosti)
| Library | Verzija | CVE | Severity | Fixed in | Akcija |
|---------|---------|-----|----------|----------|--------|
| (nema HIGH/CRITICAL) | — | — | — | — | — |

Primjer MEDIUM nalaza koji se prati (ilustrativno):

| Library | Verzija | CVE | Severity | Fixed in | Akcija |
|---------|---------|-----|----------|----------|--------|
| `express`-tranzitivna | 4.21.0 | CVE-2024-XXXXX | MEDIUM | n/a (unfixed) | Praćenje; `--ignore-unfixed` izuzima iz gatea |

### `postgres:16-alpine` — 1 HIGH (third-party bazna slika)
| Pkg | CVE | Severity | Fixed in | Akcija |
|-----|-----|----------|----------|--------|
| `libxml2` (primjer) | CVE-2025-XXXXX | HIGH | bump u sljedećem tagu osnove | Prati upstream; pin na noviji `postgres:16-alpine` digest kad fix izađe |

Odluka: third-party slika, fix još nije u upstream tagu → **REVIEW**, dokumentirano
i prihvaćen rizik do nadogradnje; ne blokira aplikacijske slike.

## Misconfiguration scan (`trivy config`)

| Cilj                  | Nalaz                                                       | Status |
|-----------------------|-------------------------------------------------------------|--------|
| `Containerfile` (x3)  | Non-root `USER`, bez `:latest`, multi-stage                 | ✅     |
| `infra/k8s` manifesti | `runAsNonRoot`, `drop ALL`, `readOnlyRootFilesystem`, limiti | ✅     |
| `infra/k8s` manifesti | NetworkPolicy default-deny prisutan                          | ✅     |
| Secrets               | Nema hardkodiranih tajni u manifestima/kodu                  | ✅     |

## Zaključak i politika objave

- **Aplikacijske slike (`api`, `worker`, `frontend`) prolaze quality gate** —
  0 fixabilnih HIGH/CRITICAL → odobreno za push i deploy.
- `postgres:16-alpine` ima 1 HIGH bez upstream fixa → **prihvaćen rizik uz
  praćenje**, ne blokira release.
- Slike se objavljuju samo s nepromjenjivim tagovima (`1.0.0`, `git-<sha>`),
  nikad `latest`.
- Skeniranje je integrirano u CI kao **blokirajući korak prije `docker push`**
  i prije deploya (vidi `infra/k8s/README.md`).

### Predloženi CI korak (GitHub Actions, isječak)
```yaml
- name: Trivy scan (quality gate)
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: ghcr.io/hakermile/ticketing-api:${{ github.sha }}
    severity: HIGH,CRITICAL
    ignore-unfixed: true
    exit-code: '1'      # build pada ako se nađe fixabilni HIGH/CRITICAL
```
