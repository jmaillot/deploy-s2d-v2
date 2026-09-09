"use strict";
/* S2D capacity math — mirrors Get-S2DVolumeEfficiency /
   Get-S2DCapacityReserve / Get-S2DCapacityMedia from Deploy-S2D.
   Decimal TB throughout (1 TB = 1e12 bytes), like drive vendors. */

/* ---------- i18n ---------- */
const I18N = {
en: {
  title: "S2D Capacity Planner — 2-node Storage Spaces Direct",
  sub1: "How many disks of which type for the usable capacity you want — 2-node Storage Spaces Direct (Windows Server 2025). Same math as the",
  sub2: "module.",
  tabGet: "What do I get?",
  tabNeed: "What do I need?",
  cluster: "Cluster",
  nodes: "Nodes",
  resiliency: "Resiliency",
  resM: "Mirror — 50% usable, survives 1 failure",
  resNM: "Nested mirror — 25% usable, survives 2 failures",
  resNP: "Nested parity — ~35–40% usable, survives 2 failures",
  resMs: "Mirror — 50%",
  resNMs: "Nested mirror — 25%",
  resNPs: "Nested parity — ~35–40%",
  mirrorShare: "Mirror share for nested parity",
  reservePct: "Reserve %",
  volumes: "Volumes (usable split evenly)",
  drivesPerServer: "Drives per server",
  hintCache: "Fastest media present becomes cache automatically (zero usable capacity).",
  colType: "Type", colCount: "Count", colSize: "Size each",
  rowNvme: "NVMe (cache)",
  rowSsd: "SSD (cache or capacity)",
  rowSas: "SAS spinning (capacity)",
  presetLabel: "SSD layout preset",
  presetCustom: "Custom (manual drives)",
  presetSsdSas: "SSD + SAS (SSD caches SAS)",
  presetNvme: "NVMe + SSD + SAS (two tiers)",
  presetFlash: "All-flash SSD (no cache)",
  nvmeRow: "NVMe recommendation",
  nvmeActiveBoth: "Active — SSD and SAS volumes side by side.",
  nvmeActiveSas: "Active — NVMe caches SAS capacity.",
  nvmeActiveSsd: "Active — NVMe write cache for SSD capacity.",
  nvmeSkipFlash: "Skip — no NVMe needed (optional write-only cache for sustained heavy writes).",
  nvmeAddUnlock: "Add 2× NVMe/server (working-set sized) to unlock SSD volumes next to SAS — otherwise the SSD cache is enough.",
  calculate: "Calculate",
  result: "Result",
  usableTB: "usable (TB)", perVolTB: "per volume (TB)", efficiency: "efficiency",
  rawPool: "Raw pool", cacheRow: "Cache (not usable)", tiersRow: "Capacity tiers", reserveRow: "Reserve held back",
  cacheNote: "(serves hot data, not usable)",
  tiersCap: "{m} capacity",
  target: "Target",
  usableWanted: "Usable capacity wanted (TB)",
  capDrive: "Capacity drive",
  mediaSas: "SAS spinning",
  mediaSsd: "SSD (all-flash, or capacity under NVMe cache)",
  mediaNvme: "NVMe (all-flash)",
  driveSize: "Drive size",
  shoppingList: "Shopping list (per server)",
  yieldTB: "usable this gives (TB)",
  rawCluster: "Raw pool (cluster)",
  cacheToAdd: "Cache to add",
  resultDrives: "{media} drives",
  cacheSAS: "2× SSD ≥ {size}/server (~10% of SAS)",
  cacheSSD: "None if all-flash; 2× NVMe/server if SSD capacity under NVMe cache",
  cacheNVMe: "None if all-NVMe (optional write-only cache only for mixed endurance)",
  perfTitle: "Performance cheat sheet",
  perfNestedM: "Nested mirror (25%)", perfNestedP: "Nested parity (~35–40%)",
  perfRead: "Read latency", perfReadM: "Lowest", perfReadNM: "Lowest (any of 4 copies)", perfReadNP: "Fast recent, slower aged",
  perfWrite: "Sustained random writes", perfWriteM: "Highest", perfWriteNM: "Highest", perfWriteNP: "Lowest",
  perfAmp: "Backend writes / guest write", perfAmpNP: "~1.2–2× + CPU",
  perfSurvives: "Survives", perfSurvivesM: "1 failure", perfSurvivesN: "2 failures",
  perfBest: "Best for", perfBestM: "Hot SSD volumes", perfBestNM: "Max safety", perfBestNP: "Cold/bulk SAS volumes",
  takeaway1: "Size the parity mirror share to your biggest single burst (daily backup + margin), not the average — overflowing it drops throughput until destaging catches up.",
  takeaway2: "An SSD cache flatters SAS parity: random writes coalesce in SSD and destage sequentially. Mirror-on-SSD + parity-on-SAS is the sweet spot.",
  footer: "Math mirrors <code>Get-S2DVolumeEfficiency</code> / <code>Get-S2DCapacityReserve</code> (1 TB = 1000⁴ bytes, decimal like vendors). Verify with <code>-WhatIf</code> before deploying.",
  errNoCapacity: "No capacity drives: every server needs flash (SSD/NVMe) for cache plus capacity drives. SAS alone is not a valid S2D layout.",
  warnCapServer: "Only ~{n} capacity drives per server — Microsoft minimum is 4, and nested resiliency needs 4+.",
  warnCacheCount: "Only {n} cache drive(s) per server — use at least 2 for redundancy.",
  warnCacheSmall: "Cache ({cache}/server) is under ~10% of SAS capacity ({sas}/server) — hot working sets may spill to spinning disks.",
  warn400: "Over 400 TB per server — resync after reboot/update takes very long. Microsoft recommends staying near 400 TB/server.",
  warn64vol: "Per-volume size exceeds the 64 TB Microsoft recommendation (10 TB for VSS/Volsnap backups) — raise the volume count.",
  tipNested: "Tip: for production 2-node clusters Microsoft recommends nested resiliency (survives 2 failures instead of 1).",
  tipCacheAuto: "Hot data is served from the SSD read+write cache automatically — size it to the active working set.",
  warnVolsNodes: "Fewer volumes than nodes — use at least 1 volume per node so ownership distributes.",
  errTooBig: "Even 48 drives/server of this size cannot reach the target — use bigger drives or more nodes.",
  warnBelow4need: "Below 4 capacity drives per server — nested resiliency needs 4+.",
  warn64need: "Plan more than 1 volume: single volumes cap at 64 TB (10 TB for VSS/Volsnap backups).",
  tipVerify: "Verify on the other tab with these exact drive counts before buying."
},
fr: {
  title: "Planificateur de capacité S2D — Storage Spaces Direct à 2 nœuds",
  sub1: "Combien de disques de quel type pour la capacité utile voulue — Storage Spaces Direct à 2 nœuds (Windows Server 2025). Mêmes calculs que le",
  sub2: "module.",
  tabGet: "Qu'est-ce que j'obtiens ?",
  tabNeed: "De quoi ai-je besoin ?",
  cluster: "Cluster",
  nodes: "Nœuds",
  resiliency: "Résilience",
  resM: "Mirror — 50 % utiles, survit à 1 panne",
  resNM: "Miroir imbriqué — 25 % utiles, survit à 2 pannes",
  resNP: "Parité imbriquée — ~35–40 % utiles, survit à 2 pannes",
  resMs: "Mirror — 50 %",
  resNMs: "Miroir imbriqué — 25 %",
  resNPs: "Parité imbriquée — ~35–40 %",
  mirrorShare: "Part miroir pour la parité imbriquée",
  reservePct: "Réserve %",
  volumes: "Volumes (utile répartie)",
  drivesPerServer: "Disques par serveur",
  hintCache: "Le média le plus rapide devient automatiquement le cache (aucune capacité utile).",
  colType: "Type", colCount: "Nombre", colSize: "Taille unitaire",
  rowNvme: "NVMe (cache)",
  rowSsd: "SSD (cache ou capacité)",
  rowSas: "SAS rotatifs (capacité)",
  presetLabel: "Modèle SSD",
  presetCustom: "Personnalisé (disques manuels)",
  presetSsdSas: "SSD + SAS (SSD en cache du SAS)",
  presetNvme: "NVMe + SSD + SAS (deux tiers)",
  presetFlash: "Tout-flash SSD (sans cache)",
  nvmeRow: "Recommandation NVMe",
  nvmeActiveBoth: "Actif — volumes SSD et SAS côte à côte.",
  nvmeActiveSas: "Actif — le NVMe cache le SAS.",
  nvmeActiveSsd: "Actif — cache écriture NVMe pour le SSD.",
  nvmeSkipFlash: "Inutile — pas de NVMe (cache écriture seule en option pour écritures soutenues).",
  nvmeAddUnlock: "Ajoutez 2× NVMe/serveur (taille de l'ensemble de travail) pour des volumes SSD à côté du SAS — sinon le cache SSD suffit.",
  calculate: "Calculer",
  result: "Résultat",
  usableTB: "utiles (To)", perVolTB: "par volume (To)", efficiency: "rendement",
  rawPool: "Pool brut", cacheRow: "Cache (non utile)", tiersRow: "Tiers capacitatifs", reserveRow: "Réserve conservée",
  cacheNote: "(sert les données chaudes, non utile)",
  tiersCap: "{m} en capacité",
  target: "Objectif",
  usableWanted: "Capacité utile voulue (To)",
  capDrive: "Disque capacitif",
  mediaSas: "SAS rotatifs",
  mediaSsd: "SSD (tout-flash, ou capacité sous cache NVMe)",
  mediaNvme: "NVMe (tout-flash)",
  driveSize: "Taille disque",
  shoppingList: "Liste d'achats (par serveur)",
  yieldTB: "utile obtenue (To)",
  rawCluster: "Pool brut (cluster)",
  cacheToAdd: "Cache à ajouter",
  resultDrives: "disques {media}",
  cacheSAS: "2× SSD ≥ {size}/serveur (~10 % du SAS)",
  cacheSSD: "Rien si tout-flash ; 2× NVMe/serveur si SSD sous cache NVMe",
  cacheNVMe: "Rien si tout-NVMe (cache écriture seule en option selon endurance)",
  perfTitle: "Aide-mémoire performance",
  perfNestedM: "Miroir imbriqué (25 %)", perfNestedP: "Parité imbriquée (~35–40 %)",
  perfRead: "Latence lecture", perfReadM: "La plus basse", perfReadNM: "La plus basse (4 copies)", perfReadNP: "Rapide récent, plus lent vieilli",
  perfWrite: "Écritures aléatoires soutenues", perfWriteM: "Max", perfWriteNM: "Max", perfWriteNP: "Min",
  perfAmp: "Écritures backend / écriture", perfAmpNP: "~1,2–2× + CPU",
  perfSurvives: "Survit à", perfSurvivesM: "1 panne", perfSurvivesN: "2 pannes",
  perfBest: "Idéal pour", perfBestM: "Volumes SSD chauds", perfBestNM: "Sécurité max", perfBestNP: "Volumes SAS froids",
  takeaway1: "Dimensionnez la part miroir sur la plus grosse rafale unique (sauvegarde quotidienne + marge), pas sur la moyenne — la déborder effondre le débit jusqu'au rattrapage.",
  takeaway2: "Un cache SSD sublime la parité SAS : les écritures aléatoires fusionnent en SSD puis descendent en séquentiel. Mirror-sur-SSD + parité-sur-SAS est le point d'équilibre.",
  footer: "Calculs identiques à <code>Get-S2DVolumeEfficiency</code> / <code>Get-S2DCapacityReserve</code> (1 To = 1000⁴ octets, décimal comme les constructeurs). Vérifiez avec <code>-WhatIf</code> avant de déployer.",
  errNoCapacity: "Aucun disque capacitif : chaque serveur a besoin de flash (SSD/NVMe) pour le cache plus des disques capacitatifs. SAS seul n'est pas valide en S2D.",
  warnCapServer: "Seulement ~{n} disques capacitatifs par serveur — minimum Microsoft 4, et la résilience imbriquée exige 4+.",
  warnCacheCount: "Seulement {n} disque(s) cache par serveur — au moins 2 pour la redondance.",
  warnCacheSmall: "Cache ({cache}/serveur) sous ~10 % de la capacité SAS ({sas}/serveur) — les données chaudes peuvent déborder sur disques.",
  warn400: "Plus de 400 To par serveur — la resync après redémarrage/MAJ est très longue. Microsoft recommande ~400 To/serveur.",
  warn64vol: "Taille par volume au-delà des 64 To Microsoft (10 To pour sauvegardes VSS/Volsnap) — augmentez le nombre de volumes.",
  tipNested: "Astuce : en production à 2 nœuds, Microsoft recommande la résilience imbriquée (2 pannes au lieu d'1).",
  tipCacheAuto: "Les données chaudes sont servies depuis le cache SSD lecture/écriture automatiquement — dimensionnez-le pour l'ensemble de travail.",
  warnVolsNodes: "Moins de volumes que de nœuds — au moins 1 volume par nœud pour répartir la propriété.",
  errTooBig: "Même 48 disques/serveur de cette taille n'atteignent pas l'objectif — disques plus gros ou plus de nœuds.",
  warnBelow4need: "Moins de 4 disques capacitatifs par serveur — la résilience imbriquée exige 4+.",
  warn64need: "Prévoyez plus d'1 volume : plafond 64 To (10 To pour VSS/Volsnap).",
  tipVerify: "Vérifiez dans l'autre onglet avec ces nombres exacts avant d'acheter."
}
};

