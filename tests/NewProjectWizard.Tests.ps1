$modulePath = Join-Path -Path $PSScriptRoot -ChildPath '../src/NewProjectWizard/NewProjectWizard.psd1'
Import-Module $modulePath -Force

Describe 'NewProjectWizard internals' {
    InModuleScope NewProjectWizard {
        It 'validates safe project names' {
            Test-NpwProjectName -Name 'my-app' | Should Be $true
            Test-NpwProjectName -Name 'my_app.2' | Should Be $true
            Test-NpwProjectName -Name '' | Should Be $false
            Test-NpwProjectName -Name ' bad' | Should Be $false
            Test-NpwProjectName -Name '../bad' | Should Be $false
        }

        It 'merges user config over defaults' {
            $defaults = @{ openVSCode = $true; preferredLicense = 'MIT' }
            $user = @{ openVSCode = $false }
            $merged = Merge-NpwConfig -Defaults $defaults -UserConfig $user
            $merged.openVSCode | Should Be $false
            $merged.preferredLicense | Should Be 'MIT'
        }

        It 'reads comments, whitespace, and quoted values from dotenv files' {
            $path = Join-Path ([System.IO.Path]::GetTempPath()) "$([System.Guid]::NewGuid()).env"
            try {
                Set-Content -LiteralPath $path -Value @('# comment', ' NPW_DEFAULT_PROJECTS_FOLDER = "C:\Projects Folder" ', "NPW_PREFERRED_LICENSE='MIT'", 'UNRELATED=value')
                $values = Read-NpwDotEnv -Path $path
                $values.NPW_DEFAULT_PROJECTS_FOLDER | Should Be 'C:\Projects Folder'
                $values.NPW_PREFERRED_LICENSE | Should Be 'MIT'
                $values.ContainsKey('UNRELATED') | Should Be $false
            }
            finally { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
        }

        It 'uses process variables before dotenv values' {
            $path = Join-Path ([System.IO.Path]::GetTempPath()) "$([System.Guid]::NewGuid()).env"
            $oldValue = [Environment]::GetEnvironmentVariable('NPW_OPEN_VSCODE', 'Process')
            try {
                Set-Content -LiteralPath $path -Value 'NPW_OPEN_VSCODE=false'
                [Environment]::SetEnvironmentVariable('NPW_OPEN_VSCODE', 'true', 'Process')
                (Get-NpwEnvironmentConfig -DotEnvPath $path).openVSCode | Should Be $true
            }
            finally {
                [Environment]::SetEnvironmentVariable('NPW_OPEN_VSCODE', $oldValue, 'Process')
                Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
            }
        }

        It 'parses supported dotenv settings and rejects invalid values' {
            (ConvertFrom-NpwEnvironmentValue -Name NPW_INITIALIZE_GIT -Value false -Type boolean) | Should Be $false
            (ConvertFrom-NpwEnvironmentValue -Name NPW_PREFERRED_LICENSE -Value Apache-2.0 -Type license) | Should Be 'Apache-2.0'
            (ConvertFrom-NpwEnvironmentValue -Name NPW_DEFAULT_GITHUB_VISIBILITY -Value public -Type visibility) | Should Be 'public'
            { ConvertFrom-NpwEnvironmentValue -Name NPW_INITIALIZE_GIT -Value yes -Type boolean } | Should Throw
            { ConvertFrom-NpwEnvironmentValue -Name NPW_PREFERRED_LICENSE -Value Custom -Type license } | Should Throw
            { ConvertFrom-NpwEnvironmentValue -Name NPW_DEFAULT_GITHUB_VISIBILITY -Value internal -Type visibility } | Should Throw
        }

        It 'maps all supported dotenv settings to configuration keys' {
            $path = Join-Path ([System.IO.Path]::GetTempPath()) "$([System.Guid]::NewGuid()).env"
            try {
                Set-Content -LiteralPath $path -Value @(
                    'NPW_DEFAULT_PROJECTS_FOLDER=C:\Projects'
                    'NPW_PREFERRED_LICENSE=BSD-3-Clause'
                    'NPW_DEFAULT_GITHUB_VISIBILITY=public'
                    'NPW_OPEN_VSCODE=false'
                    'NPW_INITIALIZE_GIT=false'
                    'NPW_CREATE_INITIAL_COMMIT=false'
                    'NPW_DOWNLOAD_GITIGNORE_TEMPLATES=false'
                    'NPW_CREATE_AGENT_FILES=false'
                )
                $config = Get-NpwEnvironmentConfig -DotEnvPath $path
                $config.Count | Should Be 8
                $config.defaultProjectsFolder | Should Be 'C:\Projects'
                $config.preferredLicense | Should Be 'BSD-3-Clause'
                $config.defaultGitHubVisibility | Should Be 'public'
                $config.openVSCode | Should Be $false
                $config.initializeGit | Should Be $false
                $config.createInitialCommit | Should Be $false
                $config.downloadGitignoreTemplates | Should Be $false
                $config.createAgentFiles | Should Be $false
            }
            finally { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
        }

        It 'returns no dotenv overrides when the file is missing' {
            $path = Join-Path ([System.IO.Path]::GetTempPath()) "$([System.Guid]::NewGuid()).missing"
            (Read-NpwDotEnv -Path $path).Count | Should Be 0
        }

        It 'reports malformed recognized dotenv entries' {
            $path = Join-Path ([System.IO.Path]::GetTempPath()) "$([System.Guid]::NewGuid()).env"
            try {
                Set-Content -LiteralPath $path -Value 'NPW_OPEN_VSCODE "true"'
                { Read-NpwDotEnv -Path $path } | Should Throw
                Set-Content -LiteralPath $path -Value 'NPW_OPEN_VSCODE="true'
                { Read-NpwDotEnv -Path $path } | Should Throw
            }
            finally { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
        }

        It 'does not append the project name twice when the selected path already ends with it' {
            $root = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([System.Guid]::NewGuid().ToString())
            $selectedPath = Join-Path -Path $root -ChildPath 'terminal-typer'
            $resolvedPath = Resolve-NpwProjectPath -BasePath $selectedPath -Name 'terminal-typer'
            $resolvedPath | Should Be $selectedPath
        }

        It 'contains the initial project type registry' {
            $types = Get-NpwProjectTypes
            ($types -contains 'Empty') | Should Be $true
            ($types -contains 'Node') | Should Be $true
            ($types -contains 'React') | Should Be $true
            ($types -contains 'Next.js') | Should Be $true
            ($types -contains 'Python') | Should Be $true
            ($types -contains 'Rust') | Should Be $true
            ($types -contains 'Go') | Should Be $true
            ($types -contains '.NET') | Should Be $true
        }

        It 'produces fallback gitignore content without network' {
            $content = Get-NpwFallbackGitignore -ProjectType 'Python'
            $content | Should Match '.venv/'
            $content | Should Match '.env'
        }

        It 'detects non-empty directories' {
            $root = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([System.Guid]::NewGuid().ToString())
            New-Item -ItemType Directory -Path $root | Out-Null
            try {
                Test-NpwDirectoryEmpty -Path $root | Should Be $true
                Set-Content -LiteralPath (Join-Path $root 'file.txt') -Value 'content'
                Test-NpwDirectoryEmpty -Path $root | Should Be $false
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force
            }
        }

        It 'creates agent files at expected paths' {
            $root = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([System.Guid]::NewGuid().ToString())
            $summary = New-NpwSummary
            New-Item -ItemType Directory -Path $root | Out-Null
            try {
                New-NpwAgentFiles -ProjectPath $root -ProjectName 'demo' -ProjectType 'Node' -Summary $summary
                Test-Path -LiteralPath (Join-Path $root 'AGENTS.md') | Should Be $true
                Test-Path -LiteralPath (Join-Path $root 'CONTEXT.md') | Should Be $true
                Test-Path -LiteralPath (Join-Path $root 'docs/adr/0001-record-architecture-decisions.md') | Should Be $true
                Test-Path -LiteralPath (Join-Path $root '.codex/README.md') | Should Be $true
                Test-Path -LiteralPath (Join-Path $root '.github/copilot-instructions.md') | Should Be $true
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force
            }
        }

        It 'does not create a project directory in WhatIf mode' {
            $root = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([System.Guid]::NewGuid().ToString())
            New-Item -ItemType Directory -Path $root | Out-Null
            try {
                New-Project -Name 'whatif-demo' -Type 'Empty' -Path $root -Description 'Preview only' -NoLicense -NoAgentFiles -NoGit -NoCode -NoGitHub -WhatIf
                Test-Path -LiteralPath (Join-Path $root 'whatif-demo') | Should Be $false
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force
            }
        }
    }
}
