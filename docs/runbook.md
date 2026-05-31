# Incident Runbook — Secure Event Ticketing Platform

Kratki operativni runbook za produkcijsko Kubernetes okruženje
(`namespace: secure-event-ticketing`). Svaki scenarij: **simptomi → dijagnostika
→ uzrok → korektivna mjera → validacija**.

Korisne skraćenice:

```bash
alias k='kubectl -n secure-event-ticketing'
k get pods -o wide
k get events --sort-by=.lastTimestamp | tail -30
```

---

## 1. Pad baze (PostgreSQL crash)

**Simptomi**
- `/readyz` na API-ju vraća `503 {"status":"not-ready"}`, `/healthz` i dalje `200`.
- Frontend kupnja prolazi (order ide u Redis), ali `/tickets/orders` vraća grešku
  i worker ne uspijeva upisivati narudžbe.
- `postgres` pod u `CrashLoopBackOff` / `Error` / restartani.

**Dijagnostika**
```bash
k get pod -l app=postgres
k describe pod -l app=postgres        # Events: OOMKilled? FailedMount? Probe fail?
k logs -l app=postgres --tail=100
k get pvc postgres-data               # je li PVC Bound?
```

**Mogući uzroci i mjere**
- **OOMKilled** (`Last State: Terminated, Reason: OOMKilled`): podigni
  `resources.limits.memory` u `10-postgres.yaml`, `k apply -f`. Provjeri da
  ResourceQuota ima prostora.
- **PVC nije Bound / izgubljen volume**: provjeri StorageClass i PV
  (`k get pv`). Bez ispravnog volumena baza ne može startati.
- **Korumpiran data dir / neuspješan initdb**: pogledaj logove; po potrebi
  restore iz backupa (vidi dolje).
- **Probe pretjerano agresivna**: ako se baza ubija prije nego digne, povećaj
  `livenessProbe.initialDelaySeconds` / `failureThreshold`.

**Restart / recovery**
```bash
k rollout restart deploy/postgres
k rollout status deploy/postgres
```

**Validacija**
```bash
k exec deploy/postgres -- sh -c 'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
k exec deploy/postgres -- sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT count(*) FROM ticket_orders;"'
curl -fsS http://ticketing.local/api/readyz
```
Narudžbe poslane tijekom ispada ostaju u Redis listi (`ticket_orders`) i worker
ih obradi čim baza ponovno proradi — provjeri `k exec deploy/redis -- redis-cli LLEN ticket_orders` koja pada prema 0.

> **Prevencija:** redovni `pg_dump` backup, monitoring memorije, PodDisruptionBudget,
> razmotri StatefulSet + replikaciju za HA.

---

## 2. Loš image tag (pogrešan / nepostojeći tag)

**Simptomi**
- Novi pod zapne u `ImagePullBackOff` / `ErrImagePull`.
- `kubectl rollout status` ne završava (visi).
- Stare replike i dalje rade (jer `maxUnavailable: 0`) → korisnici često ne osjete
  ispad, ali nova verzija se ne isporučuje.

**Dijagnostika**
```bash
k get pods -l app=api
k describe pod <api-pod>      # Events: "Failed to pull image ... not found / unauthorized"
k rollout status deploy/api --timeout=60s
```

**Uzrok**
- Typo u tagu, tag ne postoji u registryju, ili nedostaje pull secret /
  autorizacija za privatni registry.

**Korektivna mjera**
```bash
# A) najbrže: vrati na zadnju ispravnu reviziju
k rollout undo deploy/api
k rollout status deploy/api

# B) ili postavi ispravan, postojeći tag
k set image deploy/api api=ghcr.io/matej-basic/ticketing-api:1.0.0
k rollout status deploy/api

# ako je problem autorizacija na privatni registry:
k create secret docker-registry ghcr-creds \
  --docker-server=ghcr.io --docker-username=<user> --docker-password=<token>
# pa dodaj imagePullSecrets u deployment/serviceaccount i ponovno apply
```

**Validacija**
```bash
k get pods -l app=api          # svi Running/Ready
k get deploy api -o=jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
curl -fsS http://ticketing.local/api/healthz
```

> **Prevencija:** Trivy/registry provjera da tag postoji prije deploya,
> nepromjenjivi tagovi (ne `latest`), CI quality gate, `kubectl rollout status`
> u pipelineu kao automatski gate.

---

## 3. Neispravan secret (pogrešna lozinka baze)

**Simptomi**
- API pod se diže, ali `/readyz` stalno `503`; logovi: `password authentication
  failed for user "ticketing_user"`.
- Worker logira `Worker loop error: ... password authentication failed` u petlji.
- Readiness nikad ne postane `Ready` → Service ne šalje promet (kod API-ja),
  rolling update novih replika se ne dovršava.

**Dijagnostika**
```bash
k logs -l app=api --tail=50 | grep -i password
k get secret ticketing-db-credentials -o jsonpath='{.data.POSTGRES_USER}' | base64 -d; echo
# usporedi s onim što baza zapravo očekuje
k exec deploy/postgres -- sh -c 'echo user=$POSTGRES_USER'
```

**Uzrok**
- Vrijednost u Secretu ne odgovara lozinki/korisniku s kojim je baza
  inicijalizirana. **Važno:** PostgreSQL postavlja kredencijale samo pri *prvoj*
  inicijalizaciji PVC-a; naknadna promjena Secreta **ne** mijenja lozinku u već
  inicijaliziranoj bazi.

**Korektivna mjera**
```bash
# Slučaj A: Secret je krivo upisan, baza ima ispravnu lozinku
k create secret generic ticketing-db-credentials \
  --from-literal=POSTGRES_USER=ticketing_user \
  --from-literal=POSTGRES_PASSWORD='<ISPRAVNA_LOZINKA>' \
  --dry-run=client -o yaml | kubectl -n secure-event-ticketing apply -f -
k rollout restart deploy/api deploy/worker   # pokupi novi Secret (env se čita na startu)

# Slučaj B: ne znamo lozinku baze, ali smijemo je promijeniti
k exec -it deploy/postgres -- psql -U postgres -c \
  "ALTER USER ticketing_user WITH PASSWORD '<NOVA>';"
# zatim uskladi Secret (kao gore) i restart api/worker

# Slučaj C (lab/dev): potpuni reset baze ako su podaci potrošni
k delete pvc postgres-data && k rollout restart deploy/postgres
```

**Validacija**
```bash
k rollout status deploy/api
curl -fsS http://ticketing.local/api/readyz       # {"status":"ready"}
# end-to-end:
curl -fsS -X POST http://ticketing.local/api/tickets/purchase \
  -H 'Content-Type: application/json' \
  -d '{"eventId":"evt-1001","customerEmail":"ops@example.com","quantity":1}'
sleep 2
curl -fsS http://ticketing.local/api/tickets/orders
```

> **Prevencija:** Secret se kreira automatizirano (External Secrets / sealed
> secrets), rotacija lozinki koordinirana s `ALTER USER`, readiness probe
> (`/readyz`) hvata problem prije nego promet dođe do pokvarene replike.

---

## Opći troubleshooting tok

1. `k get pods` — koji pod nije `Running`/`Ready`?
2. `k describe pod <pod>` — sekcija **Events** (pull, probe, mount, OOM).
3. `k logs <pod> [--previous]` — aplikacijska greška.
4. `k get events --sort-by=.lastTimestamp` — kronologija.
5. Provjeri ovisnosti: NetworkPolicy, Secret/ConfigMap, ResourceQuota.
6. Korektivna mjera → `rollout status` → end-to-end validacija (`/readyz` + kupnja).
