Set-StrictMode -Version Latest

$script:SupportedProjectTypes = @(
    'Empty'
    'Node'
    'React'
    'Next.js'
    'Python'
    'Rust'
    'Go'
    '.NET'
)

$script:GitignoreTemplateMap = @{
    'Empty'   = @()
    'Node'    = @('Node.gitignore')
    'React'   = @('Node.gitignore')
    'Next.js' = @('Node.gitignore')
    'Python'  = @('Python.gitignore')
    'Rust'    = @('Rust.gitignore')
    'Go'      = @('Go.gitignore')
    '.NET'    = @('VisualStudio.gitignore')
}

function Write-NpwBanner {
    Write-Host ''
    Write-Host '==========================' -ForegroundColor Cyan
    Write-Host 'New Project Wizard' -ForegroundColor Cyan
    Write-Host '==========================' -ForegroundColor Cyan
    Write-Host ''
}

function Write-NpwStatus {
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    Write-Host "[..] $Message" -ForegroundColor Cyan
}

function Write-NpwSuccess {
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-NpwWarning {
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    Write-Host "[!!] $Message" -ForegroundColor Yellow
}

function Get-NpwConfigRoot {
    Join-Path -Path $HOME -ChildPath '.config/new-project-wizard'
}

function Get-NpwConfigPath {
    Join-Path -Path (Get-NpwConfigRoot) -ChildPath 'config.json'
}

function Get-NpwDefaultProjectsFolder {
    $candidate = Join-Path -Path $HOME -ChildPath 'Projects'
    return $candidate
}

function Get-NpwDefaultConfig {
    [ordered]@{
        defaultProjectsFolder      = Get-NpwDefaultProjectsFolder
        preferredLicense           = 'MIT'
        defaultGitHubVisibility    = 'private'
        openVSCode                 = $true
        initializeGit              = $true
        createInitialCommit        = $true
        downloadGitignoreTemplates = $true
        createAgentFiles           = $true
    }
}

function ConvertTo-NpwHashtable {
    param(
        [Parameter(Mandatory)]
        [object]$InputObject
    )

    $result = @{}
    foreach ($property in $InputObject.PSObject.Properties) {
        $result[$property.Name] = $property.Value
    }

    return $result
}

function Merge-NpwConfig {
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Defaults,

        [System.Collections.IDictionary]$UserConfig = @{}
    )

    $merged = [ordered]@{}
    foreach ($key in $Defaults.Keys) {
        $merged[$key] = $Defaults[$key]
    }

    foreach ($key in $UserConfig.Keys) {
        $merged[$key] = $UserConfig[$key]
    }

    return $merged
}

function Get-NpwConfig {
    param(
        [switch]$CreateIfMissing
    )

    $defaults = Get-NpwDefaultConfig
    $configPath = Get-NpwConfigPath

    if (-not (Test-Path -LiteralPath $configPath)) {
        if ($CreateIfMissing) {
            $configRoot = Split-Path -Parent $configPath
            if (-not (Test-Path -LiteralPath $configRoot)) {
                New-Item -ItemType Directory -Path $configRoot -Force | Out-Null
            }

            $defaults | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $configPath -Encoding utf8
        }

        return $defaults
    }

    try {
        $raw = Get-Content -LiteralPath $configPath -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return $defaults
        }

        $userConfig = ConvertTo-NpwHashtable -InputObject ($raw | ConvertFrom-Json -ErrorAction Stop)
        return Merge-NpwConfig -Defaults $defaults -UserConfig $userConfig
    }
    catch {
        throw "Failed to read configuration at '$configPath': $($_.Exception.Message)"
    }
}

function Test-NpwCommand {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $null -ne (Get-Command -Name $Name -ErrorAction SilentlyContinue)
}

function Test-NpwProjectName {
    param(
        [AllowEmptyString()]
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $false
    }

    if ($Name.Trim() -ne $Name) {
        return $false
    }

    $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
    foreach ($char in $invalidChars) {
        if ($Name.Contains($char)) {
            return $false
        }
    }

    return $Name -match '^[A-Za-z0-9][A-Za-z0-9._-]*$'
}

function ConvertTo-NpwPackageName {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $packageName = $Name.ToLowerInvariant() -replace '[^a-z0-9]+', '-'
    return $packageName.Trim('-')
}

function ConvertTo-NpwPythonPackageName {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $packageName = $Name.ToLowerInvariant() -replace '[^a-z0-9_]+', '_'
    $packageName = $packageName.Trim('_')
    if ($packageName -match '^[0-9]') {
        $packageName = "app_$packageName"
    }

    return $packageName
}

