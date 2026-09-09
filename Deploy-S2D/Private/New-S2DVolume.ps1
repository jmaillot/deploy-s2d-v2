function New-S2DVolume {
<#
.SYNOPSIS
New-Volume wrapper. Thin indirection so tests can mock volume creation:
Pester cannot generate a proxy for New-Volume directly (exotic
Storage-module parameter types break proxy generation).
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
        New-Volume @Parameters | Out-Null
    }
}
