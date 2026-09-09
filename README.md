# S2DCluster — Usage Guide

> Version française : [README_FR.md](README_FR.md).

Deploys a 2-node Storage Spaces Direct (S2D) cluster on Windows Server 2025:
per-node network/storage prep, then one-shot cluster creation with quorum,
S2D enablement, and a mirrored CSV volume. PowerShell 5.1, FR/EN locales.

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

Always dry-run first: append `-WhatIf` (preflight still executes — that's the point).

## 2. Create the cluster (once, from either node)

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

| `-Resiliency` | Efficiency | Survives | When to use |
|---|---|---|---|
| `Mirror` (default) | 50% | 1 failure (disk or node) | Lab, max speed, SSD hot volumes |
| `NestedMirror` | 25% | 2 failures | Production 2-node, max safety |
| `NestedParity` | ~35-40% | 2 failures | Production 2-node, balanced (Microsoft's pick) |

Nested volumes cannot be converted in place later — choose upfront.
`-NestedMirrorPercent` (10-30, default 20) sets the fast-tier share of
`NestedParity` volumes: higher favors write bursts, lower favors capacity.

**Volumes.** `-VolumeCount` (1-64, default 1) creates `Name_01`, `Name_02`…
from `-VolumeName` as prefix (count 1 keeps the exact name). Use at least
one volume per node so ownership distributes. A single `-Resiliency` /
`-StorageTier` value broadcasts to all volumes; pass one per volume to
mix — e.g. fast mirror on SSD plus efficient parity on SAS:

```powershell
New-S2DCluster -ClusterName "ClusterPDL" -ClusterNodes "HV1","HV2" -ClusterIP "192.168.1.240" -WitnessType "FileShare" -FileShareWitness "\\NTSVR22\ClusterPDL$" -VolumeName "CSV" -VolumeCount 2 -StorageTier SSD,HDD -Resiliency Mirror,NestedParity -SizingMode "Auto"
```

**Tiers.** S2D binds the fastest media as cache, so SSD + SAS alone yields
a single (SAS) capacity tier — hot data is still served from the SSD
read+write cache automatically. Side-by-side SSD and SAS volumes need a
dedicated cache tier (2x NVMe per server is enough); then `-StorageTier`
pins volumes (`SSD` hot, `HDD` cold). `Auto` (default) picks HDD when
present, else SSD.

**Sizing.** `Auto` (default) splits usable capacity across volumes — each
volume gets an equal pool-footprint share times its own efficiency.
`Fixed` needs per-volume `-VolumeSize` (e.g. `2TB`) and validates the
summed footprint against free space. Both keep a reserve unless
`-UseFullPool`: one capacity drive per server (up to 4; SSD+HDD only with
NVMe/SCM cache, else HDD alone) vs. `-CapacityReservePercent` (default
20) — larger wins. Before creating anything, the script prints usable GiB
per resiliency option. Volumes cap at 64 TB (10 TB for VSS/Volsnap
backups); a warning fires below 4 capacity drives per server.

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

- Module `Deploy-S2D/` (v1.6.0, shippable): `Start-S2DNodePrep`,
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
excluded by design — console output is the deploy UX). Pester runs 15 tests:
manifest, parameter contracts, boundary throws, two mocked NodePrep runs.
GitHub Actions runs both on every push/PR (`windows-latest`, PowerShell 5.1).
