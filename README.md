# New Project Wizard

A polished PowerShell CLI wizard for bootstrapping new software projects.

Run it interactively:

```powershell
.\new-project.ps1
```

After installation, run:

```powershell
newproj
```

## Features

- Interactive wizard with colored status output and sensible defaults.
- Scriptable `New-Project` command for automation.
- Supported project types: Empty, Node, React, Next.js, Python, Rust, Go, and .NET.
- Git initialization and optional initial commit.
- README, `.gitignore`, optional LICENSE, and Codex-ready agent files.
- Official GitHub `.gitignore` templates with cache and embedded fallback.
- Optional GitHub repository creation through `gh`.
- Optional VS Code launch with `code -n .`.
- Configuration stored outside the repo.
- Focused Pester tests for core behavior.

## Requirements

- Windows PowerShell 5.1 or newer.
- Git for repository initialization.
- VS Code command-line launcher (`code`) if you want automatic opening.
- GitHub CLI (`gh`) if you want remote repository creation.
- Ecosystem tools for selected project types:
  - Node, React, Next.js: Node.js, npm, and npx.
  - Python: Python launcher `py` or `python`.
  - Rust: `cargo`.
  - Go: `go`.
  - .NET: `dotnet`.

If script execution is restricted on your machine, use:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\new-project.ps1
```

## Install

From this repo:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

The installer copies the module to:

```text
$HOME\Documents\PowerShell\Modules\NewProjectWizard\0.1.0
```

It then asks before adding this profile snippet:

```powershell
Import-Module NewProjectWizard
Set-Alias newproj New-Project
```

Restart PowerShell after installation, or run the two profile lines manually in your current session.

Manual install:

```powershell
$target = "$HOME\Documents\PowerShell\Modules\NewProjectWizard\0.1.0"
New-Item -ItemType Directory -Force -Path $target
Copy-Item .\src\NewProjectWizard\NewProjectWizard.* $target
Import-Module NewProjectWizard
Set-Alias newproj New-Project
```

## Usage

Interactive:

```powershell
newproj
```

Local launcher:

```powershell
.\new-project.ps1
```

Parameterized:

```powershell
New-Project `
  -Name my-api `
  -Type Node `
  -Path C:\Users\kleve\Projects `
  -Description "API service" `
  -NoGitHub `
  -NoCode
```

Preview major actions without creating the project:

```powershell
New-Project -Name scratch -Type Empty -Path C:\Temp -NoLicense -NoAgentFiles -NoGit -NoCode -NoGitHub -WhatIf
```

## Configuration

The wizard reads configuration from:

```text
~\.config\new-project-wizard\config.json
```

It creates this file on first run if it does not exist.

Example:

```json
{
  "defaultProjectsFolder": "C:\\Users\\kleve\\Projects",
  "preferredLicense": "MIT",
  "defaultGitHubVisibility": "private",
  "openVSCode": true,
  "initializeGit": true,
  "createInitialCommit": true,
  "downloadGitignoreTemplates": true,
  "createAgentFiles": true
}
```

Command parameters override configuration for that run.

## Generated Agent Files

Agent files are enabled by default because projects are expected to be built with Codex.

Generated files:

- `AGENTS.md`
- `CONTEXT.md`
- `docs/adr/0001-record-architecture-decisions.md`
- `.codex/README.md`
- `.github/copilot-instructions.md`

Skip them with:

```powershell
New-Project -Name demo -Type Empty -NoAgentFiles
```

## Supported Project Types

- `Empty`: repository files only.
- `Node`: `package.json`, `src/index.js`, and `npm start`.
- `React`: Vite React TypeScript through `npm create vite@latest`.
- `Next.js`: TypeScript, App Router, ESLint, `src/`, Tailwind disabled.
- `Python`: `.venv`, `pyproject.toml`, and `src/<package>/__init__.py`.
- `Rust`: `cargo init --bin`.
- `Go`: `go mod init` and `main.go`.
- `.NET`: `dotnet new`, defaulting to `console`.

## GitHub

If `gh` is installed, the wizard asks whether to create a GitHub repository. It defaults to not creating one.

When enabled, it runs:

```powershell
gh repo create <name> --private --source . --remote origin --push
```

Visibility defaults to `private` and can be changed in config or with `-GitHubVisibility public`.

## Extending Project Types

Project types are defined in `src/NewProjectWizard/NewProjectWizard.psm1`.

To add one:

1. Add its display name to `$script:SupportedProjectTypes`.
2. Add a `.gitignore` mapping to `$script:GitignoreTemplateMap`.
3. Create an `Initialize-Npw<Name>Project` function.
4. Add a branch in `Initialize-NpwProjectType`.
5. Add or update tests in `tests/NewProjectWizard.Tests.ps1`.
6. Document the new type in this README.

Keep each initializer responsible only for that project type. Shared behavior such as README, Git, GitHub, LICENSE, `.gitignore`, VS Code, and Agent Files belongs in the common orchestration.

## Tests

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester -Script .\tests\NewProjectWizard.Tests.ps1"
```

The current suite avoids real npm, cargo, dotnet, gh, and VS Code integration calls. It focuses on validation, config merging, registry coverage, fallback templates, directory safety, and agent file generation.
