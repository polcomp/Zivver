# Zivver.psm1
# Author: Martijn van de Pol
# Description: Provides cmdlets for managing Zivver users and groups via the SCIM API.
# Version: 1.0.2
# Copyright © Martijn van de Pol, 2025

# Load all public functions
Get-ChildItem -Path "$PSScriptRoot/*.ps1" | ForEach-Object {
    . $_.FullName
}

# Session variable to store token and base URI
$Script:ZivverSession = @{}

function Connect-ZivverApi {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Token,

        [string]$BaseUri = "https://app.zivver.com/api/scim/v2"
    )

    $headers = @{
        "Authorization" = "Bearer $Token"
        "Accept"        = "application/scim+json"
    }

    try {
        $testUri = "$BaseUri/Users?count=1"
        $response = Invoke-RestMethod -Uri $testUri -Method GET -Headers $headers -ErrorAction Stop

        $Script:ZivverSession = @{
            Token   = $Token
            BaseUri = $BaseUri
        }

        Write-Host "✅ Successfully connected to Zivver SCIM API." -ForegroundColor Green
    } catch {
        Write-Error "❌ Failed to connect to Zivver SCIM API: $_"
    }
}

function CreateZivverUserTable {
	[PSCustomObject]@{
		Id        = $_.id
		UserName  = $_.userName
		Name      = $_.name.formatted
		phoneNumbers      = $_.phoneNumbers
		Active    = $_.active
		Created   = $_.meta.created
		ResourceType  = $_.meta.resourceType
		Division  = $_.'urn:ietf:params:scim:schemas:extension:enterprise:2.0:User'.division
		Aliases       = $_."urn:ietf:params:scim:schemas:zivver:0.1:User".aliases
		Delegates     = $_."urn:ietf:params:scim:schemas:zivver:0.1:User".delegates
		ExternalAccountId     = $_."urn:ietf:params:scim:schemas:zivver:0.1:User".ExternalAccountId
	}
}

function CreateZivverGroupTable {
	[PSCustomObject]@{
		Id        = $_.id
		externalId  = $_.externalId
		displayName      = $_.displayName
		members      = $_.members
		Created   = $_.meta.created
		ResourceType  = $_.meta.resourceType
		Division  = $_.'urn:ietf:params:scim:schemas:extension:enterprise:2.0:User'.division
		Aliases       = $_."urn:ietf:params:scim:schemas:zivver:0.1:Group".aliases
		ExternalAccountId     = $_."urn:ietf:params:scim:schemas:zivver:0.1:Group".ExternalAccountId
	}
}

function Get-ZivverOrganization {
    $baseUri = "$($Script:ZivverSession.BaseUri)/Organization"
    $headers = @{
        "Authorization" = "Bearer $($Script:ZivverSession.Token)"
        "Accept"        = "application/scim+json"
    }

    try {
		Invoke-RestMethod -Uri $baseUri -Method GET -Headers $headers -ErrorAction Stop
    } catch {
        Write-Error "❌ Failed to retrieve Zivver Organization: $_"
    }
}

