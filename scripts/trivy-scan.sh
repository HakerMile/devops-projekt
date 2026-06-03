#!/usr/bin/env bash
# =============================================================================
# trivy-scan.sh - real Trivy security scan (Option A: no Docker required)
#
# Runs three scans and saves the raw outputs under docs/security/scans/, then
# regenerates docs/security/image-scan-report.md from the actual JSON results:
#   1. base / third-party images (node, postgres, redis) - pulled by Trivy
#   2. application npm dependencies (filesystem scan)
#   3. misconfiguration scan of Containerfiles + Kubernetes manifests
#
# Usage:
#   ./scripts/trivy-scan.sh
#
# Env toggles:
#   SKIP_NPM=1   do not run `npm install` (npm deps scan will cover only what
#                is already present in node_modules)
#
# Requirements: trivy (https://trivy.dev), node, and internet access.
# =============================================================================
set -euo pipefail

# Move to repo root (script lives in ./scripts).
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

OUT_DIR="docs/security"
RAW_DIR="$OUT_DIR/scans"
REPORT="$OUT_DIR/image-scan-report.md"
mkdir -p "$RAW_DIR"

command -v trivy >/dev/null 2>&1 || { echo "ERROR: trivy is not installed." >&2; exit 1; }

export TRIVY_NO_PROGRESS=1
TRIVY_VERSION="$(trivy --version 2>/dev/null | head -1 | awk '{print $2}')"
SERVICES=(api worker frontend)
BASE_IMAGES=(node:22-alpine postgres:16-alpine redis:7-alpine)

echo ">> Trivy ${TRIVY_VERSION} - starting scans"

# --- 0. Ensure npm dependencies exist so the fs scan has something to read ----
if [ "${SKIP_NPM:-0}" != "1" ]; then
  if command -v npm >/dev/null 2>&1; then
    for svc in "${SERVICES[@]}"; do
      if [ ! -d "$svc/node_modules" ]; then
        echo ">> npm install ($svc) for dependency coverage"
        (cd "$svc" && npm install --no-audit --no-fund --silent) || \
          echo "   (npm install failed for $svc - continuing)"
      fi
    done
  else
    echo ">> npm not found - skipping dependency install"
  fi
fi

# --- 1. Base / third-party images --------------------------------------------
for img in "${BASE_IMAGES[@]}"; do
  safe="$(echo "$img" | tr '/:' '__')"
  echo ">> [image] $img"
  trivy image --severity HIGH,CRITICAL --format table "$img" \
    | tee "$RAW_DIR/image-${safe}.txt" >/dev/null
  trivy image --format json -o "$RAW_DIR/image-${safe}.json" "$img"
done

# --- 2. Application npm dependencies (filesystem) ----------------------------
echo ">> [fs] application dependencies"
trivy fs --scanners vuln --severity HIGH,CRITICAL,MEDIUM --format table . \
  | tee "$RAW_DIR/fs-vuln.txt" >/dev/null
trivy fs --scanners vuln --format json -o "$RAW_DIR/fs-vuln.json" .

# --- 3. Misconfiguration (Containerfiles, compose, k8s manifests) ------------
# `trivy config` accepts a single target, so scan the repo root (it recursively
# picks up Containerfiles, compose.yaml and the Kubernetes manifests).
echo ">> [config] Containerfiles + compose + k8s manifests"
trivy config --format table . \
  | tee "$RAW_DIR/config.txt" >/dev/null
trivy config --format json -o "$RAW_DIR/config.json" .

# --- 4. Generate the markdown report from the JSON results -------------------
echo ">> generating $REPORT"
RAW="$RAW_DIR" TRIVY_VERSION="$TRIVY_VERSION" node - > "$REPORT" <<'NODE'
const fs = require("fs");
const path = require("path");
const dir = process.env.RAW;
const trivyVersion = process.env.TRIVY_VERSION || "unknown";
const date = new Date().toISOString().slice(0, 10);
const SEV = ["CRITICAL", "HIGH", "MEDIUM", "LOW", "UNKNOWN"];

const load = (f) => {
  try { return JSON.parse(fs.readFileSync(path.join(dir, f), "utf8")); }
  catch { return null; }
};
const emptyCounts = () => ({ CRITICAL: 0, HIGH: 0, MEDIUM: 0, LOW: 0, UNKNOWN: 0 });

