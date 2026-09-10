BeforeAll {
    Import-Module "$PSScriptRoot/../../Deploy-S2D/Deploy-S2D.psm1" -Force
    # Pure helpers are dot-sourced into test scope and called directly:
    # InModuleScope wraps collection outputs in an extra array layer,
    # which breaks array assertions that otherwise render identically.
    foreach ($f in @('Get-S2DVolumeEfficiency', 'Get-S2DCapacityMedia', 'Get-S2DCapacityReserve', 'Get-S2DVolumeTierMap', 'Get-S2DVolumeResiliencyMap')) {
        . "$PSScriptRoot/../../Deploy-S2D/Private/$f.ps1"
    }
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

    It 'rates mirror 3-way on 3+ nodes' {
        Get-S2DVolumeEfficiency -Resiliency Mirror -NodeCount 3 | Should -Be (1.0 / 3.0)
        Get-S2DVolumeEfficiency -Resiliency Mirror -NodeCount 16 | Should -Be (1.0 / 3.0)
    }

    It 'rejects nested resiliency off 2 nodes' {
        { Get-S2DVolumeEfficiency -Resiliency NestedMirror -NodeCount 3 -ErrorAction Stop } | Should -Throw
        { Get-S2DVolumeEfficiency -Resiliency NestedParity -NodeCount 4 -NestedMirrorPercent 20 -ErrorAction Stop } | Should -Throw
    }

    It 'looks up dual parity by node count (hybrid column)' {
        Get-S2DVolumeEfficiency -Resiliency DualParity -NodeCount 4 | Should -Be 0.5
        Get-S2DVolumeEfficiency -Resiliency DualParity -NodeCount 6 | Should -Be 0.5
        Get-S2DVolumeEfficiency -Resiliency DualParity -NodeCount 7 | Should -Be 0.667
        Get-S2DVolumeEfficiency -Resiliency DualParity -NodeCount 11 | Should -Be 0.667
        Get-S2DVolumeEfficiency -Resiliency DualParity -NodeCount 12 | Should -Be 0.727
        Get-S2DVolumeEfficiency -Resiliency DualParity -NodeCount 16 | Should -Be 0.727
    }

    It 'looks up dual parity by node count (all-flash column)' {
        Get-S2DVolumeEfficiency -Resiliency DualParity -NodeCount 4 -AllFlash | Should -Be 0.5
        Get-S2DVolumeEfficiency -Resiliency DualParity -NodeCount 8 -AllFlash | Should -Be 0.667
        Get-S2DVolumeEfficiency -Resiliency DualParity -NodeCount 9 -AllFlash | Should -Be 0.75
        Get-S2DVolumeEfficiency -Resiliency DualParity -NodeCount 15 -AllFlash | Should -Be 0.75
        Get-S2DVolumeEfficiency -Resiliency DualParity -NodeCount 16 -AllFlash | Should -Be 0.8
    }

    It 'rejects dual parity below 4 nodes' {
        { Get-S2DVolumeEfficiency -Resiliency DualParity -NodeCount 2 -ErrorAction Stop } | Should -Throw
        { Get-S2DVolumeEfficiency -Resiliency DualParity -NodeCount 3 -ErrorAction Stop } | Should -Throw
        { Get-S2DVolumeEfficiency -Resiliency MirrorAcceleratedParity -NodeCount 3 -ErrorAction Stop } | Should -Throw
    }

    It 'blends mirror and parity for mirror-accelerated parity' {
        $eff = Get-S2DVolumeEfficiency -Resiliency MirrorAcceleratedParity -NodeCount 4 -NestedMirrorPercent 20
        [math]::Round($eff, 4) | Should -Be ([math]::Round(0.2 * (1.0 / 3.0) + 0.8 * 0.5, 4))
        $flash = Get-S2DVolumeEfficiency -Resiliency MirrorAcceleratedParity -NodeCount 16 -NestedMirrorPercent 20 -AllFlash
        [math]::Round($flash, 4) | Should -Be ([math]::Round(0.2 * (1.0 / 3.0) + 0.8 * 0.8, 4))
    }
}