function Get-ZivverUser {
    [CmdletBinding(DefaultParameterSetName = 'All')]
    param (
        [Parameter(ParameterSetName = 'ById')][string]$Id,
        [Parameter(ParameterSetName = 'ByUsername')][string]$UserName
    )

    $baseUri = "$($Script:ZivverSession.BaseUri)/Users"
    $headers = @{
        "Authorization" = "Bearer $($Script:ZivverSession.Token)"
        "Accept"        = "application/scim+json"
    }

    try {
        switch ($PSCmdlet.ParameterSetName) {
            'ById' {
                $uri = "$baseUri/$Id"
                $response = Invoke-RestMethod -Uri $uri -Method GET -Headers $headers -ErrorAction Stop
				if (-not $response.Resources) {Write-Error "❌ Cannot find user with Id $Id"}
                return $response.Resources | ForEach-Object {CreateZivverUserTable}
            }
            'ByUsername' {
                $uri = "$baseUri" + "?filter=userName eq `"$UserName`""
                $response = Invoke-RestMethod -Uri $uri -Method GET -Headers $headers -ErrorAction Stop
				if (-not $response.Resources) {Write-Error "❌ Cannot find user with UserName $UserName"}
                return $response.Resources | ForEach-Object {CreateZivverUserTable}
            }
            default {
                $response = Invoke-RestMethod -Uri $baseUri -Method GET -Headers $headers -ErrorAction Stop
                return $response.Resources | ForEach-Object {CreateZivverUserTable}
            }
        }
    } catch {
        Write-Error "❌ Failed to retrieve Zivver users: $_"
    }
}


function Set-ZivverUser {
    [CmdletBinding(DefaultParameterSetName = 'ById')]
    param (
        [Parameter(ParameterSetName = 'ById', Mandatory)][string]$Id,
        [Parameter(ParameterSetName = 'ByUsername', Mandatory)][string]$UserName,

        [string[]]$Aliases,
        [string[]]$Delegates,
        [bool]$Active
    )

    $baseUri = "$($Script:ZivverSession.BaseUri)/Users"
    $headers = @{
        "Authorization" = "Bearer $($Script:ZivverSession.Token)"
        "Content-Type"  = "application/scim+json"
    }

    try {
        if ($UserName) {
            $uri = "$baseUri" + "?filter=userName eq `"$UserName`""
            $lookup = Invoke-RestMethod -Uri $uri -Headers $headers -ErrorAction Stop
            if ($lookup.Resources.Count -eq 0) {
                throw "User not found with username: $UserName"
            }
            $Id = $lookup.Resources[0].id
        }

        $operations = @{}

        # Always retrieve current user details
		$currentUser = Invoke-RestMethod -Uri "$baseUri/$Id" -Headers $headers -ErrorAction Stop
		$currentExtension = $currentUser.'urn:ietf:params:scim:schemas:zivver:0.1:User'

		$aliases   = if ($PSBoundParameters.ContainsKey('Aliases')) { $Aliases } else { $currentExtension.aliases }
		$delegates = if ($PSBoundParameters.ContainsKey('Delegates')) { $Delegates } else { $currentExtension.delegates }
		$externalAccountId = $currentExtension.ExternalAccountId  # Always preserve!

		$operations += @{
			'urn:ietf:params:scim:schemas:zivver:0.1:User' = @{
				aliases   = $aliases
				delegates = $delegates
				ExternalAccountId = $externalAccountId
			}
		}

        if ($PSBoundParameters.ContainsKey('Active')) {
            $operations += @{ active = $Active }
        }

        if ($operations.Count -eq 0) {
            Write-Warning "No update parameters provided."
            return
        }

        $body = $operations | ConvertTo-Json -Depth 5

        $patchUri = "$baseUri/$Id"
        $response = Invoke-RestMethod -Uri $patchUri -Method PUT -Headers $headers -Body $body -ContentType "application/json; charset=utf-8" -ErrorAction Stop
        Write-Host "✅ User $Id successfully updated."
		
		return $response | ForEach-Object {CreateZivverUserTable}

    } catch {
        Write-Error "❌ Failed to update Zivver user: $_"
    }
}

function Add-ZivverUser {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$UserName,
        [Parameter(Mandatory)][string]$Name,
		[Parameter(Mandatory)][string]$Active
    )

    $uri = "$($Script:ZivverSession.BaseUri)/Users"
    $headers = @{
        "Authorization" = "Bearer $($Script:ZivverSession.Token)"
        "Content-Type"  = "application/scim+json"
    }

	$operations = @{}

	$operations += @{ userName = $UserName }
	$operations += @{ active = $Active }
	$operations += @{ name = @{ formatted = $UserName } }

	$body = $operations | ConvertTo-Json -Depth 5

    try {
        $response = Invoke-RestMethod -Uri $uri -Method POST -Headers $headers -Body $body
        Write-Host "✅ Zivver user '$UserName' successfully created."
        return $response | ForEach-Object {CreateZivverUserTable}
    } catch {
        Write-Error "❌ Failed to create Zivver user: $_"
    }
}

