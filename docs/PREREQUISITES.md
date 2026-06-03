# Preduvjeti — instalacija okruženja (Windows + WSL2)

Popis alata i instalacijskih koraka za **potpuno testiranje** projekta (oba dijela)
na Windowsu kroz WSL2 (Ubuntu). Provjerene verzije s kojima je projekt
live-validiran (2026-06-03):

| Alat | Verzija | Uloga |
|------|---------|-------|
| WSL2 + Ubuntu | systemd aktivan | host za sve alate |
| Docker Engine | 29.5.3 | build slika + Compose + backend za kind |
| Docker Compose | v2 (plugin) | lokalni stack (1. dio) |
| kubectl | 1.36.x | upravljanje Kubernetesom (2. dio) |
| kind | 0.24.0 | lokalni Kubernetes klaster |
| Trivy | 0.71.0 | sigurnosno skeniranje |
| Node.js / npm | 22.x / 9.x | testovi, lokalni razvoj |
| git | 2.x | verzioniranje |

> **Docker vs Podman:** projekt je validiran s Dockerom (najglađe za Compose +
> kind). Podman je dopušten (Containerfile je Podman-native), ali `compose` i
> `kind` provideri traže dodatne prilagodbe.

## 1. WSL2 + Ubuntu

```powershell
# u PowerShellu (Windows)
wsl --install -d Ubuntu
```

Uključi systemd (potrebno da Docker daemon radi kao servis) — `/etc/wsl.conf`:

```ini
[boot]
systemd=true
```

Zatim `wsl --shutdown` (PowerShell) i ponovno otvori Ubuntu.

## 2. Docker Engine + Compose

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker "$USER"      # rad bez sudo
sudo systemctl enable --now docker
# primijeni grupu: zatvori WSL pa `wsl --terminate Ubuntu` (ili wsl --shutdown)
docker run --rm hello-world          # provjera (bez sudo)
docker compose version
```

## 3. kubectl

```bash
curl -sLO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install kubectl /usr/local/bin/ && rm kubectl
kubectl version --client
```

## 4. kind (lokalni Kubernetes)

```bash
curl -sLo kind https://kind.sigs.k8s.io/dl/v0.24.0/kind-linux-amd64
sudo install kind /usr/local/bin/ && rm kind
kind version
```

## 5. Trivy

```bash
mkdir -p ~/.local/bin
curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
  | sh -s -- -b ~/.local/bin
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc
trivy --version
```

## Važne napomene (naučeno pri validaciji)

- **Build slika:** datoteke se zovu `Containerfile` (ne `Dockerfile`), pa plain
  `docker build` treba `-f`:
  `docker build -t img -f ./api/Containerfile ./api`.
  (`docker compose` to ne treba — `dockerfile: Containerfile` je u `compose.yaml`.)
- **NetworkPolicy na kind-u:** zadani CNI (`kindnet`) **ne provodi** NetworkPolicy.
  Manifesti su ispravni; za stvarno provođenje koristi CNI s podrškom (npr. Calico:
  `kind create cluster --config` uz `disableDefaultCNI: true` + Calico).
- **Worker restarti pri startu:** worker se par puta restarta dok Postgres ne
  postane spreman (radi `SELECT 1` na startu), zatim se stabilizira — očekivano.

## Brza provjera da je sve spremno

```bash
docker run --rm hello-world && docker compose version && \
  kubectl version --client && kind version && trivy --version && node --version
```

Nakon ovoga slijedi validacija iz [`SUBMISSION-CHECKLIST.md`](SUBMISSION-CHECKLIST.md).
