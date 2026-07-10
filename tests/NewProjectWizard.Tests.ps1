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
