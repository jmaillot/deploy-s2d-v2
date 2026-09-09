function Get-S2DPoolDisk {
<#
.SYNOPSIS
Physical disks in a storage pool. Thin wrapper so tests can mock the Storage
module (whose CIM parameter types break Pester proxy generation).
.PARAMETER PoolName
Storage pool friendly name, e.g. "S2D on ClusterPDL".
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PoolName
    )
    $pool = Get-StoragePool -FriendlyName $PoolName -ErrorAction Stop
    # A pool with no readable disks yields empty; callers treat empty as unknown.
    $pool | Get-PhysicalDisk -ErrorAction SilentlyContinue
}
