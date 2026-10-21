<#
.SYNOPSIS
Creates one of the five Quantaid VMs from the Packer-built base image.
Never overwrites an existing VM; to rebuild one, run vmrun deleteVM <path-to-its-.vmx> first.
#>
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("proxy", "frontend", "backend", "dns", "monitoring")]
    [string]$Role,

    [string]$BaseVmx = "$env:USERPROFILE\vmware\quantaid-base\quantaid-base.vmx",
    [string]$VmRoot = "$env:USERPROFILE\vmware",

    # Workstation's NAT network, re-subnetted to 192.168.111.0/24
    [string]$VmNet = "vmnet8"
)

$ErrorActionPreference = "Stop"

$targetDir = Join-Path $VmRoot "quantaid-$Role"
$targetVmx = Join-Path $targetDir "quantaid-$Role.vmx"

if (Test-Path $targetVmx) {
    Write-Error "Refusing to proceed: $targetVmx already exists. This script never overwrites an existing VM. To recreate it, delete it yourself first: vmrun deleteVM `"$targetVmx`""
    exit 1
}

if (-not (Test-Path $BaseVmx)) {
    Write-Error "Base image not found at $BaseVmx -- run 'packer build ubuntu.pkr.hcl' first."
    exit 1
}

Write-Host "Cloning $BaseVmx -> $targetVmx ..."
& vmrun clone $BaseVmx $targetVmx full "-cloneName=quantaid-$Role"
if ($LASTEXITCODE -ne 0) {
    Write-Error "vmrun clone failed (exit $LASTEXITCODE)"
    exit 1
}

Write-Host "Attaching to $VmNet ..."
$vmxContent = Get-Content $targetVmx
$vmxContent = $vmxContent -replace '^ethernet0\.connectionType.*', 'ethernet0.connectionType = "custom"'
if ($vmxContent -match '^ethernet0\.vnet') {
    $vmxContent = $vmxContent -replace '^ethernet0\.vnet.*', "ethernet0.vnet = `"$VmNet`""
} else {
    $vmxContent += "ethernet0.vnet = `"$VmNet`""
}
Set-Content -Path $targetVmx -Value $vmxContent

Write-Host "Starting $targetVmx ..."
& vmrun start $targetVmx nogui
if ($LASTEXITCODE -ne 0) {
    Write-Error "vmrun start failed (exit $LASTEXITCODE)"
    exit 1
}

Write-Host ""
Write-Host "Started. Once it's SSH-reachable, run (from WSL2):"
Write-Host "  cd ../ansible && ansible-playbook playbooks/$Role.yml"
