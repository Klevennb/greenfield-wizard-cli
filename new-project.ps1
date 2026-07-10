[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArguments
)

$modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'src/NewProjectWizard/NewProjectWizard.psd1'
Import-Module $modulePath -Force

New-Project @RemainingArguments