function Read-NpwInput {
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,

        [string]$Default,

        [scriptblock]$Validator,

        [string]$ValidationMessage = 'Invalid value.'
    )

    while ($true) {
        $label = if ([string]::IsNullOrWhiteSpace($Default)) { $Prompt } else { "$Prompt [$Default]" }
        $value = Read-Host -Prompt $label
        if ([string]::IsNullOrWhiteSpace($value)) {
            $value = $Default
        }

        if ($null -eq $Validator -or (& $Validator $value)) {
            return $value
        }

        Write-NpwWarning $ValidationMessage
    }
}

function Read-NpwYesNo {
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,

        [bool]$Default = $true
    )

    $suffix = if ($Default) { 'Y/n' } else { 'y/N' }
    while ($true) {
        $value = Read-Host -Prompt "$Prompt ($suffix)"
        if ([string]::IsNullOrWhiteSpace($value)) {
            return $Default
        }

        switch -Regex ($value.Trim()) {
            '^(y|yes)$' { return $true }
            '^(n|no)$' { return $false }
            default { Write-NpwWarning 'Please answer yes or no.' }
        }
    }
}

function Read-NpwMenu {
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,

        [Parameter(Mandatory)]
        [string[]]$Options,

        [string]$Default
    )

    Write-Host ''
    Write-Host $Prompt -ForegroundColor Cyan
    for ($index = 0; $index -lt $Options.Count; $index++) {
        Write-Host ("{0}) {1}" -f ($index + 1), $Options[$index])
    }

    while ($true) {
        $answer = Read-Host -Prompt '>'
        if ([string]::IsNullOrWhiteSpace($answer) -and -not [string]::IsNullOrWhiteSpace($Default)) {
            return $Default
        }

        $number = 0
        if ([int]::TryParse($answer, [ref]$number) -and $number -ge 1 -and $number -le $Options.Count) {
            return $Options[$number - 1]
        }

        $match = $Options | Where-Object { $_ -ieq $answer } | Select-Object -First 1
        if ($match) {
            return $match
        }

        Write-NpwWarning 'Choose a listed option by number or name.'
    }
}

function New-NpwSummary {
    [ordered]@{
        Completed      = New-Object System.Collections.Generic.List[string]
        Skipped        = New-Object System.Collections.Generic.List[string]
        NeedsAttention = New-Object System.Collections.Generic.List[string]
    }
}

function Add-NpwSummaryItem {
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Summary,

        [Parameter(Mandatory)]
        [ValidateSet('Completed', 'Skipped', 'NeedsAttention')]
        [string]$Bucket,

        [Parameter(Mandatory)]
        [string]$Message
    )

    $Summary[$Bucket].Add($Message) | Out-Null
}

function Show-NpwSummary {
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Summary,

        [Parameter(Mandatory)]
        [string]$ProjectPath
    )

    Write-Host ''
    Write-Host 'Project summary' -ForegroundColor Cyan
    Write-Host "Path: $ProjectPath"

    foreach ($bucket in @('Completed', 'Skipped', 'NeedsAttention')) {
        if ($Summary[$bucket].Count -eq 0) {
            continue
        }

        Write-Host ''
        $label = if ($bucket -eq 'NeedsAttention') { 'Needs attention' } else { $bucket }
        Write-Host $label -ForegroundColor $(if ($bucket -eq 'NeedsAttention') { 'Yellow' } elseif ($bucket -eq 'Skipped') { 'DarkGray' } else { 'Green' })
        foreach ($item in $Summary[$bucket]) {
            Write-Host "  - $item"
        }
    }
}

function Resolve-NpwProjectPath {
    param(
        [Parameter(Mandatory)]
        [string]$BasePath,

        [Parameter(Mandatory)]
        [string]$Name
    )

    $expandedBase = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($BasePath)
    return Join-Path -Path $expandedBase -ChildPath $Name
}

function Test-NpwDirectoryEmpty {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $true
    }

    $item = Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop | Select-Object -First 1
    return $null -eq $item
}

function New-NpwFile {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Content,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Summary,

        [string]$Description
    )

    if (Test-Path -LiteralPath $Path) {
        Add-NpwSummaryItem -Summary $Summary -Bucket Skipped -Message "$Description already exists"
        return
    }

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $Content | Set-Content -LiteralPath $Path -Encoding utf8
    Add-NpwSummaryItem -Summary $Summary -Bucket Completed -Message "Created $Description"
}

