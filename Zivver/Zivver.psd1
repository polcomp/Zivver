# Zivver PowerShell Module Manifest
# Author: Martijn van de Pol
# Description: Provides cmdlets for managing Zivver users and groups via the SCIM API.
# Version: 1.0.2
# Copyright © Martijn van de Pol, 2025

@{
    RootModule = '.\Zivver.psm1'
	ModuleVersion = '1.0.2'
    GUID = 'efefe00e-51f0-4454-8b45-5c18e39daaa6'
    Author = 'Martijn van de Pol'
    Copyright = '© Martijn van de Pol, 2025'
    Description = 'PowerShell module for managing Zivver users and groups via the SCIM API.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Connect-ZivverApi',
        'Get-ZivverUser',
        'Set-ZivverUser',
        'Add-ZivverUser',
        'Remove-ZivverUser',
        'Get-ZivverGroup',
        'Set-ZivverGroup',
        'Add-ZivverGroup',
        'Remove-ZivverGroup'
    )
    CmdletsToExport = @()
    VariablesToExport = '*'
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('Zivver','SCIM','API','UserManagement','GroupManagement')
            LicenseUri = ''
            ProjectUri = ''
            ReleaseNotes = 'Initial release with full support for managing Zivver users and groups.'
        }
    }
}
