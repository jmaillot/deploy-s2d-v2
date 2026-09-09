function New-S2DVolume {
<#
.SYNOPSIS
New-Volume wrapper. Thin indirection so tests can capture volume creation:
Pester cannot generate a proxy for New-Volume directly (exotic
Storage-module parameter types break proxy generation), and module-scope
redefinition does not survive the call boundary.
.PARAMETER Parameters
Splat passed straight to New-Volume (pool, name, filesystem, size or
tiers, resiliency).
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Parameters
    )
    if ($PSCmdlet.ShouldProcess($Parameters.FriendlyName, "New-Volume")) {
        # Test seam: when the suite provides a capture list (module state),
        # record the splat instead of touching storage.
        if ($null -ne $script:S2DCaptureVolumes) {
            [void]$script:S2DCaptureVolumes.Add($Parameters)
        } else {
            New-Volume @Parameters | Out-Null
        }
    }
}
