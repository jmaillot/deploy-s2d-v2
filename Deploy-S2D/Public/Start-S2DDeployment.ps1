function Start-S2DDeployment {
<#
.SYNOPSIS
Back-compat wrapper. Prefer Start-S2DNodePrep (per node) and New-S2DCluster (once).
.DESCRIPTION
Dispatches on RunPhase and forwards only explicitly bound values, so unprovided
identity values fall through to the inner Mandatory prompts. Kept so existing
callers keep working; new callers should use the two phase functions directly.
.PARAMETER ClusterName
Cluster name (Cluster phase).
.PARAMETER ClusterNodes
Cluster node names (Cluster phase).
.PARAMETER ClusterIP
Cluster static IP (Cluster phase).
.PARAMETER MgmtAdapters
Pre-rename management NIC names (NodePrep phase).
.PARAMETER VMAdapters
Pre-rename vSwitch NIC names (NodePrep phase).
.PARAMETER StorageA
Pre-rename NIC for fabric A (NodePrep phase).
.PARAMETER StorageB
Pre-rename NIC for fabric B (NodePrep phase).
.PARAMETER LiveMigrationAdapter
Pre-rename NIC for live migration (NodePrep phase).
.PARAMETER StorageAIP
This node's StorageA IP (NodePrep phase).
.PARAMETER StorageBIP
This node's StorageB IP (NodePrep phase).
.PARAMETER StoragePrefix
Storage subnet prefix length. Default 24.
.PARAMETER WitnessType
FileShare (default) or Cloud quorum (Cluster phase).
.PARAMETER AzStorageAccount
Cloud witness account name (Cluster phase, Cloud only).
.PARAMETER AzStorageKey
Cloud witness key as SecureString (Cluster phase, Cloud only).
.PARAMETER FileShareWitness
Witness UNC path (Cluster phase, FileShare only).
.PARAMETER VolumeName
CSV friendly name (prefix when VolumeCount > 1). Default CSV_S2D.
.PARAMETER VolumeCount
Number of CSV volumes (1-64). Default 1.
.PARAMETER Resiliency
Mirror (default), NestedMirror, or NestedParity. A single value
broadcasts; pass one per volume to mix.
.PARAMETER NestedMirrorPercent
Fast-tier mirror share for NestedParity. Default 20.
.PARAMETER StorageTier
Capacity media per volume. Auto (default), SSD, or HDD (HDD = SAS spinning
disks). A single value
broadcasts; pass one per volume to pin (needs NVMe/SCM cache for
SSD+SAS side by side).
.PARAMETER VolumeSize
Fixed size. Required when SizingMode is Fixed.
.PARAMETER SizingMode
Auto (default) or Fixed.
.PARAMETER CapacityReservePercent
Pool percent held back in Auto mode. Default 20.
.PARAMETER UseFullPool
Ignore the reserve and use the whole pool.
.PARAMETER LiveMigrationIP
LiveMig IP (NodePrep phase). Binds the migration network when supplied.
.PARAMETER LiveMigrationPrefix
LiveMig subnet prefix length. Default 24.
.PARAMETER LogPath
Log file path. Default C:\S2D_Deployment.log.
.PARAMETER RunPhase
NodePrep (run on each node) or Cluster (run once).
.EXAMPLE
Start-S2DDeployment -ClusterName "CL-S2D" -ClusterNodes "S2D-01","S2D-02" -ClusterIP "192.168.1.200" -MgmtAdapters "Ethernet 1" -VMAdapters "Ethernet 3","Ethernet 4" -StorageA "Ethernet 5" -StorageB "Ethernet 6" -LiveMigrationAdapter "Ethernet 7" -StorageAIP "10.10.10.1" -StorageBIP "10.10.20.1" -WitnessType "FileShare" -FileShareWitness "\\FILESERVER\Witness$" -VolumeName "CSV_S2D" -SizingMode "Auto" -RunPhase "NodePrep"
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType()]
    param(
        [string]$ClusterName,
        [string[]]$ClusterNodes,
        [string]$ClusterIP,
        [string[]]$MgmtAdapters,
        [string[]]$VMAdapters,
        [string]$StorageA,
        [string]$StorageB,
        [string]$LiveMigrationAdapter,
        [string]$StorageAIP,
        [string]$StorageBIP,
        [int]$StoragePrefix = 24,
        [ValidateSet("Cloud","FileShare")]
        [string]$WitnessType = "FileShare",
        [string]$AzStorageAccount = "",
        [SecureString]$AzStorageKey,
        [string]$FileShareWitness = "",
        [string]$VolumeName = "CSV_S2D",
        [int]$VolumeCount = 1,
        [ValidateSet("Mirror","NestedMirror","NestedParity")]
        [string[]]$Resiliency = @("Mirror"),
        [int]$NestedMirrorPercent = 20,
        [ValidateSet("Auto","SSD","HDD")]
        [string[]]$StorageTier = @("Auto"),
        [string]$VolumeSize,
        [ValidateSet("Auto","Fixed")]
        [string]$SizingMode = "Auto",
        [int]$CapacityReservePercent = 20,
        [switch]$UseFullPool,
        [string]$LiveMigrationIP = "",
        [int]$LiveMigrationPrefix = 24,
        [string]$LogPath = "C:\S2D_Deployment.log",
        [ValidateSet("NodePrep","Cluster")]
        [string]$RunPhase
    )
    Write-Warning "Start-S2DDeployment is kept for back-compat. Use Start-S2DNodePrep (per node) and New-S2DCluster (once)."
    # Forward only explicitly bound values: unprovided identity values fall through
    # to the inner Mandatory prompt instead of silently inheriting wrapper defaults.
    if ($RunPhase -eq "NodePrep") {
        $nodeParams = @{}
        foreach ($k in @('MgmtAdapters','VMAdapters','StorageA','StorageB','LiveMigrationAdapter','StorageAIP','StorageBIP','StoragePrefix','LiveMigrationIP','LiveMigrationPrefix','LogPath')) {
            if ($PSBoundParameters.ContainsKey($k)) { $nodeParams[$k] = $PSBoundParameters[$k] }
        }
        if ($PSCmdlet.ShouldProcess("local node", "Start-S2DNodePrep")) {
            Start-S2DNodePrep @nodeParams
        }
    } elseif ($RunPhase -eq "Cluster") {
        $p = @{}
        foreach ($k in @('ClusterName','ClusterNodes','ClusterIP','WitnessType','AzStorageAccount','AzStorageKey','FileShareWitness','VolumeName','VolumeCount','Resiliency','NestedMirrorPercent','StorageTier','VolumeSize','SizingMode','CapacityReservePercent','UseFullPool','LogPath')) {
            if ($PSBoundParameters.ContainsKey($k)) { $p[$k] = $PSBoundParameters[$k] }
        }
        if ($PSCmdlet.ShouldProcess("cluster", "New-S2DCluster")) {
            New-S2DCluster @p
        }
    } else {
        Write-Error "RunPhase must be 'NodePrep' or 'Cluster'"
    }
}