function Invoke-NpwCommand {
    param(
        [Parameter(Mandatory)]
        [string]$Command,

        [string[]]$Arguments = @(),

        [Parameter(Mandatory)]
        [string]$WorkingDirectory
    )

    Push-Location -LiteralPath $WorkingDirectory
    try {
        & $Command @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "'$Command $($Arguments -join ' ')' failed with exit code $LASTEXITCODE."
        }
    }
    finally {
        Pop-Location
    }
}

function Get-NpwGitUserName {
    if (-not (Test-NpwCommand -Name 'git')) {
        return $env:USERNAME
    }

    try {
        $name = & git config user.name 2>$null
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            return $name.Trim()
        }
    }
    catch {
    }

    return $env:USERNAME
}

function Get-NpwLicenseTemplate {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('MIT', 'Apache-2.0', 'GPL-3.0', 'BSD-3-Clause', 'Unlicense')]
        [string]$License,

        [Parameter(Mandatory)]
        [string]$Holder
    )

    $year = (Get-Date).Year
    switch ($License) {
        'MIT' {
            @"
MIT License

Copyright (c) $year $Holder

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"@
        }
        'Apache-2.0' {
            @"
Copyright $year $Holder

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
"@
        }
        'GPL-3.0' {
            @"
$Holder
Copyright (C) $year $Holder

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program. If not, see <https://www.gnu.org/licenses/>.
"@
        }
        'BSD-3-Clause' {
            @"
BSD 3-Clause License

Copyright (c) $year, $Holder
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the standard BSD 3-Clause
conditions are met.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES ARE DISCLAIMED.
"@
        }
        'Unlicense' {
            @"
This is free and unencumbered software released into the public domain.

Anyone is free to copy, modify, publish, use, compile, sell, or
distribute this software, either in source code form or as a compiled
binary, for any purpose, commercial or non-commercial, and by any
means.

For more information, please refer to <https://unlicense.org/>
"@
        }
    }
}

function Get-NpwFallbackGitignore {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectType
    )

    $common = @'
# Environment
.env
.env.*
!.env.example

# Editor and OS files
.DS_Store
Thumbs.db
.vscode/
!.vscode/extensions.json
*.swp

# Logs
*.log
'@

    $typeSpecific = switch ($ProjectType) {
        'Node' { "node_modules/`ndist/`ncoverage/" }
        'React' { "node_modules/`ndist/`nbuild/`ncoverage/" }
        'Next.js' { "node_modules/`n.next/`nout/`ncoverage/" }
        'Python' { ".venv/`n__pycache__/`n.pytest_cache/`n*.pyc`ndist/`nbuild/" }
        'Rust' { "target/`nCargo.lock" }
        'Go' { "bin/`n*.test`ncoverage.out" }
        '.NET' { "bin/`nobj/`n.vs/" }
        default { "" }
    }

    return ($common.TrimEnd() + "`n`n" + $typeSpecific.Trim() + "`n")
}

function Get-NpwGitignoreTemplate {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectType,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Config,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Summary
    )

    $templates = $script:GitignoreTemplateMap[$ProjectType]
    $contentParts = New-Object System.Collections.Generic.List[string]

    foreach ($template in $templates) {
        $cachePath = Join-Path -Path (Join-Path -Path (Get-NpwConfigRoot) -ChildPath 'gitignore-cache') -ChildPath $template
        $downloaded = $false

        if ($Config.downloadGitignoreTemplates) {
            try {
                $uri = "https://raw.githubusercontent.com/github/gitignore/main/$template"
                $remoteContent = Invoke-RestMethod -Uri $uri -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop
                $cacheRoot = Split-Path -Parent $cachePath
                if (-not (Test-Path -LiteralPath $cacheRoot)) {
                    New-Item -ItemType Directory -Path $cacheRoot -Force | Out-Null
                }

                $remoteContent | Set-Content -LiteralPath $cachePath -Encoding utf8
                $contentParts.Add($remoteContent.TrimEnd()) | Out-Null
                $downloaded = $true
            }
            catch {
                Add-NpwSummaryItem -Summary $Summary -Bucket NeedsAttention -Message "Could not download $template; using cache or fallback"
            }
        }

        if (-not $downloaded -and (Test-Path -LiteralPath $cachePath)) {
            $contentParts.Add((Get-Content -LiteralPath $cachePath -Raw).TrimEnd()) | Out-Null
        }
    }

    if ($contentParts.Count -eq 0) {
        $contentParts.Add((Get-NpwFallbackGitignore -ProjectType $ProjectType).TrimEnd()) | Out-Null
    }

    $commonLocal = @'

# Local secrets and machine files
.env
.env.*
!.env.example
.vscode/
!.vscode/extensions.json
'@

    return (($contentParts -join "`n`n") + $commonLocal + "`n")
}

