@{
    RootModule           = 'pwshui.psm1'
    ModuleVersion        = '0.1.1'
    GUID                 = 'd2b8e3a1-7c9d-4e5f-8b2a-1c3d4e5f6e7f'
    Author               = 'Stan Clemance'
    CompanyName          = 'Unknown'
    Copyright            = '(c) 2026 Stan Clemance. All rights reserved.'
    Description          = 'A portable, flexible suite of PowerShell 7.4+ functions for clean console UX.'
    PowerShellVersion    = '7.4'
    FunctionsToExport    = @('Get-PaginatedSelection', 'Read-MaskedInput', 'Read-ValidatedInput', 'Invoke-NestedMenu', 'Write-UIBox', 'Measure-FuzzyMatch')
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData = @{
        PSData = @{
            # Tags = @()
            # LicenseUri = ''
            # ProjectUri = ''
            # IconUri = ''
            # ReleaseNotes = ''
        }
    }
}
