[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$NoProfileUpdate,
    [switch]$Force
)

Set-StrictMode -Version Latest

$source = Join-Path -Path $PSScriptRoot -ChildPath 'src/NewProjectWizard'
$destinationRoot = Join-Path -Path $HOME -ChildPath 'Documents/PowerShell/Modules/NewProjectWizard'
$destination = Join-Path -Path $destinationRoot -ChildPath '0.1.0'

if (-not (Test-Path -LiteralPath $source)) {
    throw "Module source not found at '$source'."
}

if ((Test-Path -LiteralPath $destination) -and -not $Force) {
    throw "Module destination already exists at '$destination'. Re-run with -Force to overwrite it."
}

if ($PSCmdlet.ShouldProcess($destination, 'Install NewProjectWizard module')) {
    if (Test-Path -LiteralPath $destination) {
        Remove-Item -LiteralPath $destination -Recurse -Force
    }

    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $source 'NewProjectWizard.psm1') -Destination $destination -Force
    Copy-Item -LiteralPath (Join-Path $source 'NewProjectWizard.psd1') -Destination $destination -Force
    Write-Host "Installed NewProjectWizard to $destination" -ForegroundColor Green
}

if ($NoProfileUpdate) {
    Write-Host 'Skipped PowerShell profile update.' -ForegroundColor Yellow
    return
}

$profilePath = $PROFILE.CurrentUserCurrentHost
$snippet = @'

# New Project Wizard
Import-Module NewProjectWizard
Set-Alias newproj New-Project
'@

$shouldUpdateProfile = Read-Host -Prompt "Add newproj alias to '$profilePath'? (Y/n)"
if ($shouldUpdateProfile -match '^(n|no)$') {
    Write-Host 'Skipped PowerShell profile update.' -ForegroundColor Yellow
    return
}

if ($PSCmdlet.ShouldProcess($profilePath, 'Add newproj alias to PowerShell profile')) {
    $profileFolder = Split-Path -Parent $profilePath
    if (-not (Test-Path -LiteralPath $profileFolder)) {
        New-Item -ItemType Directory -Path $profileFolder -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $profilePath)) {
        New-Item -ItemType File -Path $profilePath -Force | Out-Null
    }

    $profileContent = Get-Content -LiteralPath $profilePath -Raw
    if ($profileContent -notmatch 'Set-Alias\s+newproj\s+New-Project') {
        Add-Content -LiteralPath $profilePath -Value $snippet
        Write-Host 'Added newproj alias to PowerShell profile.' -ForegroundColor Green
    }
    else {
        Write-Host 'PowerShell profile already contains a newproj alias.' -ForegroundColor Yellow
    }
}
