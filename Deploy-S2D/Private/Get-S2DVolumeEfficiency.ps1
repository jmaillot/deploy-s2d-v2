function Get-S2DVolumeEfficiency {
<#
.SYNOPSIS
Usable-to-footprint efficiency for an S2D resiliency type.
.DESCRIPTION
Pure function (no cluster access) so Pester can test it directly.
Mirror = 0.50, NestedMirror = 0.25. NestedParity interpolates the
Microsoft lookup table (capacity drives per server x mirror percent):
4 drives: 10% -> 0.357, 20% -> 0.341, 30% -> 0.326
5 drives: 10% -> 0.377, 20% -> 0.357, 30% -> 0.339
6 drives: 10% -> 0.391, 20% -> 0.368, 30% -> 0.347
7+ drives: 10% -> 0.400, 20% -> 0.375, 30% -> 0.353
.PARAMETER Resiliency
Mirror (classic 2-way), NestedMirror (nested 2-way), NestedParity
(nested mirror-accelerated parity).
.PARAMETER CapacityDrivesPerServer
Capacity drive count per server. Clamped to the 4..7+ table range.
.PARAMETER NestedMirrorPercent
Fast-tier mirror share for NestedParity. Range 10-30, default 20.
#>
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Mirror', 'NestedMirror', 'NestedParity')]
        [string]$Resiliency,
        [int]$CapacityDrivesPerServer = 4,
        [ValidateRange(10, 30)]
        [int]$NestedMirrorPercent = 20
    )

    if ($Resiliency -eq 'Mirror') { return 0.5 }
    if ($Resiliency -eq 'NestedMirror') { return 0.25 }

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