function Remove-ZivverUser {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High', DefaultParameterSetName = 'ById')]
    param (
        [Parameter(ParameterSetName = 'ById', Mandatory)][string]$Id,
        [Parameter(ParameterSetName = 'ByUsername', Mandatory)][string]$UserName,
        [switch]$Force
    )

    $baseUri = "$($Script:ZivverSession.BaseUri)/Users"
    $headers = @{
        "Authorization" = "Bearer $($Script:ZivverSession.Token)"
        "Accept"        = "application/scim+json"
    }

    try {
        # Resolve by username if needed
        if ($PSCmdlet.ParameterSetName -eq 'ByUsername') {
            $uri = "$baseUri" + "?filter=userName eq `"$UserName`""
            $lookup = Invoke-RestMethod -Uri $uri -Headers $headers -ErrorAction Stop
            if (-not $lookup.Resources -or $lookup.Resources.Count -eq 0) {
                throw "Cannot find user with UserName '$UserName'."
            }
            $user = $lookup.Resources[0]
            $Id = $user.id
        } else {
            # Fetch user (for confirmation message)
            $userResp = Invoke-RestMethod -Uri "$baseUri/$Id" -Headers $headers -ErrorAction Stop
            # Some SCIM impls return full object vs envelope; normalize
            $user = if ($userResp.PSObject.Properties.Match('Resources')) { $userResp.Resources[0] } else { $userResp }
            if (-not $user) { throw "Cannot find user with Id '$Id'." }
        }

        $targetLabel = if ($user.userName) { "$($user.userName) (Id: $Id)" } else { "Id: $Id" }

        # Respect -Force/-Confirm and WhatIf
        if ($Force -or $PSCmdlet.ShouldProcess($targetLabel, "REMOVE Zivver user")) {
            Invoke-RestMethod -Uri "$baseUri/$Id" -Method DELETE -Headers $headers -ErrorAction Stop
            Write-Host "🗑️  Removed Zivver user: $targetLabel"
        }
    } catch {
        Write-Error "❌ Failed to delete Zivver user: $_"
    }
}

function Get-ZivverGroup {
    [CmdletBinding(DefaultParameterSetName = 'All')]
    param (
        [Parameter(ParameterSetName = 'ById')][string]$Id,
        [Parameter(ParameterSetName = 'ByExternalId')][string]$ExternalId
    )

    $baseUri = "$($Script:ZivverSession.BaseUri)/Groups"
    $headers = @{
        "Authorization" = "Bearer $($Script:ZivverSession.Token)"
        "Accept"        = "application/scim+json"
    }

    try {
        switch ($PSCmdlet.ParameterSetName) {
            'ById' {
                $uri = "$baseUri/$Id"
				$response = Invoke-RestMethod -Uri $uri -Method GET -Headers $headers -ErrorAction Stop
                if (-not $response) {Write-Error "❌ Cannot find user with Id $Id"}
                return $response | ForEach-Object {CreateZivverGroupTable}
            }
            'ByExternalId' {
                $uri = "$baseUri" + "?filter=externalId eq `"$ExternalId`""
                $response = Invoke-RestMethod -Uri $uri -Method GET -Headers $headers -ErrorAction Stop
                if (-not $response.Resources) {Write-Error "❌ Cannot find Group with ExternalId $ExternalId"}
                return $response.Resources | ForEach-Object {CreateZivverGroupTable}
            }
            default {
                $response = Invoke-RestMethod -Uri $baseUri -Method GET -Headers $headers -ErrorAction Stop
                return $response.Resources | ForEach-Object {CreateZivverGroupTable}
            }
        }
    } catch {
        Write-Error "❌ Failed to retrieve Zivver groups: $_"
    }
}

