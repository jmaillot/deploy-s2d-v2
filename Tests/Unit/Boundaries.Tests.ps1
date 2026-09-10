BeforeAll {
    Import-Module "$PSScriptRoot/../../Deploy-S2D/Deploy-S2D.psm1" -Force
}

Describe 'New-S2DCluster boundaries' {
    It 'throws when FileShare witness is missing' {
        { New-S2DCluster -ClusterName X -ClusterNodes Y,Z -ClusterIP 192.168.1.240 -ErrorAction Stop } |
            Should -Throw '*FileShareWitness*'
    }

    It 'throws when Cloud credentials are missing' {
        { New-S2DCluster -ClusterName X -ClusterNodes Y,Z -ClusterIP 192.168.1.240 -WitnessType Cloud -AzStorageAccount 'acc' -ErrorAction Stop } |
            Should -Throw '*AzStorageKey*'
    }

    It 'throws when Fixed volume size is missing' {
        { New-S2DCluster -ClusterName X -ClusterNodes Y,Z -ClusterIP 192.168.1.240 -FileShareWitness '\\S\W$' -SizingMode Fixed -ErrorAction Stop } |
            Should -Throw '*VolumeSize*'
    }

    It 'throws when Fixed volume size is unparseable' {
        { New-S2DCluster -ClusterName X -ClusterNodes Y,Z -ClusterIP 192.168.1.240 -FileShareWitness '\\S\W$' -SizingMode Fixed -VolumeSize 'potato' -ErrorAction Stop } |
            Should -Throw '*Unparseable*'
    }

    It 'throws when StorageTier count matches neither 1 nor VolumeCount' {
        { New-S2DCluster -ClusterName X -ClusterNodes Y,Z -ClusterIP 192.168.1.240 -FileShareWitness '\\S\W$' -VolumeCount 2 -StorageTier SSD,HDD,SSD -ErrorAction Stop } |
            Should -Throw '*match VolumeCount*'
    }

    It 'throws when Resiliency count matches neither 1 nor VolumeCount' {
        { New-S2DCluster -ClusterName X -ClusterNodes Y,Z -ClusterIP 192.168.1.240 -FileShareWitness '\\S\W$' -VolumeCount 2 -Resiliency Mirror,NestedParity,Mirror -ErrorAction Stop } |
            Should -Throw '*match VolumeCount*'
    }

    It 'throws when nested resiliency is used off 2 nodes' {
        { New-S2DCluster -ClusterName X -ClusterNodes Y,Z,W -ClusterIP 192.168.1.240 -FileShareWitness '\\S\W$' -Resiliency NestedParity -ErrorAction Stop } |
            Should -Throw '*exactly 2 nodes*'
        { New-S2DCluster -ClusterName X -ClusterNodes Y,Z,W -ClusterIP 192.168.1.240 -FileShareWitness '\\S\W$' -Resiliency NestedMirror -ErrorAction Stop } |
            Should -Throw '*exactly 2 nodes*'
    }

    It 'throws when dual-parity resiliency is used below 4 nodes' {
        { New-S2DCluster -ClusterName X -ClusterNodes Y,Z -ClusterIP 192.168.1.240 -FileShareWitness '\\S\W$' -Resiliency DualParity -ErrorAction Stop } |
            Should -Throw '*at least 4 nodes*'
        { New-S2DCluster -ClusterName X -ClusterNodes Y,Z,W -ClusterIP 192.168.1.240 -FileShareWitness '\\S\W$' -Resiliency MirrorAcceleratedParity -ErrorAction Stop } |
            Should -Throw '*at least 4 nodes*'
    }
}

Describe 'Start-S2DNodePrep boundaries' {
    It 'throws when storage IPs are identical' {
        { Start-S2DNodePrep -MgmtAdapters 'M1' -VMAdapters 'V1' -StorageA 'S1' -StorageB 'S2' -LiveMigrationAdapter 'L1' -StorageAIP 10.0.0.1 -StorageBIP 10.0.0.1 -ErrorAction Stop } |
            Should -Throw '*must differ*'
    }

    It 'throws when storage IPs share a subnet' {
        { Start-S2DNodePrep -MgmtAdapters 'M1' -VMAdapters 'V1' -StorageA 'S1' -StorageB 'S2' -LiveMigrationAdapter 'L1' -StorageAIP 10.0.0.1 -StorageBIP 10.0.0.2 -ErrorAction Stop } |
            Should -Throw '*different subnets*'
    }

    It 'throws when LiveMigrationIP equals a storage IP' {
        { Start-S2DNodePrep -MgmtAdapters 'M1' -VMAdapters 'V1' -StorageA 'S1' -StorageB 'S2' -LiveMigrationAdapter 'L1' -StorageAIP 10.0.0.1 -StorageBIP 10.0.1.1 -LiveMigrationIP 10.0.0.1 -ErrorAction Stop } |
            Should -Throw '*must differ from both storage IPs*'
    }
}
