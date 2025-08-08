# Zivver
PowerShell Module for Zivver SCIM API
## Notes
This is my first uploaden PowerShell Module and i am not associated with Zivver, only a customer. Please feel free to use it or help improving it.

## Installation
  Install-Module Zivver

## Commands to use
  Connect-ZivverAPI
  Get-ZivverUser
  Set-ZivverUser
  Add-ZivverUser
  Remove-ZivverUser
  Get-ZivverGroup
  Set-ZivverGroup
  Add-ZivverGroup
  Remove-ZivverGroup

## Usage
Create API Key in https://app.zivver.com/admin/api-keys and use it

  Connect-ZivverAPI -Token "YourAPIToken"

  Get-ZivverUser
  Get-ZivverGroup

  Get-ZivverUser -Id a90dc4e0-3028-4e57-a8e6-913bf3f7e5d6
  Get-ZivverUser -UserName exampleuser@company.nl
  Get-ZivverGroup -Id adc7a503-db30-4c35-ad62-feb71b9a5dde
  Get-ZivverGroup -ExternalId examplegroup@company.nl

  Set-ZivverUser -Id a90dc4e0-3028-4e57-a8e6-913bf3f7e5d6 -Active $false
  
