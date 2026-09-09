function Get-S2DVolumeResiliencyMap {
<#
.SYNOPSIS
Resolves per-volume resiliency (broadcast or 1:1).
.DESCRIPTION
Pure function (no cluster access) so Pester can test it directly. A
single Resiliency value broadcasts to every volume; otherwise the count
must match VolumeCount exactly. Element values are validated by the
caller's ValidateSet.
.PARAMETER VolumeCount
Number of volumes to create (1-64).
.PARAMETER Resiliency
One resiliency per volume, or a single resiliency broadcast to all.
#>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [int]$VolumeCount,
        [Parameter(Mandatory = $true)]
        [string[]]$Resiliency
    )

    if ($Resiliency.Count -eq 1) {
        $map = @()
        for ($i = 0; $i -lt $VolumeCount; $i++) { $map += $Resiliency[0] }
        return ,$map
    }
    if ($Resiliency.Count -eq $VolumeCount) {
        return ,@($Resiliency)
    }
    throw "Resiliency count ($($Resiliency.Count)) must be 1 or match VolumeCount ($VolumeCount)."
}
