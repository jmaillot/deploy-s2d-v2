function Get-S2DDualParityEfficiency {
<#
.SYNOPSIS
Dual-parity efficiency for a node count (4-16).
.DESCRIPTION
Pure function (no cluster access) so Pester can test it directly.
Microsoft per-node layout table: hybrid pools (HDD capacity present)
run 4-6 nodes -> 0.50, 7-11 -> 0.667, 12-16 -> 0.727; all-flash
pools run 4-6 -> 0.50, 7-8 -> 0.667, 9-15 -> 0.75, 16 -> 0.80.
Called by Get-S2DVolumeEfficiency, which gates node validity.
.PARAMETER NodeCount
Cluster node count. Clamped to the 4..16 table range.
.PARAMETER AllFlash
Use the all-flash column. Default is the hybrid (conservative) column.
#>
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [int]$NodeCount = 4,
        [switch]$AllFlash
    )

    $n = [math]::Min(16, [math]::Max(4, $NodeCount))
    if ($n -le 6) { return 0.5 }
    if ($AllFlash) {
        if ($n -le 8) { return 0.667 }
        if ($n -le 15) { return 0.75 }
        return 0.8
    }
    if ($n -le 11) { return 0.667 }
    return 0.727
}
