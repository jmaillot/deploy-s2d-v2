function New-S2DCluster {
<#
.SYNOPSIS
Cluster creation + S2D. Run ONCE from one node.
.DESCRIPTION
Validates (Test-Cluster, FR-first/EN-fallback, strict), creates the cluster, sets quorum,
enables S2D, creates VolumeCount CSV volumes (ReFS) with the selected resiliency,
constrains SMB Multichannel to
StorageA/B, renames cluster networks. Passes the Test-Cluster report through.
Re-runnable: existing cluster (with matching nodes), S2D pool, and volume are
detected and skipped instead of recreated.
.PARAMETER ClusterName
Cluster name.
.PARAMETER ClusterNodes
Exactly 2 cluster node names.
.PARAMETER ClusterIP
Cluster static IP. Must be free (pre-checked).
.PARAMETER WitnessType
FileShare (default) or Cloud quorum.
.PARAMETER AzStorageAccount
Cloud witness account name (Cloud only).
.PARAMETER AzStorageKey
Cloud witness key as SecureString, e.g. Read-Host -AsSecureString (Cloud only).
.PARAMETER FileShareWitness
Witness UNC path, e.g. \\FS01\Witness$ (FileShare only). Reachability pre-checked.
.PARAMETER VolumeName
CSV friendly name. With VolumeCount 1 (default) used as-is; otherwise used
as prefix (CSV_S2D -> CSV_S2D_01, CSV_S2D_02). Default CSV_S2D.
.PARAMETER VolumeCount
Number of CSV volumes (1-64). Use at least 1 per node so volume ownership
distributes. Default 1.
.PARAMETER Resiliency
Mirror (classic 2-way, 50% efficiency, survives 1 failure), NestedMirror
(nested 2-way, 25%, survives 2 failures), NestedParity (nested
mirror-accelerated parity, ~35-40%, survives 2 failures). A single value
broadcasts to all volumes, or pass one per volume (count must match
VolumeCount), e.g. Mirror,NestedParity for a fast SSD volume plus an
efficient SAS volume. Nested volumes cannot be converted in place later;
Microsoft recommends nested for production 2-node clusters. Default Mirror.
.PARAMETER NestedMirrorPercent
Fast-tier mirror share for NestedParity (10-30, default 20). Higher values
favor write bursts; lower values favor capacity.
.PARAMETER StorageTier
Capacity media per volume: a single value broadcasts to all volumes, or
pass one per volume (count must match VolumeCount), e.g. SSD,HDD pins
volume _01 to SSD and _02 to SAS/HDD. Needs NVMe/SCM cache for SSD+HDD
side by side. Auto (default) picks HDD when present, else SSD. Classic
Mirror volumes with Auto are auto-placed by S2D; explicit pins use a
MirrorOn<Media> tier template created if missing.
.PARAMETER VolumeSize
Per-volume fixed size with optional suffix, e.g. 2TB, 512GB, bytes.
Required when SizingMode is Fixed.
.PARAMETER SizingMode
Auto (default, splits usable capacity evenly across volumes) or Fixed.
.PARAMETER CapacityReservePercent
Pool percent held back in addition to the drive-based floor (one capacity
drive per server, up to 4; SSD plus HDD when both tiers exist). The larger
of floor and percent wins. Default 20, range 0-100.
.PARAMETER UseFullPool
Ignore the reserve and use the whole pool.
.PARAMETER LogPath
Log file path. Default C:\S2D_Deployment.log.
.EXAMPLE
New-S2DCluster -ClusterName "ClusterPDL" -ClusterNodes "HV1","HV2" -ClusterIP "192.168.1.240" -WitnessType "FileShare" -FileShareWitness "\\NTSVR22\ClusterPDL$" -VolumeName "CSV_S2D" -SizingMode "Auto"
.EXAMPLE
New-S2DCluster -ClusterName "ClusterPDL" -ClusterNodes "HV1","HV2" -ClusterIP "192.168.1.240" -WitnessType "FileShare" -FileShareWitness "\\NTSVR22\ClusterPDL$" -VolumeName "CSV_S2D" -VolumeCount 2 -Resiliency NestedParity -SizingMode "Auto"
.EXAMPLE
# NVMe cache + SSD/SAS capacity: hot volume pinned to SSD, cold to SAS/HDD.
New-S2DCluster -ClusterName "ClusterPDL" -ClusterNodes "HV1","HV2" -ClusterIP "192.168.1.240" -WitnessType "FileShare" -FileShareWitness "\\NTSVR22\ClusterPDL$" -VolumeName "CSV" -VolumeCount 2 -StorageTier SSD,HDD -SizingMode "Auto"
.EXAMPLE
# Fast mirror for the SSD volume, efficient parity for the SAS volume.
New-S2DCluster -ClusterName "ClusterPDL" -ClusterNodes "HV1","HV2" -ClusterIP "192.168.1.240" -WitnessType "FileShare" -FileShareWitness "\\NTSVR22\ClusterPDL$" -VolumeName "CSV" -VolumeCount 2 -StorageTier SSD,HDD -Resiliency Mirror,NestedParity -SizingMode "Auto"
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([System.Object])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ClusterName,
        [Parameter(Mandatory = $true)]
        [ValidateCount(2, 2)]
        [string[]]$ClusterNodes,
        [Parameter(Mandatory = $true)]
        [string]$ClusterIP,
        [ValidateSet("Cloud","FileShare")]
        [string]$WitnessType = "FileShare",
        [string]$AzStorageAccount = "",
        [SecureString]$AzStorageKey,
        [string]$FileShareWitness = "",
        [string]$VolumeName = "CSV_S2D",
        [ValidateRange(1, 64)]
        [int]$VolumeCount = 1,
        [ValidateSet("Mirror","NestedMirror","NestedParity")]
        [string[]]$Resiliency = @("Mirror"),
        [ValidateRange(10, 30)]
        [int]$NestedMirrorPercent = 20,
        [ValidateSet("Auto","SSD","HDD")]
        [string[]]$StorageTier = @("Auto"),
        [string]$VolumeSize,
        [ValidateSet("Auto","Fixed")]
        [string]$SizingMode = "Auto",
        [ValidateRange(0, 100)]
        [int]$CapacityReservePercent = 20,
        [switch]$UseFullPool,
        [string]$LogPath = "C:\S2D_Deployment.log"
    )

    if ($WitnessType -eq "FileShare" -and [string]::IsNullOrWhiteSpace($FileShareWitness)) {
        throw "WitnessType=FileShare requires -FileShareWitness (UNC path, e.g. \\FS01\Witness$)."
    }
    if ($WitnessType -eq "Cloud" -and ([string]::IsNullOrWhiteSpace($AzStorageAccount) -or $null -eq $AzStorageKey)) {
        throw "WitnessType=Cloud requires -AzStorageAccount and -AzStorageKey (pass a SecureString, e.g. Read-Host -AsSecureString)."
    }
    $VolumeSizeBytes = $null
    if ($SizingMode -eq "Fixed") {
        if ([string]::IsNullOrWhiteSpace($VolumeSize)) { throw "SizingMode=Fixed : fournir -VolumeSize (ex: 2TB)." }
        $m = [regex]::Match($VolumeSize.Trim(), '^(?<n>\d+(\.\d+)?)\s*(?<u>B|KB|MB|GB|TB)?$')
        if (-not $m.Success) { throw "Unparseable -VolumeSize: '$VolumeSize'. Use plain bytes or a KB/MB/GB/TB suffix (ex: 2TB)." }
        $unit = $m.Groups['u'].Value.ToUpper()
        $mult = if ([string]::IsNullOrEmpty($unit) -or $unit -eq 'B') { 1 } else { @{ KB = 1KB; MB = 1MB; GB = 1GB; TB = 1TB }[$unit] }
        $VolumeSizeBytes = [uint64]([double]$m.Groups['n'].Value * $mult)
        if ($VolumeSizeBytes -le 0) { throw "Unparseable -VolumeSize: '$VolumeSize' resolves to 0 bytes." }
    }
    if ($StorageTier.Count -gt 1 -and $StorageTier.Count -ne $VolumeCount) {
        throw "StorageTier count ($($StorageTier.Count)) must be 1 or match VolumeCount ($VolumeCount)."
    }
    if ($Resiliency.Count -gt 1 -and $Resiliency.Count -ne $VolumeCount) {
        throw "Resiliency count ($($Resiliency.Count)) must be 1 or match VolumeCount ($VolumeCount)."
    }

    # Pre-mutation checks: everything verifiable without changing state.
    if ($WitnessType -eq "FileShare" -and -not (Test-Path $FileShareWitness)) {
        throw "FileShare witness unreachable: $FileShareWitness."
    }
    if (Test-Connection -ComputerName $ClusterIP -Count 1 -Quiet -ErrorAction SilentlyContinue) {
        throw "ClusterIP $ClusterIP already answers. Pick a free address."
    }
    foreach ($cn in $ClusterNodes) {
        if (-not (Test-WSMan -ComputerName $cn -ErrorAction SilentlyContinue)) {
            throw "Node unreachable via WinRM: $cn."
        }
    }

    $script:S2DLogPath = $LogPath
    Write-S2DLog "== Cluster - Creating $ClusterName ($ClusterIP) =="

    Write-S2DLog "Cluster validation (Test-Cluster)"
    if ($PSCmdlet.ShouldProcess($ClusterNodes -join ',', "Test-Cluster")) {
        $frOk = $true
        $frErr = ""
        try {
            Test-Cluster -Node $ClusterNodes -Include "Espaces de stockage direct","Inventaire","Réseau","Configuration du système" -ErrorAction Stop
        } catch {
            $frOk = $false
            $frErr = $_.Exception.Message
            Write-Verbose "FR validation unavailable/failed, retrying with EN-US test names."
        }
        if (-not $frOk) {
            try {
                Test-Cluster -Node $ClusterNodes -Include "Storage Spaces Direct","Inventory","Network","System Configuration" -ErrorAction Stop
            } catch {
                throw "Cluster validation failed, aborting before any mutation. FR error: $frErr | EN error: $($_.Exception.Message)"
            }
        }
    }

    if ($PSCmdlet.ShouldProcess($ClusterName, "New-Cluster")) {
        $existing = Get-Cluster -Name $ClusterName -ErrorAction SilentlyContinue
        if (-not $existing) {
            New-Cluster -Name $ClusterName -Node $ClusterNodes -StaticAddress $ClusterIP | Out-Null
        } else {
            $actualNodes = @(Get-ClusterNode -Cluster $ClusterName -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
            $missing = @($ClusterNodes | Where-Object { $_ -notin $actualNodes })
            if ($missing.Count -gt 0) {
                throw "Cluster $ClusterName exists but misses nodes: $($missing -join ', '). Refusing to adopt a foreign cluster."
            }
            Write-S2DLog "Cluster $ClusterName exists with matching nodes, reusing."
        }
    }

    if ($PSCmdlet.ShouldProcess($ClusterName, "Set-ClusterQuorum")) {
        Write-S2DLog "Quorum - $ClusterName"
        if ($WitnessType -eq "Cloud") {
            # Decrypt only for the call; zero the unmanaged copy immediately.
            # Never logged, never stored.
            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($AzStorageKey)
            try {
                $plainKey = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
                Set-ClusterQuorum -CloudWitness -AccountName $AzStorageAccount -AccessKey $plainKey
            } finally {
                $plainKey = $null
                [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
            }
        } else {
            Set-ClusterQuorum -FileShareWitness $FileShareWitness
        }
    }

    if ($PSCmdlet.ShouldProcess($ClusterName, "Enable-ClusterS2D")) {
        Write-S2DLog "Enable S2D - $ClusterName"
        $s2dPool = Get-StoragePool -FriendlyName "S2D on $ClusterName" -ErrorAction SilentlyContinue
        if (-not $s2dPool) {
            Enable-ClusterS2D -Confirm:$false -AutoConfig:$true
        } else {
            Write-S2DLog "S2D pool exists, skipping Enable-ClusterS2D."
        }
    }

    if ($PSCmdlet.ShouldProcess($VolumeName, "New-Volume x$VolumeCount")) {
        Write-S2DLog ("CSV volumes ({0} x{1}) - {2}" -f (($Resiliency | Select-Object -Unique) -join ","), $VolumeCount, $ClusterName)
        $pool = Get-StoragePool -FriendlyName "S2D on $ClusterName" -ErrorAction Stop
        $free = $pool.Size - $pool.AllocatedSize
        $poolDisks = @(Get-S2DPoolDisk -PoolName "S2D on $ClusterName")
        $capacityMedia = Get-S2DCapacityMedia -Drives $poolDisks
        $capacityDisks = @($poolDisks | Where-Object { $_.MediaType -in $capacityMedia })
        if ($capacityDisks.Count -eq 0) { $capacityDisks = $poolDisks }
        $drivesPerServer = [math]::Max(1, [math]::Ceiling($capacityDisks.Count / $ClusterNodes.Count))
        if ($poolDisks.Count -gt 0 -and $drivesPerServer -lt 4) {
            Write-Warning ("Only ~{0} capacity drives per server ({1} capacity disks / {2} nodes). Microsoft minimum is 4 per server; nested resiliency needs 4+." -f $drivesPerServer, $capacityDisks.Count, $ClusterNodes.Count)
        }
        $volumeResiliency = Get-S2DVolumeResiliencyMap -VolumeCount $VolumeCount -Resiliency $Resiliency
        $reserveBytes = [uint64]0
        if (-not $UseFullPool.IsPresent) {
            $reserveBytes = Get-S2DCapacityReserve -PoolFreeBytes $free -NodeCount $ClusterNodes.Count -ReservePercent $CapacityReservePercent -Drives $poolDisks
        }
        $plannedBase = if ($free -gt $reserveBytes) { $free - $reserveBytes } else { [uint64]0 }
        $parityEff = Get-S2DVolumeEfficiency -Resiliency NestedParity -CapacityDrivesPerServer $drivesPerServer -NestedMirrorPercent $NestedMirrorPercent
        $planLine = "Free: {0} GiB | Reserve: {1} GiB | Usable -> Mirror: {2} GiB, NestedMirror: {3} GiB, NestedParity ({4}% mirror): {5} GiB" -f ([math]::Round($free / 1GB, 2)), ([math]::Round($reserveBytes / 1GB, 2)), ([math]::Round($plannedBase * 0.5 / 1GB, 2)), ([math]::Round($plannedBase * 0.25 / 1GB, 2)), $NestedMirrorPercent, ([math]::Round($plannedBase * $parityEff / 1GB, 2))
        Write-Host $planLine -ForegroundColor Yellow
        Write-S2DLog $planLine

        $volumeSizes = @()
        if ($SizingMode -eq "Auto") {
            for ($s = 0; $s -lt $VolumeCount; $s++) {
                $volEff = Get-S2DVolumeEfficiency -Resiliency $volumeResiliency[$s] -CapacityDrivesPerServer $drivesPerServer -NestedMirrorPercent $NestedMirrorPercent
                $volumeSizes += [uint64][math]::Floor(($plannedBase / $VolumeCount) * $volEff)
                if ($volumeSizes[$s] -le 0) { throw "Insufficient capacity left to create volume $($s + 1) of $VolumeCount ($($volumeResiliency[$s]))." }
            }
        } else {
            $footprintTotal = [uint64]0
            for ($s = 0; $s -lt $VolumeCount; $s++) {
                $volEff = Get-S2DVolumeEfficiency -Resiliency $volumeResiliency[$s] -CapacityDrivesPerServer $drivesPerServer -NestedMirrorPercent $NestedMirrorPercent
                $footprintTotal += [uint64][math]::Ceiling($VolumeSizeBytes / $volEff)
                $volumeSizes += $VolumeSizeBytes
            }
            if (($footprintTotal + $reserveBytes) -gt $free) {
                throw ("Fixed volumes need {0} GiB footprint + {1} GiB reserve, but only {2} GiB is free." -f ([math]::Round($footprintTotal / 1GB, 2)), ([math]::Round($reserveBytes / 1GB, 2)), ([math]::Round($free / 1GB, 2)))
            }
            if ($VolumeSizeBytes -gt 64TB) {
                Write-Warning "Volume size exceeds the 64 TB Microsoft recommendation; VSS/Volsnap backup solutions cap at 10 TB per volume."
            }
        }

        $defaultTierMedia = if ($capacityMedia -contains "HDD") { "HDD" } elseif ($capacityMedia.Count -gt 0) { $capacityMedia[0] } else { "SSD" }
        $volumeTierMedia = Get-S2DVolumeTierMap -VolumeCount $VolumeCount -StorageTier $StorageTier -DefaultMedia $defaultTierMedia
        $pinnedFlags = @()
        for ($m = 0; $m -lt $volumeTierMedia.Count; $m++) {
            $rawTier = if ($StorageTier.Count -eq 1) { $StorageTier[0] } else { $StorageTier[$m] }
            $pinnedFlags += ($rawTier -ne "Auto")
        }
        $pinnedMedia = @()
        for ($m = 0; $m -lt $volumeTierMedia.Count; $m++) {
            if ($pinnedFlags[$m]) { $pinnedMedia += $volumeTierMedia[$m] }
        }
        $pinnedMedia = @($pinnedMedia | Select-Object -Unique)
        foreach ($pinned in $pinnedMedia) {
            if ($capacityMedia.Count -gt 0 -and $pinned -notin $capacityMedia) {
                Write-Warning ("StorageTier {0} is not a capacity tier here (capacity: {1}); pinned volumes target {0} anyway and may fail." -f $pinned, ($capacityMedia -join ", "))
            }
        }

        # A lookup miss just means the template is created below (WS2019 needs explicit templates).
        $existingTiers = @(Get-StoragePool -FriendlyName "S2D on $ClusterName" -ErrorAction Stop | Get-StorageTier -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FriendlyName)
        $mirrorTemplateMedia = @()
        $nestedMirrorTemplateMedia = @()
        $nestedParityTemplateMedia = @()
        for ($m = 0; $m -lt $VolumeCount; $m++) {
            if ($volumeResiliency[$m] -eq "Mirror") {
                if ($pinnedFlags[$m]) { $mirrorTemplateMedia += $volumeTierMedia[$m] }
            } else {
                $nestedMirrorTemplateMedia += $volumeTierMedia[$m]
                if ($volumeResiliency[$m] -eq "NestedParity") { $nestedParityTemplateMedia += $volumeTierMedia[$m] }
            }
        }
        $mirrorTemplateMedia = @($mirrorTemplateMedia | Select-Object -Unique)
        $nestedMirrorTemplateMedia = @($nestedMirrorTemplateMedia | Select-Object -Unique)
        $nestedParityTemplateMedia = @($nestedParityTemplateMedia | Select-Object -Unique)
        foreach ($tierMedia in $mirrorTemplateMedia) {
            $templateName = "MirrorOn$TierMedia"
            if ($templateName -notin $existingTiers) {
                New-StorageTier -StoragePoolFriendlyName "S2D on $ClusterName" -FriendlyName $templateName -ResiliencySettingName Mirror -MediaType $tierMedia -NumberOfDataCopies 2
            }
        }
        foreach ($tierMedia in $nestedMirrorTemplateMedia) {
            $mirrorTierName = "NestedMirrorOn$TierMedia"
            if ($mirrorTierName -notin $existingTiers) {
                New-StorageTier -StoragePoolFriendlyName "S2D on $ClusterName" -FriendlyName $mirrorTierName -ResiliencySettingName Mirror -MediaType $tierMedia -NumberOfDataCopies 4
            }
        }
        foreach ($tierMedia in $nestedParityTemplateMedia) {
            $parityTierName = "NestedParityOn$TierMedia"
            if ($parityTierName -notin $existingTiers) {
                $paritySplat = @{
                    StoragePoolFriendlyName = "S2D on $ClusterName"
                    FriendlyName            = $parityTierName
                    ResiliencySettingName   = "Parity"
                    MediaType               = $tierMedia
                    NumberOfDataCopies      = 2
                    PhysicalDiskRedundancy  = 1
                    NumberOfGroups          = 1
                    FaultDomainAwareness    = "StorageScaleUnit"
                    ColumnIsolation         = "PhysicalDisk"
                }
                New-StorageTier @paritySplat
            }
        }

        $volumeNames = @()
        if ($VolumeCount -eq 1) {
            $volumeNames = @($VolumeName)
        } else {
            for ($i = 1; $i -le $VolumeCount; $i++) {
                $volumeNames += ("{0}_{1:D2}" -f $VolumeName, $i)
            }
        }
        for ($idx = 0; $idx -lt $volumeNames.Count; $idx++) {
            $name = $volumeNames[$idx]
            if (Get-VirtualDisk -FriendlyName $name -ErrorAction SilentlyContinue) {
                Write-S2DLog "Volume $name exists, skipping creation."
                continue
            }
            $volMedia = $volumeTierMedia[$idx]
            $volRes = $volumeResiliency[$idx]
            $sizeGiB = [math]::Round($volumeSizes[$idx] / 1GB, 2)
            Write-S2DLog "Volume $name ($volRes on $volMedia, $sizeGiB GiB)"
            if ($volRes -eq "Mirror") {
                if (-not $pinnedFlags[$idx]) {
                    New-Volume -StoragePoolFriendlyName "S2D on $ClusterName" -FriendlyName $name -FileSystem CSVFS_ReFS -Size $volumeSizes[$idx] -ResiliencySettingName Mirror | Out-Null
                } else {
                    New-Volume -StoragePoolFriendlyName "S2D on $ClusterName" -FriendlyName $name -FileSystem CSVFS_ReFS -StorageTierFriendlyNames "MirrorOn$volMedia" -StorageTierSizes $volumeSizes[$idx] | Out-Null
                }
            } elseif ($volRes -eq "NestedMirror") {
                New-Volume -StoragePoolFriendlyName "S2D on $ClusterName" -FriendlyName $name -FileSystem CSVFS_ReFS -StorageTierFriendlyNames "NestedMirrorOn$volMedia" -StorageTierSizes $volumeSizes[$idx] | Out-Null
            } else {
                $mirrorPart = [uint64][math]::Floor($volumeSizes[$idx] * ($NestedMirrorPercent / 100.0))
                $parityPart = $volumeSizes[$idx] - $mirrorPart
                New-Volume -StoragePoolFriendlyName "S2D on $ClusterName" -FriendlyName $name -FileSystem CSVFS_ReFS -StorageTierFriendlyNames "NestedMirrorOn$volMedia", "NestedParityOn$volMedia" -StorageTierSizes $mirrorPart, $parityPart | Out-Null
            }
        }
    }

    if ($PSCmdlet.ShouldProcess(($ClusterNodes -join ','), "SMB Multichannel constraints (StorageA/B only)")) {
        Write-S2DLog "SMB Multichannel constraints (StorageA/B only)"
        foreach ($n in $ClusterNodes) {
            $others = $ClusterNodes | Where-Object { $_ -ne $n }
            foreach ($o in $others) {
                Invoke-Command -ComputerName $n -ScriptBlock {
                    Get-SmbMultichannelConstraint -ErrorAction SilentlyContinue | Where-Object {$_.ServerName -eq $using:o} | Remove-SmbMultichannelConstraint -Confirm:$false -ErrorAction SilentlyContinue
                    New-SmbMultichannelConstraint -ServerName $using:o -InterfaceAlias "StorageA","StorageB" -Confirm:$false | Out-Null
                } -ArgumentList $o
            }
        }
    }

    if ($PSCmdlet.ShouldProcess($ClusterName, "Rename cluster networks")) {
        Write-S2DLog "Rename cluster networks - $ClusterName"
        $netA = @(Get-ClusterNetworkInterface | Where-Object {$_.Name -like "*StorageA*"} | ForEach-Object { $_.Network.Name } | Select-Object -Unique)
        if ($netA.Count -gt 1) { throw "Multiple cluster networks match *StorageA*: $($netA -join ', ')." }
        elseif ($netA.Count -eq 1) { (Get-ClusterNetwork -Name $netA[0]).Name = "StorageA" }
        $netB = @(Get-ClusterNetworkInterface | Where-Object {$_.Name -like "*StorageB*"} | ForEach-Object { $_.Network.Name } | Select-Object -Unique)
        if ($netB.Count -gt 1) { throw "Multiple cluster networks match *StorageB*: $($netB -join ', ')." }
        elseif ($netB.Count -eq 1) { (Get-ClusterNetwork -Name $netB[0]).Name = "StorageB" }
        $netM = @(Get-ClusterNetworkInterface | Where-Object {$_.Name -like "*Mgmt*"} | ForEach-Object { $_.Network.Name } | Select-Object -Unique)
        if ($netM.Count -gt 1) { throw "Multiple cluster networks match *Mgmt*: $($netM -join ', ')." }
        elseif ($netM.Count -eq 1) { (Get-ClusterNetwork -Name $netM[0]).Name = "Mgmt" }
    }

    Write-S2DLog "== Cluster - Finished $ClusterName =="
}