function New-NpwReadmeContent {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectName,

        [string]$Description,

        [Parameter(Mandatory)]
        [string]$ProjectType
    )

    $summary = if ([string]::IsNullOrWhiteSpace($Description)) { 'TODO: Describe this project.' } else { $Description }
    @"
# $ProjectName

$summary

## Project Type

$ProjectType

## Getting Started

Update this section with setup, development, and test commands for the project.
"@
}

function New-NpwAgentFiles {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$ProjectName,

        [Parameter(Mandatory)]
        [string]$ProjectType,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Summary
    )

    $agents = @"
# Agent Instructions

This repository is intended to be maintained with Codex and compatible coding agents.

## Working Rules

- Read `CONTEXT.md` before changing domain language.
- Keep implementation changes scoped to the requested behavior.
- Prefer existing project conventions over introducing new tooling.
- Run the relevant tests or checks before finishing work.
- Do not rewrite history, delete user work, or make destructive Git changes without explicit approval.

## Project

- Name: $ProjectName
- Type: $ProjectType
"@

    $context = @"
# $ProjectName

$ProjectName is a software project bootstrapped by New Project Wizard.

## Language

Add project-specific domain terms here as they become clear. Keep this file as a glossary, not an implementation spec.
"@

    $adr = @"
# 0001. Record Architecture Decisions

Date: $(Get-Date -Format 'yyyy-MM-dd')

## Status

Accepted

## Context

This project should preserve important architecture decisions in a consistent place so future maintainers and coding agents can understand why choices were made.

## Decision

Architecture decisions that are hard to reverse, surprising without context, and based on meaningful trade-offs will be recorded in `docs/adr/`.

## Consequences

The repository has a lightweight decision trail without requiring every small implementation choice to become documentation.
"@

    $codex = @"
# Codex Notes

Use this folder for repository-local Codex notes, generated context, skill configuration, or workflow hints that should travel with the project.

Start with `AGENTS.md` and `CONTEXT.md` before changing code.
"@

    $copilot = @"
# Copilot Instructions

Follow the repository guidance in `AGENTS.md`. Preserve domain language in `CONTEXT.md`, keep changes scoped, and run relevant checks before completing work.
"@

    New-NpwFile -Path (Join-Path $ProjectPath 'AGENTS.md') -Content $agents -Summary $Summary -Description 'AGENTS.md'
    New-NpwFile -Path (Join-Path $ProjectPath 'CONTEXT.md') -Content $context -Summary $Summary -Description 'CONTEXT.md'
    New-NpwFile -Path (Join-Path $ProjectPath 'docs/adr/0001-record-architecture-decisions.md') -Content $adr -Summary $Summary -Description 'starter ADR'
    New-NpwFile -Path (Join-Path $ProjectPath '.codex/README.md') -Content $codex -Summary $Summary -Description '.codex/README.md'
    New-NpwFile -Path (Join-Path $ProjectPath '.github/copilot-instructions.md') -Content $copilot -Summary $Summary -Description '.github/copilot-instructions.md'
}

function Initialize-NpwEmptyProject {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$ProjectName,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Summary
    )

    Add-NpwSummaryItem -Summary $Summary -Bucket Completed -Message 'Initialized empty project'
}

function Initialize-NpwNodeProject {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$ProjectName,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Summary
    )

    $packageName = ConvertTo-NpwPackageName -Name $ProjectName
    $packageJson = [ordered]@{
        name        = $packageName
        version     = '0.1.0'
        private     = $true
        description = ''
        type        = 'module'
        scripts     = [ordered]@{
            start = 'node src/index.js'
        }
    } | ConvertTo-Json -Depth 5

    New-NpwFile -Path (Join-Path $ProjectPath 'package.json') -Content $packageJson -Summary $Summary -Description 'package.json'
    New-NpwFile -Path (Join-Path $ProjectPath 'src/index.js') -Content "console.log('Hello from $ProjectName');" -Summary $Summary -Description 'src/index.js'
    Add-NpwSummaryItem -Summary $Summary -Bucket Completed -Message 'Initialized Node project'
}

function Initialize-NpwReactProject {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$ProjectName,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Summary
    )

    $npmCommand = if (Test-NpwCommand -Name 'npm.cmd') { 'npm.cmd' } else { 'npm' }
    if (-not (Test-NpwCommand -Name $npmCommand)) {
        throw 'npm is required to initialize a React project.'
    }

    Invoke-NpwCommand -Command $npmCommand -Arguments @('create', 'vite@latest', '.', '--', '--template', 'react-ts') -WorkingDirectory $ProjectPath
    Add-NpwSummaryItem -Summary $Summary -Bucket Completed -Message 'Initialized React project with Vite'
}

