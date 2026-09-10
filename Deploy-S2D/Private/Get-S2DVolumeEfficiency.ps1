function Get-S2DVolumeEfficiency {
<#
.SYNOPSIS
Usable-to-footprint efficiency for an S2D resiliency type.
.DESCRIPTION
Pure function (no cluster access) so Pester can test it directly.
Mirror = 0.50 on 2 nodes (2-way), 1/3 on 3+ nodes (3-way).
NestedMirror = 0.25 (2 nodes only). NestedParity interpolates the
Microsoft lookup table (capacity drives per server x mirror percent,
2 nodes only):
4 drives: 10% -> 0.357, 20% -> 0.341, 30% -> 0.326
5 drives: 10% -> 0.377, 20% -> 0.357, 30% -> 0.339
6 drives: 10% -> 0.391, 20% -> 0.368, 30% -> 0.347
7+ drives: 10% -> 0.400, 20% -> 0.375, 30% -> 0.353
DualParity (4-16 nodes) uses the Microsoft per-node layout table.
Hybrid pools (HDD capacity present): 4-6 nodes -> 0.50, 7-11 ->
0.667, 12-16 -> 0.727. All-flash pools (-AllFlash): 4-6 -> 0.50,
7-8 -> 0.667, 9-15 -> 0.75, 16 -> 0.80.
MirrorAcceleratedParity (4-16 nodes) blends 3-way mirror and dual
parity by -NestedMirrorPercent: mirror share at 1/3 plus parity
share at the dual-parity efficiency above.
.PARAMETER Resiliency
Mirror (2-way on 2 nodes, 3-way on 3+), NestedMirror / NestedParity
(2 nodes only), DualParity / MirrorAcceleratedParity (4+ nodes only).
.PARAMETER CapacityDrivesPerServer
Capacity drive count per server. Clamped to the 4..7+ table range
(nested parity only).
.PARAMETER NestedMirrorPercent
Fast-tier mirror share for NestedParity and MirrorAcceleratedParity.
Range 10-30, default 20.
.PARAMETER NodeCount
Cluster node count (2-16). Selects 2-way vs 3-way mirror and gates
the nested (2 only) and dual-parity (4+) options.
.PARAMETER AllFlash
Use the all-flash dual-parity column (no HDD capacity). Default is
the hybrid column, which is the conservative choice at every scale.
#>
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Mirror', 'NestedMirror', 'NestedParity', 'DualParity', 'MirrorAcceleratedParity')]
        [string]$Resiliency,
        [int]$CapacityDrivesPerServer = 4,
        [ValidateRange(10, 30)]
        [int]$NestedMirrorPercent = 20,
        [ValidateRange(2, 16)]
        [int]$NodeCount = 2,
        [switch]$AllFlash
    )

    if ($Resiliency -eq 'Mirror') {
        if ($NodeCount -le 2) { return 0.5 }
        return 1.0 / 3.0
    }
    if ($Resiliency -eq 'NestedMirror') {
        if ($NodeCount -ne 2) { throw "NestedMirror requires exactly 2 nodes (got $NodeCount)." }
        return 0.25
    }
    if ($Resiliency -eq 'DualParity' -or $Resiliency -eq 'MirrorAcceleratedParity') {
        if ($NodeCount -lt 4) { throw "$Resiliency requires at least 4 nodes (got $NodeCount)." }
    }
    if ($Resiliency -eq 'DualParity') { return Get-S2DDualParityEfficiency -NodeCount $NodeCount -AllFlash:$AllFlash }
    if ($Resiliency -eq 'MirrorAcceleratedParity') {
        $mirrorShare = $NestedMirrorPercent / 100.0
        $parityEff = Get-S2DDualParityEfficiency -NodeCount $NodeCount -AllFlash:$AllFlash
        return ($mirrorShare * (1.0 / 3.0)) + ((1.0 - $mirrorShare) * $parityEff)
    }
    if ($NodeCount -ne 2) { throw "NestedParity requires exactly 2 nodes (got $NodeCount)." }

    $rowKey = if ($CapacityDrivesPerServer -ge 7) { 7 } elseif ($CapacityDrivesPerServer -le 4) { 4 } else { $CapacityDrivesPerServer }
    $table = @{
        4 = @{ P10 = 0.357; P20 = 0.341; P30 = 0.326 }
        5 = @{ P10 = 0.377; P20 = 0.357; P30 = 0.339 }
        6 = @{ P10 = 0.391; P20 = 0.368; P30 = 0.347 }
        7 = @{ P10 = 0.400; P20 = 0.375; P30 = 0.353 }
    }
    $row = $table[$rowKey]
    if ($NestedMirrorPercent -le 10) { return $row.P10 }
    if ($NestedMirrorPercent -ge 30) { return $row.P30 }
    if ($NestedMirrorPercent -le 20) {
        $f = ($NestedMirrorPercent - 10) / 10.0
        return $row.P10 + $f * ($row.P20 - $row.P10)
    }
    $f = ($NestedMirrorPercent - 20) / 10.0
    return $row.P20 + $f * ($row.P30 - $row.P20)
}