let LANG = "en";
try {
  LANG = localStorage.getItem("s2d-lang") ||
    ((navigator.language || "en").toLowerCase().startsWith("fr") ? "fr" : "en");
} catch (e) { LANG = "en"; }

function t(key, params) {
  let s = (I18N[LANG] && I18N[LANG][key]) || I18N.en[key] || key;
  for (const k in (params || {})) s = s.replace("{" + k + "}", params[k]);
  return s;
}

function unit() { return LANG === "fr" ? "To" : "TB"; }
function fmtNum(tb) {
  return (Math.round(tb * 100) / 100).toLocaleString(LANG === "fr" ? "fr-FR" : "en-US");
}
function fmt(tb) { return fmtNum(tb) + " " + unit(); }

function setLang(l) {
  LANG = l;
  try { localStorage.setItem("s2d-lang", l); } catch (e) {}
  applyLang();
}

function applyLang() {
  document.documentElement.lang = LANG;
  document.title = t("title");
  document.querySelectorAll("[data-i18n]").forEach((el) => { el.textContent = t(el.dataset.i18n); });
  document.querySelectorAll("[data-i18n-html]").forEach((el) => { el.innerHTML = t(el.dataset.i18nHtml); });
  document.getElementById("lang-en").classList.toggle("active", LANG === "en");
  document.getElementById("lang-fr").classList.toggle("active", LANG === "fr");
  updateNeedSizes();
  if (!document.getElementById("g-results").hidden) calcGet();
  if (!document.getElementById("n-results").hidden) calcNeed();
}