function Initialize-NpwNextProject {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$ProjectName,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Summary
    )

    $npxCommand = if (Test-NpwCommand -Name 'npx.cmd') { 'npx.cmd' } else { 'npx' }
    if (-not (Test-NpwCommand -Name $npxCommand)) {
        throw 'npx is required to initialize a Next.js project.'
    }

    Invoke-NpwCommand -Command $npxCommand -Arguments @('create-next-app@latest', '.', '--ts', '--eslint', '--app', '--src-dir', '--no-tailwind', '--import-alias', '@/*', '--use-npm') -WorkingDirectory $ProjectPath
    Add-NpwSummaryItem -Summary $Summary -Bucket Completed -Message 'Initialized Next.js project'
}

function Initialize-NpwPythonProject {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$ProjectName,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Summary
    )

    $pythonCommand = if (Test-NpwCommand -Name 'py') { 'py' } elseif (Test-NpwCommand -Name 'python') { 'python' } else { $null }
    if ($null -eq $pythonCommand) {
        throw 'Python is required to initialize a Python project.'
    }

    $packageName = ConvertTo-NpwPythonPackageName -Name $ProjectName
    $pyproject = @"
[project]
name = "$ProjectName"
version = "0.1.0"
description = ""
readme = "README.md"
requires-python = ">=3.11"
dependencies = []

[build-system]
requires = ["setuptools>=68"]
build-backend = "setuptools.build_meta"
"@

    Invoke-NpwCommand -Command $pythonCommand -Arguments @('-m', 'venv', '.venv') -WorkingDirectory $ProjectPath
    New-NpwFile -Path (Join-Path $ProjectPath 'pyproject.toml') -Content $pyproject -Summary $Summary -Description 'pyproject.toml'
    New-NpwFile -Path (Join-Path $ProjectPath "src/$packageName/__init__.py") -Content '"""Project package."""' -Summary $Summary -Description "src/$packageName/__init__.py"
    Add-NpwSummaryItem -Summary $Summary -Bucket Completed -Message 'Initialized Python project'
}

function Initialize-NpwRustProject {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$ProjectName,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Summary
    )

    if (-not (Test-NpwCommand -Name 'cargo')) {
        throw 'cargo is required to initialize a Rust project.'
    }

    Invoke-NpwCommand -Command 'cargo' -Arguments @('init', '--bin', '.') -WorkingDirectory $ProjectPath
    Add-NpwSummaryItem -Summary $Summary -Bucket Completed -Message 'Initialized Rust project'
}

