@{
    RootModule        = 'NewProjectWizard.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '91f0a2db-9281-470b-9d0a-aaaa'
    Author            = 'New Project Wizard'
    CompanyName       = 'Unknown'
    Copyright         = '(c) 2026. All rights reserved.'
    Description       = 'A polished PowerShell CLI wizard for bootstrapping new software projects.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('New-Project')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('project', 'wizard', 'bootstrap', 'cli')
            ProjectUri = ''
            LicenseUri = ''
        }
    }
}
