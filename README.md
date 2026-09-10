# S2DCluster — Usage Guide

> Version française : [README_FR.md](README_FR.md).

Deploys a 2-node Storage Spaces Direct (S2D) cluster on Windows Server 2025:
per-node network/storage prep, then one-shot cluster creation with quorum,
S2D enablement, and CSV volume(s) with selectable resiliency
(Mirror/NestedMirror/NestedParity). PowerShell 5.1, FR/EN locales.

## 0. Prerequisites checklist

- [ ] 2x Windows Server 2025 (Datacenter), Failover-Clustering + Hyper-V roles
- [ ] **10 GbE or faster RDMA-capable adapters on the storage fabric** — preflight
  throws on anything slower. Below 10 GbE, resync/repair traffic saturates the link.
- [ ] PERC/HBA in **pass-through (HBA) mode, not RAID** — preflight throws when no
  poolable disks are visible. At least some SSD/NVMe for the cache tier (all-HDD warns).
- [ ] NIC firmware/drivers current (preflight prints a driver table — check it
  against your vendor matrix), BIOS virtualization on for SR-IOV
- [ ] 1x witness: file share (`\\server\share$`) or Azure Cloud Witness (account + key)
- [ ] 1x static cluster IP; per-node static storage IPs on **different subnets**
- [ ] Elevated shell on the nodes themselves — never run NodePrep from a
  workstation (it renames the *local* NICs)

Fill this plan before starting (example values):

| Role | HV1 | HV2 |
|---|---|---|
| Mgmt NICs | Mgmt01, Mgmt02 | Mgmt01, Mgmt02 |
| VM NICs | Vm01, Vm02 | Vm01, Vm02 |
| StorageA NIC / IP | Storage01 / 192.168.200.1 | Storage01 / 192.168.200.2 |
| StorageB NIC / IP | Storage02 / 192.168.201.1 | Storage02 / 192.168.201.2 |
| LiveMig NIC (+opt IP) | Live01 | Live01 |
| Cluster | ClusterPDL / 192.168.1.240, witness `\\NTSVR22\ClusterPDL$` | |

## 1. Prepare each node (run locally, elevated, on HV1 then HV2)

Copy the repo folder to the node first — the picker lists *local* adapters.

```powershell
Import-Module .\Deploy-S2D\Deploy-S2D.psm1
Start-S2DNodePrep -MgmtAdapters "Mgmt01","Mgmt02" -VMAdapters "Vm01","Vm02" -StorageA "Storage01" -StorageB "Storage02" -LiveMigrationAdapter "Live01" -StorageAIP "192.168.200.1" -StorageBIP "192.168.201.1"
```

Omit any NIC name to pick it from a numbered console menu instead — each menu
states the role your pick **will be renamed to** (`1/5` StorageA … `5/5` VM).
MGMT/VM take comma lists (`0,2`); blank finishes; `Q` aborts. Already-picked
NICs disappear from later menus; one NIC can't serve two roles.

What runs, in order: preflight (reads only — ≥4 NICs, 10 Gbps + proven RDMA,
poolable disks) → renames (verified after the fact) → jumbo MTU + static IPs →
QoS/DCB + RDMA → vSwitch (SET team for 2+ VM NICs, plain for 1) → VMQ/RSS/RSC on + Jumbo off (VM), VMQ/RSC/EEE off + RSS on (storage), VMQ/EEE off (Mgmt) →
live-migration binding (only with `-LiveMigrationIP`, else a warning).

| Parameter | Required | Notes |
|---|---|---|
| `MgmtAdapters`, `VMAdapters` | picker if omitted | Any count (1+) |
| `StorageA/B`, `LiveMigrationAdapter` | picker if omitted | Exactly **2 storage** (the two fabrics), exactly **1 LiveMig** — by design |
| `StorageAIP/BIP` | yes | Must parse, must differ, must sit on **different subnets** |
| `StoragePrefix` | no | Default `24` (range 1–31) |
| `LiveMigrationIP/Prefix` | no | Binds *the* migration network (`Add-VMMigrationNetwork`); omitted = warning |
| `LogPath` | no | Default `C:\S2D_Deployment.log` |

