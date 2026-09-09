BeforeAll {
    Import-Module "$PSScriptRoot/../../Deploy-S2D/Deploy-S2D.psm1" -Force
}

Describe 'Get-S2DVolumeEfficiency' {
    It 'rates classic mirror at 50%' {
        Get-S2DVolumeEfficiency -Resiliency Mirror | Should -Be 0.5
    }

    It 'rates nested mirror at 25%' {
        Get-S2DVolumeEfficiency -Resiliency NestedMirror | Should -Be 0.25
    }

    It 'looks up nested parity table values' {
        Get-S2DVolumeEfficiency -Resiliency NestedParity -CapacityDrivesPerServer 6 -NestedMirrorPercent 20 | Should -Be 0.368
        Get-S2DVolumeEfficiency -Resiliency NestedParity -CapacityDrivesPerServer 6 -NestedMirrorPercent 10 | Should -Be 0.391
        Get-S2DVolumeEfficiency -Resiliency NestedParity -CapacityDrivesPerServer 4 -NestedMirrorPercent 30 | Should -Be 0.326
        Get-S2DVolumeEfficiency -Resiliency NestedParity -CapacityDrivesPerServer 9 -NestedMirrorPercent 20 | Should -Be 0.375
    }

    It 'interpolates between mirror-percent columns' {
        [math]::Round((Get-S2DVolumeEfficiency -Resiliency NestedParity -CapacityDrivesPerServer 6 -NestedMirrorPercent 15), 4) | Should -Be 0.3795
    }

    It 'clamps drive counts below the table' {
        Get-S2DVolumeEfficiency -Resiliency NestedParity -CapacityDrivesPerServer 2 -NestedMirrorPercent 20 | Should -Be 0.341
    }
}

Describe 'Get-S2DCapacityMedia' {
    It 'returns empty when drives are unknown' {
        Get-S2DCapacityMedia -Drives @() | Should -Be @()
    }

    It 'treats SSD as cache with SSD plus SAS HDD only' {
        $drives = @(
            [pscustomobject]@{ Size = 800GB; MediaType = 'SSD'; BusType = 'SATA' }
            [pscustomobject]@{ Size = 4TB; MediaType = 'HDD'; BusType = 'SAS' }
        )
        Get-S2DCapacityMedia -Drives $drives | Should -Be @('HDD')
    }

    It 'promotes SSD to capacity with an NVMe cache tier' {
        $drives = @(
            [pscustomobject]@{ Size = 800GB; MediaType = 'SSD'; BusType = 'NVMe' }
            [pscustomobject]@{ Size = 800GB; MediaType = 'SSD'; BusType = 'SATA' }
            [pscustomobject]@{ Size = 4TB; MediaType = 'HDD'; BusType = 'SAS' }
        )
        Get-S2DCapacityMedia -Drives $drives | Should -Be @('SSD', 'HDD')
    }

    It 'handles single-media pools' {
        $ssdOnly = @([pscustomobject]@{ Size = 2TB; MediaType = 'SSD'; BusType = 'SATA' })
        Get-S2DCapacityMedia -Drives $ssdOnly | Should -Be @('SSD')
        $hddOnly = @([pscustomobject]@{ Size = 4TB; MediaType = 'HDD'; BusType = 'SAS' })
        Get-S2DCapacityMedia -Drives $hddOnly | Should -Be @('HDD')
    }
}

Describe 'Get-S2DCapacityReserve' {
    It 'takes the drive floor on small pools (2 nodes x largest HDD)' {
        $drives = @(
            [pscustomobject]@{ Size = 2TB; MediaType = 'HDD'; BusType = 'SAS' }
            [pscustomobject]@{ Size = 2TB; MediaType = 'HDD'; BusType = 'SAS' }
            [pscustomobject]@{ Size = 2TB; MediaType = 'HDD'; BusType = 'SAS' }
            [pscustomobject]@{ Size = 2TB; MediaType = 'HDD'; BusType = 'SAS' }
        )
        Get-S2DCapacityReserve -PoolFreeBytes 10TB -NodeCount 2 -ReservePercent 20 -Drives $drives | Should -Be 4TB
    }

    It 'takes the percent reserve on large pools' {
        $drives = @([pscustomobject]@{ Size = 2TB; MediaType = 'HDD'; BusType = 'SAS' })
        Get-S2DCapacityReserve -PoolFreeBytes 100TB -NodeCount 2 -ReservePercent 20 -Drives $drives | Should -Be 20TB
    }

    It 'reserves HDD only with SSD plus SAS and no dedicated cache' {
        $drives = @(
            [pscustomobject]@{ Size = 800GB; MediaType = 'SSD'; BusType = 'SATA' }
            [pscustomobject]@{ Size = 4TB; MediaType = 'HDD'; BusType = 'SAS' }
        )
        Get-S2DCapacityReserve -PoolFreeBytes 100TB -NodeCount 2 -ReservePercent 0 -Drives $drives | Should -Be ([uint64](2 * 4TB))
    }

    It 'reserves SSD plus HDD with an NVMe cache tier' {
        $drives = @(
            [pscustomobject]@{ Size = 800GB; MediaType = 'SSD'; BusType = 'NVMe' }
            [pscustomobject]@{ Size = 800GB; MediaType = 'SSD'; BusType = 'SATA' }
            [pscustomobject]@{ Size = 4TB; MediaType = 'HDD'; BusType = 'SAS' }
        )
        $expected = [uint64](2 * 800GB + 2 * 4TB)
        Get-S2DCapacityReserve -PoolFreeBytes 100TB -NodeCount 2 -ReservePercent 0 -Drives $drives | Should -Be $expected
    }

    It 'falls back to percent only when drives are unknown' {
        Get-S2DCapacityReserve -PoolFreeBytes 10TB -NodeCount 2 -ReservePercent 20 -Drives @() | Should -Be 2TB
    }

    It 'caps the reserve at free pool bytes' {
        $drives = @([pscustomobject]@{ Size = 8TB; MediaType = 'HDD'; BusType = 'SAS' })
        Get-S2DCapacityReserve -PoolFreeBytes 4TB -NodeCount 2 -ReservePercent 20 -Drives $drives | Should -Be 4TB
    }
}
