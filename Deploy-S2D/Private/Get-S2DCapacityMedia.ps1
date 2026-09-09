function Get-S2DCapacityMedia {
<#
.SYNOPSIS
Which media types hold S2D capacity (vs. cache).
.DESCRIPTION
Pure function (no cluster access) so Pester can test it directly. S2D
uses the fastest media as cache: with only SSD+HDD (e.g. SSD + SAS
spinning disks), SSD is cache and HDD alone is capacity. A dedicated
cache tier (NVMe bus or SCM media) promotes SSD to capacity alongside
HDD. Returns the capacity media type names. Empty input means unknown.
.PARAMETER Drives
Drive objects with MediaType and BusType properties
(e.g. Get-S2DPoolDisk output). Empty when unknown.
#>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [array]$Drives = @()
    )

    if ($Drives.Count -eq 0) { return @() }
    $mediaTypes = @($Drives | ForEach-Object { $_.MediaType } | Select-Object -Unique)
    $hasHdd = $mediaTypes -contains 'HDD'
    $hasSsd = $mediaTypes -contains 'SSD'
    if ($hasHdd -and $hasSsd) {
        $hasDedicatedCache = @($Drives | Where-Object { $_.MediaType -eq 'SCM' -or $_.BusType -eq 'NVMe' }).Count -gt 0
        if ($hasDedicatedCache) { return @('SSD', 'HDD') }
        return ,@('HDD')
    }
    if ($hasHdd) { return ,@('HDD') }
    if ($hasSsd) { return ,@('SSD') }
    return ,@($mediaTypes)
}
