# New-S2DCluster volume path with cluster/storage cmdlets mocked.
# Covers Auto sizing math, tier template ensure-or-skip, per-volume
# creation calls, and the Fixed footprint throw. Pure helpers have
# their own unit tests; this suite pins the wiring between them.
BeforeAll {
    Import-Module "$PSScriptRoot/../../Deploy-S2D/Deploy-S2D.psm1" -Force

    # The runner image lacks Failover-Clustering cmdlets. Define global
    # stubs for anything missing so Mock -ModuleName can attach; mocks
    # replace them entirely, so no real host is ever touched.
    $externals = @(
        'Test-Cluster', 'Get-Cluster', 'Get-ClusterNode', 'Set-ClusterQuorum',
        'Enable-ClusterS2D', 'Get-StoragePool', 'Get-VirtualDisk',
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
    Mock -ModuleName Deploy-S2D New-S2DVolume -MockWith {}
    Mock -ModuleName Deploy-S2D New-StorageTier -MockWith {}
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
        { New-S2DCluster -ClusterName X -ClusterNodes Y,Z -ClusterIP 192.168.1.240 -FileShareWitness '\\S\W$' -Confirm:$false } |
            Should -Not -Throw
        Should -Invoke -ModuleName Deploy-S2D -CommandName New-S2DVolume -Times 1 -Exactly -ParameterFilter {
            $Parameters.Size -eq 12TB -and $Parameters.ResiliencySettingName -eq 'Mirror'
        }
        Should -Invoke -ModuleName Deploy-S2D -CommandName New-StorageTier -Times 0 -Exactly
    }

    It 'pins a Mirror volume through a MirrorOn tier template' {
        { New-S2DCluster -ClusterName X -ClusterNodes Y,Z -ClusterIP 192.168.1.240 -FileShareWitness '\\S\W$' -StorageTier HDD -Confirm:$false } |
            Should -Not -Throw
        Should -Invoke -ModuleName Deploy-S2D -CommandName New-StorageTier -Times 1 -Exactly -ParameterFilter {
            $FriendlyName -eq 'MirrorOnHDD' -and $NumberOfDataCopies -eq 2
        }
        Should -Invoke -ModuleName Deploy-S2D -CommandName New-S2DVolume -Times 1 -Exactly -ParameterFilter {
            $Parameters.Size -eq 12TB -and $Parameters.StorageTierFriendlyNames -eq 'MirrorOnHDD'
        }
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
        { New-S2DCluster -ClusterName X -ClusterNodes Y,Z -ClusterIP 192.168.1.240 -FileShareWitness '\\S\W$' -VolumeName CSV -VolumeCount 2 -StorageTier SSD,HDD -Resiliency NestedParity -Confirm:$false } |
            Should -Not -Throw
        Should -Invoke -ModuleName Deploy-S2D -CommandName New-StorageTier -Times 4 -Exactly
        Should -Invoke -ModuleName Deploy-S2D -CommandName New-S2DVolume -Times 1 -Exactly -ParameterFilter {
            $Parameters.FriendlyName -eq 'CSV_01' -and $Parameters.StorageTierFriendlyNames -contains 'NestedMirrorOnSSD' -and $Parameters.StorageTierFriendlyNames -contains 'NestedParityOnSSD'
        }
        Should -Invoke -ModuleName Deploy-S2D -CommandName New-S2DVolume -Times 1 -Exactly -ParameterFilter {
            $Parameters.FriendlyName -eq 'CSV_02' -and $Parameters.StorageTierFriendlyNames -contains 'NestedMirrorOnHDD' -and $Parameters.StorageTierFriendlyNames -contains 'NestedParityOnHDD'
        }
        Should -Invoke -ModuleName Deploy-S2D -CommandName New-S2DVolume -Times 2 -Exactly -ParameterFilter {
            $Parameters.Size -gt 5TB -and $Parameters.Size -lt 5.5TB -and ($Parameters.StorageTierSizes[0] + $Parameters.StorageTierSizes[1]) -eq $Parameters.Size
        }
    }

    It 'skips template creation when templates already exist' {
        Mock -ModuleName Deploy-S2D Get-StorageTier -MockWith {
            [pscustomobject]@{ FriendlyName = 'NestedMirrorOnSSD' }
            [pscustomobject]@{ FriendlyName = 'NestedParityOnSSD' }
            [pscustomobject]@{ FriendlyName = 'NestedMirrorOnHDD' }
            [pscustomobject]@{ FriendlyName = 'NestedParityOnHDD' }
        }
        { New-S2DCluster -ClusterName X -ClusterNodes Y,Z -ClusterIP 192.168.1.240 -FileShareWitness '\\S\W$' -VolumeName CSV -VolumeCount 2 -StorageTier SSD,HDD -Resiliency NestedParity -Confirm:$false } |
            Should -Not -Throw
        Should -Invoke -ModuleName Deploy-S2D -CommandName New-StorageTier -Times 0 -Exactly
        Should -Invoke -ModuleName Deploy-S2D -CommandName New-S2DVolume -Times 2 -Exactly
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
        { New-S2DCluster -ClusterName X -ClusterNodes Y,Z -ClusterIP 192.168.1.240 -FileShareWitness '\\S\W$' -VolumeCount 2 -SizingMode Fixed -VolumeSize '10TB' -Confirm:$false -ErrorAction Stop } |
            Should -Throw '*footprint*'
        Should -Invoke -ModuleName Deploy-S2D -CommandName New-S2DVolume -Times 0 -Exactly
    }
}
