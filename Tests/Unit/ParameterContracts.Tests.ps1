BeforeAll {
    Import-Module "$PSScriptRoot/../../Deploy-S2D/Deploy-S2D.psm1" -Force
}

Describe 'Parameter contracts' {
    It 'NodePrep identity params are Mandatory' {
        $params = (Get-Command Start-S2DNodePrep).Parameters
        foreach ($n in @('StorageAIP', 'StorageBIP')) {
            $attr = $params[$n].Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] })
            $attr.Mandatory | Should -BeTrue
        }
    }

    It 'Cluster identity params are Mandatory' {
        $params = (Get-Command New-S2DCluster).Parameters
        foreach ($n in @('ClusterName', 'ClusterNodes', 'ClusterIP')) {
            $attr = $params[$n].Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] })
            $attr.Mandatory | Should -BeTrue
        }
    }

    It 'ClusterNodes requires exactly 2 nodes' {
        $cnt = (Get-Command New-S2DCluster).Parameters['ClusterNodes'].Attributes.Where({ $_ -is [System.Management.Automation.ValidateCountAttribute] })
        $cnt.MinLength | Should -Be 2
        $cnt.MaxLength | Should -Be 2
    }

    It 'AzStorageKey is SecureString' {
        (Get-Command New-S2DCluster).Parameters['AzStorageKey'].ParameterType |
            Should -Be ([System.Security.SecureString])
    }

    It 'shared code has no environment defaults' {
        $src = Get-Content "$PSScriptRoot/../../Deploy-S2D/Public/*.ps1" -Raw
        $src | Should -Not -Match '@\("Ethernet'
        $src | Should -Not -Match '="Ethernet'
        $src | Should -Not -Match '"CLUSTERS2D"'
        $src | Should -Not -Match '@\("HV1"'
        $src | Should -Not -Match 'FS01\\ClusterWitness'
    }

    It 'state-changing functions support ShouldProcess' {
        foreach ($n in @('Start-S2DNodePrep', 'New-S2DCluster', 'Start-S2DDeployment')) {
            (Get-Command $n).Parameters.Keys | Should -Contain 'WhatIf'
        }
    }

    It 'volume params carry v2 defaults and bounds' {
        $params = (Get-Command New-S2DCluster).Parameters
        $params['VolumeCount'].Attributes.Where({ $_ -is [System.Management.Automation.ValidateRangeAttribute] }).MaxRange | Should -Be 64
        $params['Resiliency'].Attributes.Where({ $_ -is [System.Management.Automation.ValidateSetAttribute] }).ValidValues | Should -Be @('Mirror', 'NestedMirror', 'NestedParity')
        $params['NestedMirrorPercent'].Attributes.Where({ $_ -is [System.Management.Automation.ValidateRangeAttribute] }).MinRange | Should -Be 10
        $params['StorageTier'].Attributes.Where({ $_ -is [System.Management.Automation.ValidateSetAttribute] }).ValidValues | Should -Be @('Auto', 'SSD', 'HDD')
        $params['VolumeCount'].ParameterType | Should -Be ([int])
        $params['Resiliency'].ParameterType | Should -Be ([string])
        $params['NestedMirrorPercent'].ParameterType | Should -Be ([int])
        $params['StorageTier'].ParameterType | Should -Be ([string[]])
    }

    It 'wrapper forwards v2 volume params' {
        $params = (Get-Command Start-S2DDeployment).Parameters
        foreach ($n in @('VolumeCount', 'Resiliency', 'NestedMirrorPercent', 'StorageTier')) {
            $params.Keys | Should -Contain $n
        }
    }
}
