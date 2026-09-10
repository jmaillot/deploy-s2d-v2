# Changelog

## [Unreleased]
### Added
- N-node clusters (2-16): `Mirror` is 2-way (50%) on 2 nodes, 3-way
  (33.3%) on 3+; `DualParity` (50-80% by node count, hybrid vs.
  all-flash columns) and `MirrorAcceleratedParity` (3-way mirror +
  dual parity blend via `-NestedMirrorPercent`) on 4+ nodes.
  Nested options throw outside 2 nodes, dual-parity options below 4.
  Pinned `MirrorOn` tier uses 3 copies on 3+ nodes.
- Planner: node-gated resiliency options, switched-fabric guide and
  3-node quorum warning above 2 nodes (EN+FR), node-aware efficiency
  and `New-S2DCluster` command export.

## [2.0.1] - 2026-09-10
### Added
- Mocked runtime tests for the volume path (`ClusterVolume.Tests.ps1`):
  Auto sizing, tier ensure-or-skip, per-volume calls, Fixed guard
- `New-S2DVolume` wrapper (Pester cannot proxy `New-Volume` directly)

## [2.0.0] - 2026-09-09
### Added
- `-Resiliency Mirror|NestedMirror|NestedParity` on `New-S2DCluster`
  (nested survives 2 failures; cannot be converted in place later)
- `-VolumeCount` (1-64, `-VolumeName` as prefix) so ownership distributes
  (at least 1 volume per node); `-NestedMirrorPercent` (10-30, default 20)
  and `-StorageTier Auto|SSD|HDD` for nested tier placement
- Per-volume tier pinning: single `-StorageTier` broadcasts, or one per
  volume (`-VolumeCount 2 -StorageTier SSD,HDD` pins hot to SSD, cold to
  SAS; needs NVMe/SCM cache for both side by side). Pinned Mirror
  volumes use an auto-created MirrorOn tier template
- Per-volume resiliency: single `-Resiliency` broadcasts, or one per
  volume (`Mirror,NestedParity`); Auto sizing gives each volume an equal
  pool-footprint share times its own efficiency
- Drive-based reserve floor (1 capacity drive/server up to 4; SSD+SAS only
  with a dedicated NVMe/SCM cache tier, else SAS alone);
  larger of floor and `-CapacityReservePercent` wins. Drive counts and
  nested-parity efficiency use capacity disks only (cache SSDs excluded)
- Fixed-mode footprint validation (size/efficiency + reserve vs. pool free)
  with 64 TB / 10 TB VSS guidance; sub-4-drives/server preflight warning
- Verbose capacity plan printed before creation (usable GiB per resiliency)
- Capacity planner site (`s2dcalculator/`, GitHub Pages, EN/FR toggle):
  both sizing directions, cache minimums, NVMe add-or-skip verdict,
  PowerShell command export
- README galleries per step, cluster switch grid, case-based tiers,
  resiliency performance comparison, Microsoft reference links (EN+FR)

## [1.7.0] - 2026-09-09
### Added
- LiveMig: jumbo MTU, EEE off, DNS registration + NetBIOS off (same hygiene
  as storage); DNS/NetBIOS off also on StorageA/B
- Mgmt: EEE off (best-effort across vendor property names)
- Storage: VMQ/RSC/EEE off, RSS on (VM side untouched)
- VM adapters: VMQ/RSS/RSC on, Jumbo off; Mgmt: VMQ off. VMMQ is per-vNIC
  post-deploy (`Set-VMNetworkAdapter -VmmqEnabled/-VrssEnabled`), not NodePrep
  (no VMs/vNICs exist yet — NodePrep only enables its physical prerequisites)

## [1.6.0] - 2026-09-08
### Changed
- `AzStorageKey` is `SecureString` end to end (function, forwarder, wrapper);
  decrypted only for the quorum call, cleared after, never logged
- Thin forwarders accept `-WhatIf` via `SupportsShouldProcess`

## [1.5.0] - 2026-09-08
### Added
- Post-rename verification (loud collision error instead of misconfiguration)
- 10 Gbps + RDMA preflight on storage/LiveMig, with SMB-binding fallback probe
- Dell preflight: poolable-disk (`CanPool`) throw, all-HDD warning, NIC driver
  table and BIOS virtualization check (advisory)
- Optional `-LiveMigrationIP` binds the migration network (`Add-VMMigrationNetwork`)
- `-LogPath` on deploy functions; `ConfirmImpact = High`
### Changed
- QoS cleanup touches only the `SMBDirect` policy (no more nuke-all)
- IP inputs validated (parse, A≠B, different subnets, prefix range 1–31)
- `Enable-NetAdapterRdma` by `-Name`; dropped bogus `Set-VMSwitch -EnableSoftwareRsc`

## [1.4.0] - 2026-09-08
### Added
- Console NIC picker (`Select-S2DNic`): per-role menus, exclusion, validation
- Dynamic vSwitch: SET team for 2+ VM NICs, plain vSwitch for 1

## [1.3.0] - 2026-09-08
### Changed
- **Breaking:** identity params are `Mandatory` with no environment defaults;
  engine prompts when missing. Values live in `DeployCmd-*` examples

## [1.2.0] - 2026-09-08
### Added
- Standard module layout (`Public/` + `Private/`, loader `.psm1`, manifest)

## [1.1.0] - 2026-09-08
### Added
- Split `Start-S2DDeployment` into `Start-S2DNodePrep` (per node) and
  `New-S2DCluster` (once); FR→EN `Test-Cluster` fallback
### Fixed
- En-dash parameters, `Select-Objectv` typo, `$ClusterName.Name` null pool,
  single-backslash UNC default
