function Get-S2DVolumeTierMap {
<#
.SYNOPSIS
Resolves per-volume tier media (broadcast or 1:1).
.DESCRIPTION
Pure function (no cluster access) so Pester can test it directly. A
single StorageTier value broadcasts to every volume; otherwise the
count must match VolumeCount exactly. "Auto" entries resolve to
DefaultMedia (the caller's capacity default, e.g. HDD).
.PARAMETER VolumeCount
Number of volumes to create (1-64).
.PARAMETER StorageTier
One tier per volume, or a single tier broadcast to all.
.PARAMETER DefaultMedia
Capacity media used for "Auto" entries.
#>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [int]$VolumeCount,
        [Parameter(Mandatory = $true)]
        [string[]]$StorageTier,
        [string]$DefaultMedia = "HDD"
    )

    if ($StorageTier.Count -eq 1) {
        $raw = @()
        for ($i = 0; $i -lt $VolumeCount; $i++) { $raw += $StorageTier[0] }
    } elseif ($StorageTier.Count -eq $VolumeCount) {
        $raw = @($StorageTier)
    } else {
        throw "StorageTier count ($($StorageTier.Count)) must be 1 or match VolumeCount ($VolumeCount)."
    }
    return @($raw | ForEach-Object { if ($_ -eq "Auto") { $DefaultMedia } else { $_ } })
}
