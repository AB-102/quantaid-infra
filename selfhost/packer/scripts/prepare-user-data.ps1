<#
.SYNOPSIS
Generates http/user-data from http/user-data.template with your SSH public key and a password hash.

.EXAMPLE
.\scripts\prepare-user-data.ps1 -SshPublicKeyPath "$env:USERPROFILE\.ssh\id_ed25519.pub" -PasswordHash '$6$...'
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$SshPublicKeyPath,

    [Parameter(Mandatory = $true)]
    [string]$PasswordHash
)

$ErrorActionPreference = "Stop"

$templatePath = Join-Path $PSScriptRoot "..\http\user-data.template"
$outputPath = Join-Path $PSScriptRoot "..\http\user-data"

$sshPublicKey = (Get-Content $SshPublicKeyPath -Raw).Trim()

# .Replace() is literal; -replace would read the $ in crypt hashes as regex backreferences
$content = Get-Content $templatePath -Raw
$content = $content.Replace('__ANB_SSH_PUBLIC_KEY__', $sshPublicKey)
$content = $content.Replace('__ANB_PASSWORD_HASH__', $PasswordHash)
Set-Content -Path $outputPath -Value $content -NoNewline

Write-Host "Wrote $outputPath"
