BeforeAll {
    Import-Module "$PSScriptRoot/../../Deploy-S2D/Deploy-S2D.psm1" -Force
}

Describe 'Deploy-S2D module' {
    It 'has a valid manifest' {
        { Test-ModuleManifest "$PSScriptRoot/../../Deploy-S2D/Deploy-S2D.psd1" -ErrorAction Stop } | Should -Not -Throw
    }

    It 'exports exactly the three public functions' {
        $names = (Get-Command -Module Deploy-S2D).Name | Sort-Object
        $names | Should -Be @('New-S2DCluster', 'Start-S2DDeployment', 'Start-S2DNodePrep')
    }

    It 'keeps helpers private' {
        $names = (Get-Command -Module Deploy-S2D).Name
        foreach ($h in @('Write-S2DLog', 'Select-S2DNic', 'Get-S2DPoolableDisk', 'Get-S2DPoolDisk', 'Get-S2DVolumeEfficiency', 'Get-S2DCapacityReserve')) {
            $names | Should -Not -Contain $h
        }
    }
}