/* ---------- capacity math (mirrors Deploy-S2D helpers) ---------- */

/* Nested-parity lookup: capacity drives/server -> mirror% -> efficiency. */
const PARITY_TABLE = {
  4: { 10: 0.357, 20: 0.341, 30: 0.326 },
  5: { 10: 0.377, 20: 0.357, 30: 0.339 },
  6: { 10: 0.391, 20: 0.368, 30: 0.347 },
  7: { 10: 0.400, 20: 0.375, 30: 0.353 }
};

function efficiency(resiliency, drivesPerServer, mirrorPct) {
  if (resiliency === "Mirror") return 0.5;
  if (resiliency === "NestedMirror") return 0.25;
  const key = Math.min(7, Math.max(4, drivesPerServer));
  const row = PARITY_TABLE[key];
  if (mirrorPct <= 10) return row[10];
  if (mirrorPct >= 30) return row[30];
  if (mirrorPct <= 20) {
    const f = (mirrorPct - 10) / 10;
    return row[10] + f * (row[20] - row[10]);
  }
  const f = (mirrorPct - 20) / 10;
  return row[20] + f * (row[30] - row[20]);
}

/* drives: [{media:'NVMe'|'SSD'|'SAS', n, sizeTB}] (per-server counts).
   Returns capacity media list. Fastest present is cache. */