function Initialize-NpwGoProject {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$ProjectName,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Summary
    )

    if (-not (Test-NpwCommand -Name 'go')) {
        throw 'go is required to initialize a Go project.'
    }

    $moduleName = ConvertTo-NpwPackageName -Name $ProjectName
    Invoke-NpwCommand -Command 'go' -Arguments @('mod', 'init', $moduleName) -WorkingDirectory $ProjectPath
    New-NpwFile -Path (Join-Path $ProjectPath 'main.go') -Content "package main`n`nimport `"fmt`"`n`nfunc main() {`n`tfmt.Println(`"Hello from $ProjectName`")`n}" -Summary $Summary -Description 'main.go'
    Add-NpwSummaryItem -Summary $Summary -Bucket Completed -Message 'Initialized Go project'
}

function Initialize-NpwDotNetProject {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$ProjectName,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Summary,

        [string]$DotNetTemplate = 'console'
    )

    if (-not (Test-NpwCommand -Name 'dotnet')) {
        throw 'dotnet is required to initialize a .NET project.'
    }

    Invoke-NpwCommand -Command 'dotnet' -Arguments @('new', $DotNetTemplate, '--name', $ProjectName, '--output', '.') -WorkingDirectory $ProjectPath
    Add-NpwSummaryItem -Summary $Summary -Bucket Completed -Message "Initialized .NET project using '$DotNetTemplate'"
}

function Initialize-NpwProjectType {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Empty', 'Node', 'React', 'Next.js', 'Python', 'Rust', 'Go', '.NET')]
        [string]$ProjectType,

        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$ProjectName,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Summary,

        [string]$DotNetTemplate = 'console'
    )

    switch ($ProjectType) {
        'Empty' { Initialize-NpwEmptyProject -ProjectPath $ProjectPath -ProjectName $ProjectName -Summary $Summary }
        'Node' { Initialize-NpwNodeProject -ProjectPath $ProjectPath -ProjectName $ProjectName -Summary $Summary }
        'React' { Initialize-NpwReactProject -ProjectPath $ProjectPath -ProjectName $ProjectName -Summary $Summary }
        'Next.js' { Initialize-NpwNextProject -ProjectPath $ProjectPath -ProjectName $ProjectName -Summary $Summary }
        'Python' { Initialize-NpwPythonProject -ProjectPath $ProjectPath -ProjectName $ProjectName -Summary $Summary }
        'Rust' { Initialize-NpwRustProject -ProjectPath $ProjectPath -ProjectName $ProjectName -Summary $Summary }
        'Go' { Initialize-NpwGoProject -ProjectPath $ProjectPath -ProjectName $ProjectName -Summary $Summary }
        '.NET' { Initialize-NpwDotNetProject -ProjectPath $ProjectPath -ProjectName $ProjectName -Summary $Summary -DotNetTemplate $DotNetTemplate }
    }
}

function Initialize-NpwGit {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Summary,

        [bool]$CreateInitialCommit = $true
    )

    if (-not (Test-NpwCommand -Name 'git')) {
        Add-NpwSummaryItem -Summary $Summary -Bucket NeedsAttention -Message 'Git is not available; repository was not initialized'
        return
    }

    Invoke-NpwCommand -Command 'git' -Arguments @('init') -WorkingDirectory $ProjectPath
    Add-NpwSummaryItem -Summary $Summary -Bucket Completed -Message 'Initialized Git repository'

    if (-not $CreateInitialCommit) {
        Add-NpwSummaryItem -Summary $Summary -Bucket Skipped -Message 'Initial commit disabled'
        return
    }

    try {
        Invoke-NpwCommand -Command 'git' -Arguments @('add', '.') -WorkingDirectory $ProjectPath
        Invoke-NpwCommand -Command 'git' -Arguments @('commit', '-m', 'Initial commit') -WorkingDirectory $ProjectPath
        Add-NpwSummaryItem -Summary $Summary -Bucket Completed -Message 'Created initial commit'
    }
    catch {
        Add-NpwSummaryItem -Summary $Summary -Bucket NeedsAttention -Message "Initial commit failed: $($_.Exception.Message)"
    }
}

function Test-NpwGitRemoteExists {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [string]$RemoteName = 'origin'
    )

    try {
        Push-Location -LiteralPath $ProjectPath
        $remote = & git remote get-url $RemoteName 2>$null
        return -not [string]::IsNullOrWhiteSpace($remote)
    }
    finally {
        Pop-Location
    }
}

function Invoke-NpwGitHubCreate {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$ProjectName,

        [Parameter(Mandatory)]
        [ValidateSet('private', 'public')]
        [string]$Visibility,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Summary
    )

    if (-not (Test-NpwCommand -Name 'gh')) {
        Add-NpwSummaryItem -Summary $Summary -Bucket Skipped -Message 'GitHub CLI is unavailable'
        Add-NpwSummaryItem -Summary $Summary -Bucket NeedsAttention -Message "Manual GitHub command: gh repo create $ProjectName --$Visibility --source . --remote origin --push"
        return
    }

    if (Test-NpwGitRemoteExists -ProjectPath $ProjectPath -RemoteName 'origin') {
        Add-NpwSummaryItem -Summary $Summary -Bucket Skipped -Message 'Remote origin already exists'
        return
    }

    try {
        Invoke-NpwCommand -Command 'gh' -Arguments @('repo', 'create', $ProjectName, "--$Visibility", '--source', '.', '--remote', 'origin', '--push') -WorkingDirectory $ProjectPath
        Add-NpwSummaryItem -Summary $Summary -Bucket Completed -Message 'Created GitHub repository and pushed initial commit'
    }
    catch {
        Add-NpwSummaryItem -Summary $Summary -Bucket NeedsAttention -Message "GitHub repository creation failed: $($_.Exception.Message)"
    }
}

function Open-NpwVSCode {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Summary
    )

    if (-not (Test-NpwCommand -Name 'code')) {
        Add-NpwSummaryItem -Summary $Summary -Bucket NeedsAttention -Message 'VS Code command "code" is unavailable'
        return
    }

    try {
        Invoke-NpwCommand -Command 'code' -Arguments @('-n', '.') -WorkingDirectory $ProjectPath
        Add-NpwSummaryItem -Summary $Summary -Bucket Completed -Message 'Opened project in VS Code'
    }
    catch {
        Add-NpwSummaryItem -Summary $Summary -Bucket NeedsAttention -Message "Could not open VS Code: $($_.Exception.Message)"
    }
}

function Get-NpwProjectTypes {
    $script:SupportedProjectTypes
}

<#
.SYNOPSIS
Creates a new software project through a polished PowerShell wizard.

.DESCRIPTION
New-Project bootstraps a project directory, initializes a supported project type,
creates standard repository files, optionally creates Codex/agent files, initializes
Git, optionally creates a GitHub repository through gh, and opens VS Code.

.PARAMETER Name
Project name. If omitted, the wizard prompts for it.

.PARAMETER Type
Project type to create. If omitted, the wizard prompts for it.

.PARAMETER Path
Folder where the project directory should be created. Defaults to configuration.

.PARAMETER Description
README description.

.PARAMETER Force
Allow using an existing non-empty directory. Existing files are not deleted.

.EXAMPLE
New-Project

.EXAMPLE
New-Project -Name my-api -Type Node -Path C:\Users\me\Projects -NoGitHub -NoCode
#>
function New-Project {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [ValidateScript({ Test-NpwProjectName -Name $_ })]
        [string]$Name,

        [ValidateSet('Empty', 'Node', 'React', 'Next.js', 'Python', 'Rust', 'Go', '.NET')]
        [string]$Type,

        [string]$Path,

        [string]$Description,

        [ValidateSet('MIT', 'Apache-2.0', 'GPL-3.0', 'BSD-3-Clause', 'Unlicense')]
        [string]$License,

        [string]$LicenseHolder,

        [ValidateSet('private', 'public')]
        [string]$GitHubVisibility,

        [string]$DotNetTemplate,

        [switch]$NoGit,

        [switch]$NoInitialCommit,

        [switch]$NoCode,

        [switch]$NoGitHub,

        [switch]$CreateGitHub,

        [switch]$NoAgentFiles,

        [switch]$NoLicense,

        [switch]$Force
    )

    $config = Get-NpwConfig -CreateIfMissing:(-not $WhatIfPreference)
    $summary = New-NpwSummary

    Write-NpwBanner

    if ([string]::IsNullOrWhiteSpace($Name)) {
        $Name = Read-NpwInput -Prompt 'Project name' -Validator { param($value) Test-NpwProjectName -Name $value } -ValidationMessage 'Use letters, numbers, dots, underscores, or hyphens. Start with a letter or number.'
    }

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = Read-NpwInput -Prompt 'Create in' -Default $config.defaultProjectsFolder -Validator { param($value) -not [string]::IsNullOrWhiteSpace($value) } -ValidationMessage 'Enter a folder path.'
    }

    if ([string]::IsNullOrWhiteSpace($Type)) {
        $Type = Read-NpwMenu -Prompt 'Project type:' -Options $script:SupportedProjectTypes -Default 'Node'
    }

    if ([string]::IsNullOrWhiteSpace($Description)) {
        $Description = Read-NpwInput -Prompt 'Description' -Default ''
    }

    $createLicense = -not $NoLicense
    if ($createLicense -and -not $PSBoundParameters.ContainsKey('License')) {
        $createLicense = Read-NpwYesNo -Prompt 'Create a LICENSE file?' -Default $true
    }

    $licenseId = if ($PSBoundParameters.ContainsKey('License')) { $License } else { $config.preferredLicense }
    $licenseHolder = if ($PSBoundParameters.ContainsKey('LicenseHolder')) { $LicenseHolder } else { $null }
    if ($createLicense) {
        $licenseOptions = @('MIT', 'Apache-2.0', 'GPL-3.0', 'BSD-3-Clause', 'Unlicense')
        if (-not $PSBoundParameters.ContainsKey('License')) {
            $licenseId = Read-NpwMenu -Prompt 'License:' -Options $licenseOptions -Default $config.preferredLicense
        }

        if ([string]::IsNullOrWhiteSpace($licenseHolder)) {
            $licenseHolder = Read-NpwInput -Prompt 'Copyright holder' -Default (Get-NpwGitUserName)
        }
    }

    $createAgentFiles = (-not $NoAgentFiles) -and [bool]$config.createAgentFiles
    if ($createAgentFiles -and -not $PSBoundParameters.ContainsKey('NoAgentFiles')) {
        $createAgentFiles = Read-NpwYesNo -Prompt 'Create Codex/agent files?' -Default $true
    }

    $openCode = (-not $NoCode) -and [bool]$config.openVSCode
    if (-not $NoCode -and -not $PSBoundParameters.ContainsKey('NoCode')) {
        $openCode = Read-NpwYesNo -Prompt 'Open VS Code when finished?' -Default ([bool]$config.openVSCode)
    }

    $createGitHub = [bool]$CreateGitHub
    if (-not $CreateGitHub -and -not $NoGitHub -and (Test-NpwCommand -Name 'gh')) {
        $createGitHub = Read-NpwYesNo -Prompt 'Create GitHub repository?' -Default $false
    }
    elseif (-not $NoGitHub) {
        Add-NpwSummaryItem -Summary $summary -Bucket Skipped -Message 'GitHub prompt skipped because gh is unavailable'
    }

    $githubVisibility = if ($PSBoundParameters.ContainsKey('GitHubVisibility')) { $GitHubVisibility } else { $config.defaultGitHubVisibility }
    if ($createGitHub) {
        if (-not $PSBoundParameters.ContainsKey('GitHubVisibility')) {
            $githubVisibility = Read-NpwMenu -Prompt 'GitHub visibility:' -Options @('private', 'public') -Default $config.defaultGitHubVisibility
        }
    }

    if ([string]::IsNullOrWhiteSpace($DotNetTemplate)) {
        $DotNetTemplate = 'console'
    }

    if ($Type -eq '.NET') {
        if (-not $PSBoundParameters.ContainsKey('DotNetTemplate')) {
            $DotNetTemplate = Read-NpwInput -Prompt '.NET template' -Default 'console' -Validator { param($value) -not [string]::IsNullOrWhiteSpace($value) }
        }
    }

    $projectPath = Resolve-NpwProjectPath -BasePath $Path -Name $Name
    $exists = Test-Path -LiteralPath $projectPath
    if ($exists -and -not (Test-NpwDirectoryEmpty -Path $projectPath) -and -not $Force) {
        throw "Target directory '$projectPath' already exists and is not empty. Use -Force to proceed without deleting existing files."
    }

    if ($exists -and (Test-NpwDirectoryEmpty -Path $projectPath)) {
        $useExisting = Read-NpwYesNo -Prompt "Directory '$projectPath' already exists and is empty. Use it?" -Default $true
        if (-not $useExisting) {
            throw 'Project creation cancelled.'
        }
    }

    if (-not $PSCmdlet.ShouldProcess($projectPath, 'Create new project')) {
        Add-NpwSummaryItem -Summary $summary -Bucket Skipped -Message 'WhatIf: project creation skipped'
        Show-NpwSummary -Summary $summary -ProjectPath $projectPath
        return
    }

    Write-NpwStatus "Creating project at $projectPath"
    if (-not (Test-Path -LiteralPath $projectPath)) {
        New-Item -ItemType Directory -Path $projectPath -Force | Out-Null
    }

    Initialize-NpwProjectType -ProjectType $Type -ProjectPath $projectPath -ProjectName $Name -Summary $summary -DotNetTemplate $DotNetTemplate

    New-NpwFile -Path (Join-Path $projectPath 'README.md') -Content (New-NpwReadmeContent -ProjectName $Name -Description $Description -ProjectType $Type) -Summary $summary -Description 'README.md'
    New-NpwFile -Path (Join-Path $projectPath '.gitignore') -Content (Get-NpwGitignoreTemplate -ProjectType $Type -Config $config -Summary $summary) -Summary $summary -Description '.gitignore'

    if ($createLicense) {
        New-NpwFile -Path (Join-Path $projectPath 'LICENSE') -Content (Get-NpwLicenseTemplate -License $licenseId -Holder $licenseHolder) -Summary $summary -Description 'LICENSE'
    }
    else {
        Add-NpwSummaryItem -Summary $summary -Bucket Skipped -Message 'LICENSE file'
    }

    if ($createAgentFiles) {
        New-NpwAgentFiles -ProjectPath $projectPath -ProjectName $Name -ProjectType $Type -Summary $summary
    }
    else {
        Add-NpwSummaryItem -Summary $summary -Bucket Skipped -Message 'Agent files'
    }

    if (-not $NoGit -and [bool]$config.initializeGit) {
        Initialize-NpwGit -ProjectPath $projectPath -Summary $summary -CreateInitialCommit:(-not $NoInitialCommit -and [bool]$config.createInitialCommit)
    }
    else {
        Add-NpwSummaryItem -Summary $summary -Bucket Skipped -Message 'Git initialization'
    }

    if ($createGitHub) {
        Invoke-NpwGitHubCreate -ProjectPath $projectPath -ProjectName $Name -Visibility $githubVisibility -Summary $summary
    }

    if ($openCode) {
        Open-NpwVSCode -ProjectPath $projectPath -Summary $summary
    }
    else {
        Add-NpwSummaryItem -Summary $summary -Bucket Skipped -Message 'VS Code open'
    }

    Write-NpwSuccess 'Project wizard finished'
    Show-NpwSummary -Summary $summary -ProjectPath $projectPath
}

Export-ModuleMember -Function New-Project