function Set-ZivverGroup {
    [CmdletBinding(DefaultParameterSetName = 'ById')]
    param (
        [Parameter(ParameterSetName = 'ById', Mandatory)][string]$Id,
        [Parameter(ParameterSetName = 'ByExternalId', Mandatory)][string]$ExternalId,
		[string[]]$Aliases,
        [string[]]$Members,
        [string]$NewExternalId
    )

    $baseUri = "$($Script:ZivverSession.BaseUri)/Groups"
    $headers = @{
        "Authorization" = "Bearer $($Script:ZivverSession.Token)"
        "Content-Type"  = "application/scim+json"
    }

    try {
        if ($ExternalId) {
            $uri = "$baseUri" + "?filter=externalId eq `"$ExternalId`""
            $lookup = Invoke-RestMethod -Uri $uri -Headers $headers -ErrorAction Stop
            if ($lookup.Resources.Count -eq 0) {
                throw "Group not found with ExternalId: $ExternalId"
            }
            $Id = $lookup.Resources[0].id
        }
		
		$operations = @{}

        # Always retrieve current group details
        $currentGroup = Invoke-RestMethod -Uri "$baseUri/$Id" -Headers $headers -ErrorAction Stop
		$currentExtension = $currentGroup.'urn:ietf:params:scim:schemas:zivver:0.1:Group'

		$aliases   = if ($PSBoundParameters.ContainsKey('Aliases')) { $Aliases } else { $currentExtension.aliases }
		$externalAccountId = $currentExtension.ExternalAccountId  # Always preserve!

		if ($PSBoundParameters.ContainsKey('Aliases')) {
			$operations += @{
				'urn:ietf:params:scim:schemas:zivver:0.1:Group' = @{
					aliases   = $aliases
					ExternalAccountId = $externalAccountId
				}
			}
		}

        if ($PSBoundParameters.ContainsKey('Members')) {
			$MembersTable = @()
			foreach ($MemberId in $Members) {
				$MembersTable += @{ value = $memberId }
			}
			$operations += @{
				members = $MembersTable
			}
		}
        

        if ($operations.Count -eq 0) {
            Write-Warning "No update parameters provided."
            return
        }

        $body = $operations | ConvertTo-Json -Depth 5

        $patchUri = "$baseUri/$Id"
        $response = Invoke-RestMethod -Uri $patchUri -Method PUT -Headers $headers -Body $body -ContentType "application/json; charset=utf-8" -ErrorAction Stop
        Write-Host "✅ Group $Id successfully updated."
		
        return $response | ForEach-Object {CreateZivverGroupTable}

    } catch {
        Write-Error "❌ Failed to update Zivver group: $_"
    }
}

function Add-ZivverGroup {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$ExternalId,
		[Parameter(Mandatory)][string]$DisplayName
    )

    $uri = "$($Script:ZivverSession.BaseUri)/Groups"
    $headers = @{
        "Authorization" = "Bearer $($Script:ZivverSession.Token)"
        "Content-Type"  = "application/scim+json"
    }

	$operations = @{}

	$operations += @{ externalId = $ExternalId }
	$operations += @{ displayName = $DisplayName }

	$body = $operations | ConvertTo-Json -Depth 5

    try {
        $response = Invoke-RestMethod -Uri $uri -Method POST -Headers $headers -Body $body
        Write-Host "✅ Zivver group '$DisplayName' successfully created."
        return $response | ForEach-Object {CreateZivverGroupTable}
    } catch {
        Write-Error "❌ Failed to create Zivver group: $_"
    }
}

function Remove-ZivverGroup {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High', DefaultParameterSetName = 'ById')]
    param (
        [Parameter(ParameterSetName = 'ById', Mandatory)][string]$Id,
        [Parameter(ParameterSetName = 'ByExternalId', Mandatory)][string]$ExternalId,
        [switch]$Force
    )

    $baseUri = "$($Script:ZivverSession.BaseUri)/Groups"
    $headers = @{
        "Authorization" = "Bearer $($Script:ZivverSession.Token)"
        "Accept"        = "application/scim+json"
    }

    try {
        # Resolve by ExternalId if needed
        if ($PSCmdlet.ParameterSetName -eq 'ByExternalId') {
            $uri = "$baseUri" + "?filter=externalId eq `"$ExternalId`""
            $lookup = Invoke-RestMethod -Uri $uri -Headers $headers -ErrorAction Stop
            if (-not $lookup.Resources -or $lookup.Resources.Count -eq 0) {
                throw "Cannot find group with ExternalId '$ExternalId'."
            }
            $group = $lookup.Resources[0]
            $Id = $group.id
        } else {
            # Fetch group (for confirmation message)
            $groupResp = Invoke-RestMethod -Uri "$baseUri/$Id" -Headers $headers -ErrorAction Stop
            $group = if ($groupResp.PSObject.Properties.Match('Resources')) { $groupResp.Resources[0] } else { $groupResp }
            if (-not $group) { throw "Cannot find group with Id '$Id'." }
        }

        $label = if ($group.displayName) { "$($group.displayName) (Id: $Id)" }
                 elseif ($ExternalId)   { "ExternalId: $ExternalId (Id: $Id)" }
                 else { "Id: $Id" }

        if ($Force -or $PSCmdlet.ShouldProcess($label, "REMOVE Zivver group")) {
            Invoke-RestMethod -Uri "$baseUri/$Id" -Method DELETE -Headers $headers -ErrorAction Stop
            Write-Host "🗑️  Remove Zivver group: $label"
        }
    } catch {
        Write-Error "❌ Failed to delete Zivver group: $_"
    }
}
