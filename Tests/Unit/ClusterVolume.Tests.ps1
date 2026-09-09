# New-S2DCluster volume path with cluster/storage cmdlets mocked.
# Covers Auto sizing math, tier template ensure-or-skip, per-volume
# creation calls, and the Fixed footprint throw. Pure helpers have
# their own unit tests; this suite pins the wiring between them.
#
# Note: volume creation is captured through the New-S2DVolume test seam
# ($script:S2DCaptureVolumes in module state). External cmdlets use Mock.
BeforeAll {
    Import-Module "$PSScriptRoot/../../Deploy-S2D/Deploy-S2D.psm1" -Force

    # The runner image lacks Failover-Clustering cmdlets. Define global
    # stubs for anything missing so Mock -ModuleName can attach; mocks
    # replace them entirely, so no real host is ever touched.
    $externals = @(
        'Test-Cluster', 'Get-Cluster', 'Get-ClusterNode', 'Set-ClusterQuorum',
        'Enable-ClusterS2D', 'Get-StoragePool', 'Get-VirtualDisk', 'New-Volume',
        'Get-StorageTier', 'New-StorageTier', 'Get-ClusterNetworkInterface',
        'Add-Content'
    )
    foreach ($e in $externals) {
        if (-not (Get-Command $e -ErrorAction SilentlyContinue)) {
            New-Item -Path "function:Global:$e" -Value {} -Force | Out-Null
        }
    }

    Mock -ModuleName Deploy-S2D Add-Content -MockWith {}
    Mock -ModuleName Deploy-S2D Test-Cluster -MockWith {}
    Mock -ModuleName Deploy-S2D Test-Path -MockWith { $true }
    Mock -ModuleName Deploy-S2D Test-Connection -MockWith { $false }
    Mock -ModuleName Deploy-S2D Test-WSMan -MockWith { $true }
    Mock -ModuleName Deploy-S2D Get-Cluster -MockWith { [pscustomobject]@{ Name = 'X' } }
    Mock -ModuleName Deploy-S2D Get-ClusterNode -MockWith {
        [pscustomobject]@{ Name = 'Y' }
        [pscustomobject]@{ Name = 'Z' }
    }
    Mock -ModuleName Deploy-S2D Set-ClusterQuorum -MockWith {}
    Mock -ModuleName Deploy-S2D Get-VirtualDisk -MockWith {}
    Mock -ModuleName Deploy-S2D Get-StorageTier -MockWith {}
    Mock -ModuleName Deploy-S2D Get-ClusterNetworkInterface -MockWith {}
    Mock -ModuleName Deploy-S2D Invoke-Command -MockWith {}
    Mock -ModuleName Deploy-S2D New-StorageTier -MockWith {}

    function script:Reset-VolumeCapture {
        & (Get-Module Deploy-S2D) {
            $script:S2DCaptureVolumes = [System.Collections.ArrayList]::new()
        }
    }

    function script:Get-VolumeCapture {
        & (Get-Module Deploy-S2D) { ,$script:S2DCaptureVolumes }
    }
}

Describe 'Cluster volumes Auto Mirror (mocked)' {
    BeforeAll {
        # 32 TB free, 4x4 TB SAS per pool: floor 2x4 TB = 8 TB wins over 20%.
        Mock -ModuleName Deploy-S2D Get-StoragePool -MockWith {
            [pscustomobject]@{ Size = 32TB; AllocatedSize = 0; FriendlyName = 'S2D on X' }
        }
        Mock -ModuleName Deploy-S2D Get-S2DPoolDisk -MockWith {
            1..4 | ForEach-Object {
                [pscustomobject]@{ FriendlyName = "Disk$_"; MediaType = 'HDD'; BusType = 'SAS'; Size = 4TB }
            }
        }
    }

    It 'creates one 12 TB classic mirror volume and no tier templates' {
        # (32 - 8) x 50% = 12 TB.
        Reset-VolumeCapture
        { New-S2DCluster -ClusterName X -ClusterNodes Y,Z -ClusterIP 192.168.1.240 -FileShareWitness '\\S\W$' -Confirm:$false } |
            Should -Not -Throw
        Should -Invoke -ModuleName Deploy-S2D -CommandName New-StorageTier -Times 0 -Exactly
        $calls = Get-VolumeCapture
        $calls.Count | Should -Be 1
        $calls[0].Size | Should -Be 12TB
        $calls[0].ResiliencySettingName | Should -Be 'Mirror'
    }

    It 'pins a Mirror volume through a MirrorOn tier template' {
        Reset-VolumeCapture
        { New-S2DCluster -ClusterName X -ClusterNodes Y,Z -ClusterIP 192.168.1.240 -FileShareWitness '\\S\W$' -StorageTier HDD -Confirm:$false } |
            Should -Not -Throw
        Should -Invoke -ModuleName Deploy-S2D -CommandName New-StorageTier -Times 1 -Exactly -ParameterFilter {
            $FriendlyName -eq 'MirrorOnHDD' -and $NumberOfDataCopies -eq 2
        }
        $calls = Get-VolumeCapture
        $calls.Count | Should -Be 1
        $calls[0].Size | Should -Be 12TB
        $calls[0].StorageTierFriendlyNames | Should -Be 'MirrorOnHDD'
    }
}