function capacityMedia(drives) {
  const has = (m) => drives.some((d) => d.media === m && d.n > 0 && d.sizeTB > 0);
  const hasNvme = has("NVMe"), hasSsd = has("SSD"), hasSas = has("SAS");
  if (hasSsd && hasSas) return hasNvme ? ["SSD", "SAS"] : ["SAS"];
  if (hasSas) return ["SAS"];
  if (hasSsd) return ["SSD"];
  if (hasNvme) return ["NVMe"];
  return [];
}

function largestOf(drives, media) {
  return Math.max(0, ...drives.filter((d) => d.media === media).map((d) => d.sizeTB));
}

/* Reserve in TB. rawTB = free pool TB. Mirrors Get-S2DCapacityReserve. */
function reserveTB(rawTB, nodeCount, reservePct, drives) {
  const slots = Math.min(nodeCount, 4);
  let floor = 0;
  const cap = capacityMedia(drives);
  const groups = cap.length ? cap : [...new Set(drives.map((d) => d.media))];
  for (const m of groups) floor += slots * largestOf(drives, m);
  const pct = rawTB * (reservePct / 100);
  return Math.min(rawTB, Math.max(floor, pct));
}

function showMode(mode) {
  document.getElementById("mode-get").hidden = mode !== "get";
  document.getElementById("mode-need").hidden = mode !== "need";
  document.getElementById("tab-get").setAttribute("aria-selected", mode === "get");
  document.getElementById("tab-need").setAttribute("aria-selected", mode === "need");
}