Describe 'Get-S2DCapacityMedia' {
    It 'returns empty when drives are unknown' {
        @(Get-S2DCapacityMedia -Drives @()).Count | Should -Be 0
    }

    It 'treats SSD as cache with SSD plus SAS HDD only' {
        $drives = @(
            [pscustomobject]@{ Size = 800GB; MediaType = 'SSD'; BusType = 'SATA' }
            [pscustomobject]@{ Size = 4TB; MediaType = 'HDD'; BusType = 'SAS' }
        )
        (Get-S2DCapacityMedia -Drives $drives) -join ',' | Should -Be 'HDD'
    }

    It 'promotes SSD to capacity with an NVMe cache tier' {
        $drives = @(
            [pscustomobject]@{ Size = 800GB; MediaType = 'SSD'; BusType = 'NVMe' }
            [pscustomobject]@{ Size = 800GB; MediaType = 'SSD'; BusType = 'SATA' }
            [pscustomobject]@{ Size = 4TB; MediaType = 'HDD'; BusType = 'SAS' }
        )
        (Get-S2DCapacityMedia -Drives $drives) -join ',' | Should -Be 'SSD,HDD'
    }

    It 'handles single-media pools' {
        $ssdOnly = @([pscustomobject]@{ Size = 2TB; MediaType = 'SSD'; BusType = 'SATA' })
        (Get-S2DCapacityMedia -Drives $ssdOnly) -join ',' | Should -Be 'SSD'
        (Get-S2DCapacityMedia -Drives $ssdOnly)[0] | Should -Be 'SSD'
        $hddOnly = @([pscustomobject]@{ Size = 4TB; MediaType = 'HDD'; BusType = 'SAS' })
        (Get-S2DCapacityMedia -Drives $hddOnly) -join ',' | Should -Be 'HDD'
    }
}

Describe 'Get-S2DVolumeTierMap' {
    It 'broadcasts a single tier to all volumes' {
        (Get-S2DVolumeTierMap -VolumeCount 2 -StorageTier @('Auto') -DefaultMedia 'HDD') -join ',' | Should -Be 'HDD,HDD'
    }

    It 'maps one tier per volume' {
        (Get-S2DVolumeTierMap -VolumeCount 2 -StorageTier @('SSD', 'HDD') -DefaultMedia 'HDD') -join ',' | Should -Be 'SSD,HDD'
    }

    It 'resolves Auto entries to the default media' {
        (Get-S2DVolumeTierMap -VolumeCount 2 -StorageTier @('SSD', 'Auto') -DefaultMedia 'HDD') -join ',' | Should -Be 'SSD,HDD'
    }

    It 'throws when the count matches neither 1 nor VolumeCount' {
        { Get-S2DVolumeTierMap -VolumeCount 2 -StorageTier @('SSD', 'HDD', 'SSD') -DefaultMedia 'HDD' } | Should -Throw '*match VolumeCount*'
    }

    It 'returns an indexable array for a single volume (no scalar unroll)' {
        (Get-S2DVolumeTierMap -VolumeCount 1 -StorageTier @('Auto') -DefaultMedia 'HDD')[0] | Should -Be 'HDD'
    }
}

Describe 'Get-S2DVolumeResiliencyMap' {
    It 'broadcasts a single resiliency to all volumes' {
        (Get-S2DVolumeResiliencyMap -VolumeCount 2 -Resiliency @('Mirror')) -join ',' | Should -Be 'Mirror,Mirror'
    }

    It 'maps one resiliency per volume' {
        (Get-S2DVolumeResiliencyMap -VolumeCount 2 -Resiliency @('Mirror', 'NestedParity')) -join ',' | Should -Be 'Mirror,NestedParity'
    }

    It 'throws when the count matches neither 1 nor VolumeCount' {
        { Get-S2DVolumeResiliencyMap -VolumeCount 2 -Resiliency @('Mirror', 'NestedParity', 'Mirror') } | Should -Throw '*match VolumeCount*'
    }

    It 'returns an indexable array for a single volume (no scalar unroll)' {
        (Get-S2DVolumeResiliencyMap -VolumeCount 1 -Resiliency @('Mirror'))[0] | Should -Be 'Mirror'
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