Describe 'Cluster volumes Auto NestedParity x2 mixed tiers (mocked)' {
    BeforeAll {
        # 36 TB free (2x1 TB SSD + 4x4 TB SAS, 2 nodes): HDD-only floor 8 TB.
        Mock -ModuleName Deploy-S2D Get-StoragePool -MockWith {
            [pscustomobject]@{ Size = 36TB; AllocatedSize = 0; FriendlyName = 'S2D on X' }
        }
        Mock -ModuleName Deploy-S2D Get-S2DPoolDisk -MockWith {
            1..2 | ForEach-Object {
                [pscustomobject]@{ FriendlyName = "Ssd$_"; MediaType = 'SSD'; BusType = 'SATA'; Size = 1TB }
            }
            1..4 | ForEach-Object {
                [pscustomobject]@{ FriendlyName = "Hdd$_"; MediaType = 'HDD'; BusType = 'SAS'; Size = 4TB }
            }
        }
    }

    It 'creates two parity volumes on their pinned tiers with split tiers' {
        Reset-VolumeCapture
        { New-S2DCluster -ClusterName X -ClusterNodes Y,Z -ClusterIP 192.168.1.240 -FileShareWitness '\\S\W$' -VolumeName CSV -VolumeCount 2 -StorageTier SSD,HDD -Resiliency NestedParity -Confirm:$false } |
            Should -Not -Throw
        Should -Invoke -ModuleName Deploy-S2D -CommandName New-StorageTier -Times 4 -Exactly
        $calls = Get-VolumeCapture
        $calls.Count | Should -Be 2
        $calls[0].FriendlyName | Should -Be 'CSV_01'
        $calls[0].StorageTierFriendlyNames | Should -Be @('NestedMirrorOnSSD', 'NestedParityOnSSD')
        $calls[1].FriendlyName | Should -Be 'CSV_02'
        $calls[1].StorageTierFriendlyNames | Should -Be @('NestedMirrorOnHDD', 'NestedParityOnHDD')
        $calls[0].Size | Should -BeGreaterThan 4.5TB
        $calls[0].Size | Should -BeLessThan 5TB
        $calls[0].Size | Should -Be $calls[1].Size
        ($calls[0].StorageTierSizes[0] + $calls[0].StorageTierSizes[1]) | Should -Be $calls[0].Size
    }

    It 'skips template creation when templates already exist' {
        Mock -ModuleName Deploy-S2D Get-StorageTier -MockWith {
            [pscustomobject]@{ FriendlyName = 'NestedMirrorOnSSD' }
            [pscustomobject]@{ FriendlyName = 'NestedParityOnSSD' }
            [pscustomobject]@{ FriendlyName = 'NestedMirrorOnHDD' }
            [pscustomobject]@{ FriendlyName = 'NestedParityOnHDD' }
        }
        Reset-VolumeCapture
        { New-S2DCluster -ClusterName X -ClusterNodes Y,Z -ClusterIP 192.168.1.240 -FileShareWitness '\\S\W$' -VolumeName CSV -VolumeCount 2 -StorageTier SSD,HDD -Resiliency NestedParity -Confirm:$false } |
            Should -Not -Throw
        Should -Invoke -ModuleName Deploy-S2D -CommandName New-StorageTier -Times 0 -Exactly
        (Get-VolumeCapture).Count | Should -Be 2
    }
}

Describe 'Cluster volumes Fixed footprint guard (mocked)' {
    BeforeAll {
        Mock -ModuleName Deploy-S2D Get-StoragePool -MockWith {
            [pscustomobject]@{ Size = 32TB; AllocatedSize = 0; FriendlyName = 'S2D on X' }
        }
        Mock -ModuleName Deploy-S2D Get-S2DPoolDisk -MockWith {
            1..4 | ForEach-Object {
                [pscustomobject]@{ FriendlyName = "Disk$_"; MediaType = 'HDD'; BusType = 'SAS'; Size = 4TB }
            }
        }
    }

    It 'throws before creating anything when footprints exceed free space' {
        # 2 x 10 TB mirror = 40 TB footprint + 8 TB reserve > 32 TB free.
        Reset-VolumeCapture
        { New-S2DCluster -ClusterName X -ClusterNodes Y,Z -ClusterIP 192.168.1.240 -FileShareWitness '\\S\W$' -VolumeCount 2 -SizingMode Fixed -VolumeSize '10TB' -Confirm:$false -ErrorAction Stop } |
            Should -Throw '*footprint*'
        (Get-VolumeCapture).Count | Should -Be 0
    }
}
