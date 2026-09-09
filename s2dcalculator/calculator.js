"use strict";
/* S2D capacity math — mirrors Get-S2DVolumeEfficiency /
   Get-S2DCapacityReserve / Get-S2DCapacityMedia from Deploy-S2D.
   Decimal TB throughout (1 TB = 1e12 bytes), like drive vendors. */

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

function fmt(tb) {
  return (Math.round(tb * 100) / 100).toLocaleString("en-US") + " TB";
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
  SSD: [0.8, 1.6, 1.92, 3.84, 7.68]
};

function updateNeedSizes() {
  const media = document.getElementById("n-media").value;
  const sel = document.getElementById("n-size");
  const prev = parseFloat(sel.value);
  sel.innerHTML = "";
  for (const s of NEED_SIZES[media]) {
    const opt = document.createElement("option");
    opt.value = s;
    opt.textContent = s >= 1 ? s + " TB" : Math.round(s * 1000) + " GB";
    sel.appendChild(opt);
  }
  const keep = NEED_SIZES[media].includes(prev) ? prev : NEED_SIZES[media][1];
  sel.value = keep;
}

document.addEventListener("DOMContentLoaded", updateNeedSizes);

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
    items.push(["error", "No capacity drives: every server needs flash (SSD/NVMe) for cache plus capacity drives. SAS alone is not a valid S2D layout."]);
    return items;
  }
  if (capPerServer < 4) {
    items.push(["warn", "Only ~" + capPerServer + " capacity drives per server — Microsoft minimum is 4, and nested resiliency needs 4+."]);
  }
  if (cacheCount > 0 && cacheCount < 2) {
    items.push(["warn", "Only " + cacheCount + " cache drive(s) per server — use at least 2 for redundancy."]);
  }
  const sasTB = countOf("SAS") * largestOf(drives, "SAS");
  const cacheTB = drives
    .filter((d) => !capMedia.includes(d.media))
    .reduce((a, d) => a + d.n * d.sizeTB, 0);
  if (sasTB > 0 && cacheTB < 0.1 * sasTB) {
    items.push(["warn", "Cache (" + fmt(cacheTB) + "/server) is under ~10% of SAS capacity (" + fmt(sasTB) + "/server) — hot working sets may spill to spinning disks."]);
  }
  if (rawTB / nodes > 400) {
    items.push(["warn", "Over 400 TB per server — resync after reboot/update takes very long. Microsoft recommends staying near 400 TB/server."]);
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

  document.getElementById("g-usable").textContent = fmt(usable).replace(" TB", "");
  document.getElementById("g-pervol").textContent = fmt(usable / vols).replace(" TB", "");
  document.getElementById("g-eff").textContent = Math.round(eff * 1000) / 10 + "%";
  document.getElementById("g-raw").textContent = fmt(rawTB);
  document.getElementById("g-cache").textContent = fmt(cacheTB) + (cacheTB > 0 ? " (serves hot data, not usable)" : "");
  document.getElementById("g-tiers").textContent = capMedia.join(" + ") + " capacity";
  document.getElementById("g-reserve").textContent = fmt(reserve);

  if (usable / vols > 64) items.push(["warn", "Per-volume size exceeds the 64 TB Microsoft recommendation (10 TB for VSS/Volsnap backups) — raise the volume count."]);
  if (res === "Mirror") items.push(["ok", "Tip: for production 2-node clusters Microsoft recommends nested resiliency (survives 2 failures instead of 1)."]);
  if (capMedia.length === 1 && capMedia[0] === "SAS") {
    items.push(["ok", "Hot data is served from the SSD read+write cache automatically — size it to the active working set."]);
  }
  if (vols < nodes) items.push(["warn", "Fewer volumes than nodes — use at least 1 volume per node so ownership distributes."]);

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
    warnList("n-warnings", [["error", "Even 48 drives/server of this size cannot reach the target — use bigger drives or more nodes."]]);
    box.hidden = false;
    return;
  }

  document.getElementById("n-count").textContent = found + "× " + size + " TB";
  document.getElementById("n-count-label").textContent = media + " drives";
  document.getElementById("n-yield").textContent = fmt(foundUsable).replace(" TB", "");
  document.getElementById("n-raw").textContent = fmt(foundRaw);
  document.getElementById("n-reserve").textContent = fmt(foundReserve);

  if (media === "SAS") {
    const cacheEach = Math.max(0.8, Math.round((found * size * 0.1) * 10) / 10);
    document.getElementById("n-cache").textContent = "2× SSD ≥ " + cacheEach + " TB/server (~10% of SAS)";
    if (found < 4) items.push(["warn", "Below 4 capacity drives per server — nested resiliency needs 4+."]);
  } else {
    document.getElementById("n-cache").textContent = "None if all-flash; 2× NVMe/server if SSD capacity under NVMe cache";
  }
  if (foundUsable > 64) items.push(["warn", "Plan more than 1 volume: single volumes cap at 64 TB (10 TB for VSS/Volsnap backups)."]);
  items.push(["ok", "Verify on the other tab with these exact drive counts before buying."]);
  warnList("n-warnings", items);
  box.hidden = false;
}