/* Mode-2 drive sizes per capacity media. */
const NEED_SIZES = {
  SAS: [2, 4, 8, 12, 16, 20],
  SSD: [0.8, 1.6, 1.92, 3.84, 7.68],
  NVMe: [0.8, 1.6, 3.2, 6.4]
};

function sizeLabel(s) {
  if (s >= 1) return String(s).replace(".", LANG === "fr" ? "," : ".") + " " + unit();
  return Math.round(s * 1000) + " GB";
}

function updateNeedSizes() {
  const media = document.getElementById("n-media").value;
  const sel = document.getElementById("n-size");
  const prev = parseFloat(sel.value);
  sel.innerHTML = "";
  for (const s of NEED_SIZES[media]) {
    const opt = document.createElement("option");
    opt.value = s;
    opt.textContent = sizeLabel(s);
    sel.appendChild(opt);
  }
  sel.value = NEED_SIZES[media].includes(prev) ? prev : NEED_SIZES[media][1];
}

/* SSD layout presets fill the drive rows; manual edits revert to Custom. */
function applyPreset() {
  const p = document.getElementById("g-preset").value;
  const set = (id, v) => { document.getElementById(id).value = v; };
  if (p === "ssd-sas") {
    set("g-nvme-n", 0); set("g-nvme-s", 0);
    set("g-ssd-n", 2); set("g-ssd-s", 0.8);
    set("g-sas-n", 4); set("g-sas-s", 4);
  } else if (p === "nvme") {
    set("g-nvme-n", 2); set("g-nvme-s", 1.6);
    set("g-ssd-n", 2); set("g-ssd-s", 1.92);
    set("g-sas-n", 4); set("g-sas-s", 4);
  } else if (p === "flash") {
    set("g-nvme-n", 0); set("g-nvme-s", 0);
    set("g-ssd-n", 4); set("g-ssd-s", 1.92);
    set("g-sas-n", 0); set("g-sas-s", 0);
  }
}