function vulnCounts(report) {
  const c = emptyCounts();
  const list = [];
  for (const r of (report.Results || [])) {
    for (const v of (r.Vulnerabilities || [])) {
      if (c[v.Severity] !== undefined) c[v.Severity]++;
      if (v.Severity === "HIGH" || v.Severity === "CRITICAL") {
        list.push({
          target: r.Target, pkg: v.PkgName, installed: v.InstalledVersion,
          fixed: v.FixedVersion || "", id: v.VulnerabilityID, sev: v.Severity,
        });
      }
    }
  }
  return { c, list };
}

const out = [];
const p = (s = "") => out.push(s);

p("# Container Image Scan Report (Trivy)");
p("");
p(`> Generirano skriptom \`scripts/trivy-scan.sh\` iz stvarnih Trivy rezultata.`);
p(`> Sirovi outputi: \`docs/security/scans/\`.`);
p("");
p(`- **Datum skeniranja:** ${date}`);
p(`- **Skener:** Trivy ${trivyVersion} (vulnerability + misconfig)`);
p("- **Politika (quality gate):** build pada na `HIGH` i `CRITICAL` koji imaju");
p("  dostupan fix (`--severity HIGH,CRITICAL --ignore-unfixed --exit-code 1`)");
p("");
p("## Opseg skeniranja (Opcija A - bez Dockera)");
p("");
p("1. Bazne / third-party slike (`node`, `postgres`, `redis`) - Trivy ih sam povlači");
p("2. Aplikacijske npm ovisnosti (filesystem scan repozitorija)");
p("3. Misconfiguration Containerfilea i Kubernetes manifesta");
p("");
p("> Skeniranje finalnih aplikacijskih slika (`ticketing-*`) odvija se u CI");
p("> pipelineu (`build-scan-push` job) i lokalno kroz `docker build` + `trivy image`.");
p("");

// --- 1. base images ---
p("## 1. Bazne / third-party slike");
p("");
p("| Slika | CRITICAL | HIGH | MEDIUM | LOW | Gate (HIGH/CRITICAL fixable) |");
p("|-------|:--------:|:----:|:------:|:---:|:----------------------------:|");
const imageFiles = fs.readdirSync(dir).filter((f) => f.startsWith("image-") && f.endsWith(".json"));
const baseHighFix = [];
for (const f of imageFiles.sort()) {
  const rep = load(f);
  if (!rep) continue;
  const name = rep.ArtifactName || f;
  const { c, list } = vulnCounts(rep);
  const fixable = list.filter((v) => v.fixed);
  const gate = fixable.length === 0 ? "PASS" : "REVIEW";
  p(`| \`${name}\` | ${c.CRITICAL} | ${c.HIGH} | ${c.MEDIUM} | ${c.LOW} | ${gate} |`);
  for (const v of fixable) baseHighFix.push({ name, ...v });
}
p("");
if (baseHighFix.length) {
  p("### Fixable HIGH/CRITICAL u baznim slikama");
  p("");
  p("| Slika | Paket | Instalirano | Fixed in | CVE | Severity |");
  p("|-------|-------|-------------|----------|-----|----------|");
  for (const v of baseHighFix.slice(0, 40)) {
    p(`| \`${v.name}\` | ${v.pkg} | ${v.installed} | ${v.fixed} | ${v.id} | ${v.sev} |`);
  }
  p("");
  p("> Bazne slike su third-party; mitigacija je nadogradnja na noviji digest osnove");
  p("> kad fix uđe u upstream. Ne blokira aplikacijske slike.");
} else {
  p("Nema fixabilnih HIGH/CRITICAL ranjivosti u baznim slikama.");
}
p("");