Examples — same step, three levels of explicitness:

```powershell
# A. Minimal: pick every NIC from the numbered console menu.
#    Only the two storage IPs are mandatory (no picker can guess them).
Start-S2DNodePrep -StorageAIP "192.168.200.1" -StorageBIP "192.168.201.1"

# B. Full: everything named, no prompts. Run per node with its own IPs.
Start-S2DNodePrep -MgmtAdapters "Mgmt01","Mgmt02" -VMAdapters "Vm01","Vm02" -StorageA "Storage01" -StorageB "Storage02" -LiveMigrationAdapter "Live01" -StorageAIP "192.168.200.1" -StorageBIP "192.168.201.1" -LiveMigrationIP "192.168.210.1"

# C. Dry run (any variant + -WhatIf): preflight executes, nothing changes.
Start-S2DNodePrep -StorageAIP "192.168.200.1" -StorageBIP "192.168.201.1" -WhatIf
```

Always dry-run first: append `-WhatIf` (preflight still executes — that's the point).

## 2. Create the cluster (once, from either node)

Plan disks first with the hosted calculator (same math as the module):
https://jmaillot.github.io/deploy-s2d-v2/
It works both directions (disks → usable, usable → per-server shopping
list for SAS/SSD/NVMe), flags undersized cache with the minimum to add,
gives an NVMe add-or-skip verdict, and exports the matching
`New-S2DCluster` command to copy-paste. French toggle included.

```powershell
New-S2DCluster -ClusterName "ClusterPDL" -ClusterNodes "HV1","HV2" -ClusterIP "192.168.1.240" -WitnessType "FileShare" -FileShareWitness "\\NTSVR22\ClusterPDL$" -VolumeName "CSV_S2D" -SizingMode "Auto"
```

Validates (`Test-Cluster`), creates the cluster, sets quorum, enables S2D,
creates the CSV volume(s) (ReFS) with the selected resiliency, constrains
SMB Multichannel to StorageA/B, renames cluster networks. Cloud witness instead:

```powershell
$key = Read-Host -AsSecureString
New-S2DCluster -ClusterName "ClusterPDL" -ClusterNodes "HV1","HV2" -ClusterIP "192.168.1.240" -WitnessType "Cloud" -AzStorageAccount "acc" -AzStorageKey $key -SizingMode "Auto"
```

The key is `SecureString` end to end — decrypted only for the quorum call,
cleared after, never logged.

### Storage: resiliency, volumes, and sizing

| `-Resiliency` | Usable (share of raw pool) | Survives | When to use |
|---|---|---|---|
| `Mirror` (default) | 50% | 1 failure (disk or node) | Lab, max speed, SSD hot volumes |
| `NestedMirror` | 25% | 2 failures | Production 2-node, max safety |
| `NestedParity` | ~35-40% | 2 failures | Production 2-node, balanced (Microsoft's pick) |

Usable is the share of raw pool capacity available for data: 50% turns
10 TB raw into 5 TB of volumes. Nested volumes cannot be converted in
place later — choose upfront.
`-NestedMirrorPercent` (10-30, default 20) sets the fast-tier share of
`NestedParity` volumes: higher favors write bursts, lower favors capacity.

**Performance.** No vendor IOPS figures exist per resiliency — what matters:

| | Mirror | Nested mirror | Nested parity |
|---|---|---|---|
| Read latency | Lowest | Lowest (any of 4 copies) | Fast for recent data, slower for aged parity data |
| Sustained random writes | Highest | Highest | Lowest (parity encoding + read-modify-write) |
| Backend writes per guest write | 2x | 4x (burns IOPS + endurance) | ~1.2–2x, plus CPU |
| Best for | Hot SSD volumes | Max safety, cost no object | Cold/bulk SAS volumes |

Two rules: size `-NestedMirrorPercent` to your biggest single burst (daily
backup + margin), not the average — overflowing the mirror tier drops
throughput sharply until destaging catches up. And an SSD cache flatters
SAS parity enormously (random writes coalesce in SSD, destage
sequentially), which is why Mirror-on-SSD + Parity-on-SAS is the sweet
spot.

**Volumes.** `-VolumeCount` (1-64, default 1) creates `Name_01`, `Name_02`…
from `-VolumeName` as prefix (count 1 keeps the exact name). Use at least
one volume per node so ownership distributes. A single `-Resiliency` /
`-StorageTier` value broadcasts to all volumes; pass one per volume to
mix (see cases below). Note: S2D reports SAS spinning disks with media
type `HDD`, so the `-StorageTier` value for SAS is `HDD`.

### Which drives you have decides everything

S2D automatically binds the fastest media as cache. Cache drives serve
hot data but contribute zero usable capacity. That gives four cases:

**Case A — SSD + SAS, no NVMe (single SAS tier).** The SSDs become
read+write cache; every volume lives on SAS. You cannot create SSD
volumes — but hot VM data is still served from SSD automatically, so
size the cache to cover the active working set (~10% of SAS capacity:
4x 4 TB SAS per server → 2x 800 GB SSD cache). Keep `-StorageTier` on
`Auto` (it picks SAS); forcing `SSD` warns. The reserve floor counts
SAS only. Example: 32 TB raw SAS pool with an 8 TB floor (2 nodes x
4 TB drive) → `Mirror` usable ≈ (free − 8 TB) x 50%.

```powershell
New-S2DCluster -ClusterName "ClusterPDL" -ClusterNodes "HV1","HV2" -ClusterIP "192.168.1.240" -WitnessType "FileShare" -FileShareWitness "\\NTSVR22\ClusterPDL$" -VolumeName "CSV_S2D" -SizingMode "Auto"
```

**Case B — NVMe + SSD + SAS (two tiers).** NVMe becomes cache; SSD and
SAS are both capacity, so volumes can sit on either side by side (SSD
reads come straight off SSD, SAS gets read+write cache). This is the
layout for hot VMs on SSD and cold data on SAS — pin per volume:

```powershell
New-S2DCluster -ClusterName "ClusterPDL" -ClusterNodes "HV1","HV2" -ClusterIP "192.168.1.240" -WitnessType "FileShare" -FileShareWitness "\\NTSVR22\ClusterPDL$" -VolumeName "CSV" -VolumeCount 2 -StorageTier SSD,HDD -Resiliency Mirror,NestedParity -SizingMode "Auto"
# -> CSV_01: Mirror on SSD (hot VMs) | CSV_02: NestedParity on SAS (cold)
```

2x NVMe per server is enough (working-set sized, not capacity sized).
The reserve floor counts one SSD plus one SAS drive per server.

**Case C — SSD only (all-flash).** No cache tier (write-only cache is
optional); everything is fast SSD capacity. The simplest layout:
`-StorageTier` `Auto` picks SSD, the reserve floor counts SSD, and
there are no pinning decisions at all.

**Case D — SAS only (spinning disks, no flash).** Not a valid S2D
configuration on its own — every server needs flash for cache (at
least 2 SSD/NVMe cache drives next to 4+ capacity drives). Add SSDs
(becomes case A) or NVMe (becomes case B once SSDs are present, else
NVMe-cached SAS).

**Sizing.** `Auto` (default) splits usable capacity across volumes — each
volume gets an equal pool-footprint share times its own efficiency.
`Fixed` needs per-volume `-VolumeSize` (e.g. `2TB`) and validates the
summed footprint against free space. Both keep a reserve unless
`-UseFullPool`: one capacity drive per server (up to 4, per the case
above) vs. `-CapacityReservePercent` (default 20) — larger wins. Before
creating anything, the script prints usable GiB per resiliency option.
Volumes cap at 64 TB (10 TB for VSS/Volsnap backups); a warning fires
below 4 capacity drives per server.

### Cluster switches at a glance

| Switch | Effect |
|---|---|
| `-VolumeCount 2` | `CSV_01`, `CSV_02`, … (use ≥1 per node) |
| `-Resiliency NestedParity` | All volumes survive 2 failures, ~35-40% usable |
| `-Resiliency Mirror,NestedParity` | Per-volume mix (count must match `-VolumeCount`) |
| `-StorageTier SSD,HDD` | Pin volumes per tier (needs NVMe cache) |
| `-NestedMirrorPercent 30` | Bigger fast tier inside parity volumes (10-30) |
| `-SizingMode Fixed -VolumeSize 2TB` | Exact per-volume size, footprint validated |
| `-CapacityReservePercent 30` | Bigger % reserve (drive floor still applies) |
| `-UseFullPool` | No reserve (post-failure repairs may stall) |
| `-WhatIf` | Prints plan + preflight, changes nothing |

Examples — pick the scenario matching your hardware:

```powershell
# A. Production, SSD+SAS: two nested volumes (one owned per node), 2-failure safety.
New-S2DCluster -ClusterName "ClusterPDL" -ClusterNodes "HV1","HV2" -ClusterIP "192.168.1.240" -WitnessType "FileShare" -FileShareWitness "\\NTSVR22\ClusterPDL$" -VolumeName "CSV" -VolumeCount 2 -Resiliency NestedParity -SizingMode "Auto"

# B. NVMe + SSD + SAS: hot mirror volume on SSD, efficient parity on SAS.
New-S2DCluster -ClusterName "ClusterPDL" -ClusterNodes "HV1","HV2" -ClusterIP "192.168.1.240" -WitnessType "FileShare" -FileShareWitness "\\NTSVR22\ClusterPDL$" -VolumeName "CSV" -VolumeCount 2 -StorageTier SSD,HDD -Resiliency Mirror,NestedParity -SizingMode "Auto"

# C. Fixed sizes: 2 TB per volume, throws if pool + reserve cannot fit it.
New-S2DCluster -ClusterName "ClusterPDL" -ClusterNodes "HV1","HV2" -ClusterIP "192.168.1.240" -WitnessType "FileShare" -FileShareWitness "\\NTSVR22\ClusterPDL$" -VolumeName "CSV" -VolumeCount 2 -SizingMode "Fixed" -VolumeSize "2TB"

# D. Dry run (any variant + -WhatIf): validation + capacity plan, no changes.
New-S2DCluster -ClusterName "ClusterPDL" -ClusterNodes "HV1","HV2" -ClusterIP "192.168.1.240" -WitnessType "FileShare" -FileShareWitness "\\NTSVR22\ClusterPDL$" -VolumeName "CSV" -VolumeCount 2 -StorageTier SSD,HDD -Resiliency Mirror,NestedParity -SizingMode "Auto" -WhatIf
```

### Microsoft references

The module implements these best practices — read the source when sizing edge cases:

- [Plan volumes](https://learn.microsoft.com/en-us/windows-server/storage/storage-spaces/plan-volumes) — resiliency per node count, reserve rule, 64 TB cap
- [Nested resiliency](https://learn.microsoft.com/en-us/windows-server/storage/storage-spaces/nested-resiliency) — how the two nested options work, efficiency table
- [Choose drives](https://learn.microsoft.com/en-us/windows-server/storage/storage-spaces/choose-drives) — which media becomes cache vs. capacity, minimums
- [Understanding the cache](https://learn.microsoft.com/en-us/windows-server/storage/storage-spaces/cache) — cache behavior per drive layout
- [Deploy Storage Spaces Direct](https://learn.microsoft.com/en-us/windows-server/storage/storage-spaces/deploy-storage-spaces-direct) — the official deployment sequence
- [Hardware requirements](https://learn.microsoft.com/en-us/windows-server/storage/storage-spaces/storage-spaces-direct-hardware-requirements) — drive minimums, 400 TB/server guidance

## 3. Validate the deployment

```powershell
Get-VirtualDisk | Format-Table FriendlyName, HealthStatus, OperationalStatus
Get-StorageJob
Get-StoragePool -FriendlyName "S2D on ClusterPDL" | Select-Object Size, AllocatedSize
```

Plus Failover Cluster Manager: networks named StorageA/StorageB/Mgmt, witness
online, CSV mounted. Run a real `Test-Cluster` before production cutover
(`-WhatIf` runs skip it by design).

## 4. Day-2 operations

Safe reboot (run from the *other* node; `-Force -WhatIf` for a dry run):

```powershell
.\Scripts\Reboot-S2D.ps1 -NodeName "HV1"
```

Disk health flags (vendored Don MacGregor helper, use as-is):

Clears persistent Health Service flags (*Intent*/*Policy*) that Windows keeps on
physical disks after an incident. Use it when: a replaced drive still shows as
unhealthy/retired (ghost state), a healthy disk is wrongly refused for pooling
(`CanPool = False`) after a transient issue (cable, bay, firmware) you already
fixed, or you reuse lab disks carrying flags from a previous pool.

Golden rule: **verify real health first, clear flags second — never to mask
dying hardware.** Clearing on a truly failed disk just re-flags it next cycle,
with a degraded pool in between.

```powershell
# 1. Check real health first (SMART, LED, operational status)
Get-PhysicalDisk -SerialNumber <sn> | Format-List FriendlyName, HealthStatus, OperationalStatus
# 2. Only if hardware is healthy and the flag is stale:
Get-PhysicalDisk -UniqueId <id> | Clear-PhysicalDiskHealthData -Intent -Policy -Force
```

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `found 3 physical NIC(s), minimum 4` | Not a node (or missing NICs). NodePrep needs StorageA/B + LiveMig + ≥1 VM. |
| `'X' link is 1 Gbps, 10 Gbps minimum required` | NIC/switch/cable below spec. Fix hardware, re-run. |
| `not RDMA-capable` / `RDMA capability unproven` | Enable RDMA stack / install vendor driver first. |
| `no poolable disks (CanPool)` | PERC in RAID mode — switch controller to HBA/pass-through. |
| `resolves to N adapter(s)` after rename | Collision from a partial run — clean the duplicate name, re-run. |
| No Mandatory prompt / stale behavior | Stale module in session — `Import-Module ... -Force` every new shell. |
| `Test-Cluster` include mismatch | FR-first/EN-fallback is built in; on other locales, extend the list. |

## Reference

- Module `Deploy-S2D/` (v2.0.0, shippable): `Start-S2DNodePrep`,
  `New-S2DCluster`, `Start-S2DDeployment` (back-compat wrapper). `Public/` = one
  function per file, `Private/` = helpers, `en-US/` = conceptual help.
  `Scripts/` = reboot runbook, vendored helper, one-offs. `archive/` = retired.
- Tests: `Tests/` (Pester 5) + `.github/workflows/ci.yml` (analyzer errors + Pester).
  Local: `Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1 -Severity Error`
  then `Invoke-Pester -Path ./Tests -Output Detailed`.
- Design notes: exactly 2 storage NICs (two fabrics) and exactly 1 LiveMig by
  design; no environment defaults in shared code (engine prompts instead);
  every destructive path supports `-WhatIf`; resume happens exactly once,
  after resync.

## Testing & lint (end of checklist)

```powershell
Import-Module .\Deploy-S2D\Deploy-S2D.psm1 -Force
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
Invoke-Pester -Path ./Tests -Output Detailed
```

Analyzer must report zero `Error`s (warnings print for info; `Write-Host` is
excluded by design — console output is the deploy UX). Pester covers manifest,
parameter contracts, boundary throws, mocked NodePrep runs, volume
planning/sizing, and the mocked cluster-volume runtime.
GitHub Actions runs both on every push/PR (`windows-latest`, PowerShell 5.1).