function presetCustom() {
  document.getElementById("g-preset").value = "custom";
}

/* NVMe add-or-skip verdict for the result table. */
function nvmeAdvice(drives, capMedia) {
  const nv = drives.find((d) => d.media === "NVMe");
  if (nv && nv.n > 0 && nv.sizeTB > 0) {
    if (capMedia.includes("SSD") && capMedia.includes("SAS")) return t("nvmeActiveBoth");
    if (capMedia.includes("SAS")) return t("nvmeActiveSas");
    return t("nvmeActiveSsd");
  }
  if (capMedia.includes("SSD") && !capMedia.includes("SAS")) return t("nvmeSkipFlash");
  if (capMedia.includes("SAS")) return t("nvmeAddUnlock");
  return null;
}

function num(id) {
  const v = parseFloat(document.getElementById(id).value);
  return Number.isFinite(v) ? v : 0;
}

function warnList(el, items) {
  const ul = document.getElementById(el);
  ul.innerHTML = "";
  for (const [cls, text] of items) {
    const li = document.createElement("li");
    li.className = cls;
    li.textContent = text;
    ul.appendChild(li);
  }
}

/* Shared health checks. Returns [errors, warnings] as [cls, text] items. */
function checkLayout(nodes, drives, capMedia, capPerServer, rawTB) {
  const items = [];
  const countOf = (m) => drives.filter((d) => d.media === m).reduce((a, d) => a + d.n, 0);
  const cacheCount = drives
    .filter((d) => !capMedia.includes(d.media))
    .reduce((a, d) => a + d.n, 0);

  if (capMedia.length === 0) {
    items.push(["error", t("errNoCapacity")]);
    return items;
  }
  if (capPerServer < 4) {
    items.push(["warn", t("warnCapServer", { n: capPerServer })]);
  }
  if (cacheCount > 0 && cacheCount < 2) {
    items.push(["warn", t("warnCacheCount", { n: cacheCount })]);
  }
  const sasTB = countOf("SAS") * largestOf(drives, "SAS");
  const cacheTB = drives
    .filter((d) => !capMedia.includes(d.media))
    .reduce((a, d) => a + d.n * d.sizeTB, 0);
  if (sasTB > 0 && cacheTB < 0.1 * sasTB) {
    items.push(["warn", t("warnCacheSmall", { cache: fmt(cacheTB), sas: fmt(sasTB) })]);
  }
  if (rawTB / nodes > 400) {
    items.push(["warn", t("warn400")]);
  }
  return items;
}