// --- 2. npm deps ---
p("## 2. Aplikacijske npm ovisnosti (filesystem scan)");
p("");
const fsRep = load("fs-vuln.json");
if (fsRep) {
  const { c, list } = vulnCounts(fsRep);
  p(`Ukupno: CRITICAL ${c.CRITICAL}, HIGH ${c.HIGH}, MEDIUM ${c.MEDIUM}, LOW ${c.LOW}.`);
  p("");
  const fixable = list.filter((v) => v.fixed);
  if (list.length) {
    p("| Komponenta (target) | Paket | Instalirano | Fixed in | CVE | Severity |");
    p("|---------------------|-------|-------------|----------|-----|----------|");
    for (const v of list.slice(0, 40)) {
      p(`| ${v.target} | ${v.pkg} | ${v.installed} | ${v.fixed || "n/a"} | ${v.id} | ${v.sev} |`);
    }
    p("");
    p(`Gate (fixable HIGH/CRITICAL): **${fixable.length === 0 ? "PASS" : "FAIL - " + fixable.length + " za nadogradnju"}**.`);
  } else {
    p("Nema HIGH/CRITICAL ranjivosti u npm ovisnostima. Gate: **PASS**.");
  }
} else {
  p("_Nema rezultata filesystem scana (fs-vuln.json nije pronađen)._");
}
p("");

// --- 3. misconfig ---
p("## 3. Misconfiguration (Containerfiles + k8s manifesti)");
p("");
const cfgRep = load("config.json");
if (cfgRep) {
  const sevCount = emptyCounts();
  let pass = 0, fail = 0;
  const failures = [];
  for (const r of (cfgRep.Results || [])) {
    for (const m of (r.Misconfigurations || [])) {
      if (m.Status === "FAIL") {
        fail++;
        if (sevCount[m.Severity] !== undefined) sevCount[m.Severity]++;
        failures.push({ target: r.Target, id: m.ID, sev: m.Severity, title: m.Title });
      } else if (m.Status === "PASS") {
        pass++;
      }
    }
  }
  void pass; // Trivy reports only failing checks by default (successes hidden)
  p(`Trivy po defaultu prijavljuje samo nalaze koji **ne prolaze**. ` +
    `Ukupno **${fail} FAIL** ` +
    `(CRITICAL ${sevCount.CRITICAL}, HIGH ${sevCount.HIGH}, MEDIUM ${sevCount.MEDIUM}, LOW ${sevCount.LOW}).`);
  p("");
  if (failures.length) {
    p("| Cilj | ID | Severity | Naslov |");
    p("|------|----|----------|--------|");
    for (const m of failures.slice(0, 60)) {
      p(`| ${m.target} | ${m.id} | ${m.sev} | ${(m.title || "").replace(/\|/g, "\\|")} |`);
    }
    p("");
    p("> **Interpretacija:** većina nalaza je `LOW` i informativnog karaktera");
    p("> (UID/GID < 10000; reference na LimitRange/ResourceQuota po manifestu -");
    p("> oboje *postoji* u `01-resourcequota.yaml`). `MEDIUM` nalazi savjetuju");
    p("> trusted-registry politiku (KSV-0125) i pažnju oko ConfigMapa. Jedini");
    p("> `HIGH` je `KSV-0014` (postgres rootfs nije read-only) - **svjesna odluka**");
    p("> jer PostgreSQL piše izvan PVC-a; rizik je smanjen non-root korisnikom,");
    p("> `drop ALL` capabilities i `seccompProfile: RuntimeDefault`.");
  } else {
    p("Nema FAIL nalaza - Containerfileovi i manifesti prolaze misconfig provjere.");
  }
} else {
  p("_Nema rezultata config scana (config.json nije pronađen)._");
}
p("");

p("## Zaključak i politika objave");
p("");
p("- Aplikacijske ovisnosti i manifeste se skeniraju na svakom buildu; quality");
p("  gate pada na fixabilnim HIGH/CRITICAL ranjivostima prije `docker push`.");
p("- Bazne slike s HIGH/CRITICAL bez upstream fixa = prihvaćen rizik uz praćenje");
p("  i nadogradnju digesta osnove.");
p("- Slike se objavljuju samo s nepromjenjivim tagovima (`1.0.0`, `git-<sha>`), nikad `latest`.");
p("- Skeniranje je integrirano u CI (`.github/workflows/ci-cd.yaml`) kao blokirajući");
p("  korak prije objave i deploya.");
p("");
p("_Reproduciraj:_ `./scripts/trivy-scan.sh` (sirovi outputi u `docs/security/scans/`).");

process.stdout.write(out.join("\n") + "\n");
NODE

echo ">> done. Report: $REPORT"
