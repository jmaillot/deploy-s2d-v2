function Get-S2DCapacityReserve {
<#
.SYNOPSIS
Pool reserve in bytes: drive-based floor vs. percent, max wins.
.DESCRIPTION
Pure function (no cluster access) so Pester can test it directly.
Microsoft recommends reserving one capacity drive per server (up to 4
drives); with a dedicated cache tier (NVMe/SCM) plus SSD+HDD capacity,
one of each per server. The
percent reserve is kept as an override for large pools. Returns the
larger of the two, capped at the free pool bytes.
The drive floor is approximated from pool-wide data: reserve slots =
min(node count, 4), times the largest drive of each capacity media
type (see Get-S2DCapacityMedia; SSD+SAS pools count HDD only).
.PARAMETER PoolFreeBytes
Free pool bytes (pool Size minus AllocatedSize).
.PARAMETER NodeCount
Cluster node count. Reserve slots = min(NodeCount, 4).
.PARAMETER ReservePercent
Percent of free pool held back. Range 0-100.
.PARAMETER Drives
Poolable drive objects with Size, MediaType, and BusType properties
(e.g. Get-S2DPoolDisk output). Empty when unknown: percent only.
#>
    [CmdletBinding()]
    [OutputType([uint64])]
    param(
        [Parameter(Mandatory = $true)]
        [uint64]$PoolFreeBytes,
        [int]$NodeCount = 2,
        [ValidateRange(0, 100)]
        [int]$ReservePercent = 20,
        [array]$Drives = @()
    )

    $slots = [math]::Min($NodeCount, 4)
    [uint64]$floor = 0
    if ($Drives.Count -gt 0 -and $slots -gt 0) {
        $capacityMedia = Get-S2DCapacityMedia -Drives $Drives
        $capacityGroups = @($Drives | Where-Object { $_.MediaType -in $capacityMedia })
        if ($capacityGroups.Count -eq 0) {
            $capacityGroups = @($Drives)
        }
        $byMedia = $capacityGroups | Group-Object -Property MediaType
        foreach ($g in $byMedia) {
            $largest = ($g.Group | Measure-Object -Property Size -Maximum).Maximum
            $floor += [uint64]$slots * [uint64]$largest
        }
    }
    [uint64]$percentReserve = [uint64][math]::Floor($PoolFreeBytes * ($ReservePercent / 100.0))
    [uint64]$reserve = [uint64][math]::Max($floor, $percentReserve)
    if ($reserve -gt $PoolFreeBytes) { $reserve = $PoolFreeBytes }
    Write-Verbose ("Reserve: floor {0} GiB (slots {1}) vs percent {2}% = {3} GiB -> {4} GiB of {5} GiB free." -f ([math]::Round($floor / 1GB, 2)), $slots, $ReservePercent, ([math]::Round($percentReserve / 1GB, 2)), ([math]::Round($reserve / 1GB, 2)), ([math]::Round($PoolFreeBytes / 1GB, 2)))
    return $reserve
}