/* ================= MODE 1 ================= */
function calcGet() {
  const nodes = Math.max(2, Math.round(num("g-nodes")));
  const res = document.getElementById("g-res").value;
  const mirrorPct = num("g-mirrorpct");
  const reservePct = num("g-reservepct");
  const vols = Math.min(64, Math.max(1, Math.round(num("g-vols"))));
  const drives = [
    { media: "NVMe", n: Math.round(num("g-nvme-n")), sizeTB: num("g-nvme-s") },
    { media: "SSD", n: Math.round(num("g-ssd-n")), sizeTB: num("g-ssd-s") },
    { media: "SAS", n: Math.round(num("g-sas-n")), sizeTB: num("g-sas-s") }
  ];

  const capMedia = capacityMedia(drives);
  const capPerServer = drives.filter((d) => capMedia.includes(d.media)).reduce((a, d) => a + d.n, 0);
  const rawTB = drives.filter((d) => capMedia.includes(d.media)).reduce((a, d) => a + d.n * d.sizeTB, 0) * nodes;
  const cacheTB = drives.filter((d) => !capMedia.includes(d.media)).reduce((a, d) => a + d.n * d.sizeTB, 0) * nodes;

  const box = document.getElementById("g-results");
  const items = checkLayout(nodes, drives, capMedia, capPerServer, rawTB);
  if (capMedia.length === 0) {
    box.hidden = false;
    warnList("g-warnings", items);
    return;
  }

  const reserve = reserveTB(rawTB, nodes, reservePct, drives);
  const eff = efficiency(res, capPerServer, mirrorPct);
  const usable = Math.max(0, rawTB - reserve) * eff;

  document.getElementById("g-usable").textContent = fmtNum(usable);
  document.getElementById("g-pervol").textContent = fmtNum(usable / vols);
  document.getElementById("g-eff").textContent = (Math.round(eff * 1000) / 10) + "%";
  document.getElementById("g-raw").textContent = fmt(rawTB);
  document.getElementById("g-cache").textContent = fmt(cacheTB) + (cacheTB > 0 ? " " + t("cacheNote") : "");
  document.getElementById("g-tiers").textContent = t("tiersCap", { m: capMedia.join(" + ") });
  document.getElementById("g-nvme").textContent = nvmeAdvice(drives, capMedia) || "–";
  document.getElementById("g-reserve").textContent = fmt(reserve);

  if (usable / vols > 64) items.push(["warn", t("warn64vol")]);
  if (res === "Mirror") items.push(["ok", t("tipNested")]);
  if (capMedia.length === 1 && capMedia[0] === "SAS") {
    items.push(["ok", t("tipCacheAuto")]);
  }
  if (vols < nodes) items.push(["warn", t("warnVolsNodes")]);

  warnList("g-warnings", items);
  box.hidden = false;
}

/* ================= MODE 2 ================= */
function calcNeed() {
  const target = num("n-target");
  const nodes = Math.max(2, Math.round(num("n-nodes")));
  const res = document.getElementById("n-res").value;
  const media = document.getElementById("n-media").value;
  const size = num("n-size");
  const reservePct = num("n-reservepct");

  const box = document.getElementById("n-results");
  const items = [];
  let found = -1, foundUsable = 0, foundRaw = 0, foundReserve = 0;
  for (let n = 4; n <= 48; n++) {
    const raw = n * size * nodes;
    const drives = [{ media, n, sizeTB: size }];
    const reserve = reserveTB(raw, nodes, reservePct, drives);
    const usable = Math.max(0, raw - reserve) * efficiency(res, n, 20);
    if (usable >= target) {
      found = n; foundUsable = usable; foundRaw = raw; foundReserve = reserve;
      break;
    }
  }

  if (found < 0) {
    warnList("n-warnings", [["error", t("errTooBig")]]);
    box.hidden = false;
    return;
  }

  document.getElementById("n-count").textContent = found + "× " + sizeLabel(size);
  document.getElementById("n-count-label").textContent = t("resultDrives", { media });
  document.getElementById("n-yield").textContent = fmtNum(foundUsable);
  document.getElementById("n-raw").textContent = fmt(foundRaw);
  document.getElementById("n-reserve").textContent = fmt(foundReserve);

  if (media === "SAS") {
    const cacheEach = Math.max(0.8, Math.round((found * size * 0.1) * 10) / 10);
    document.getElementById("n-cache").textContent = t("cacheSAS", { size: String(cacheEach).replace(".", LANG === "fr" ? "," : ".") + " " + unit() });
  } else if (media === "SSD") {
    document.getElementById("n-cache").textContent = t("cacheSSD");
  } else {
    document.getElementById("n-cache").textContent = t("cacheNVMe");
  }
  if (found < 4) items.push(["warn", t("warnBelow4need")]);
  if (foundUsable > 64) items.push(["warn", t("warn64need")]);
  items.push(["ok", t("tipVerify")]);
  warnList("n-warnings", items);
  box.hidden = false;
}

document.addEventListener("DOMContentLoaded", () => { applyLang(); });
