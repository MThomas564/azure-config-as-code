# This script reads your editable config schema (with type info) and outputs a KVSet file for Azure App Configuration import.
# Usage: pwsh -File convert-to-kvset.ps1 -InputFile config/devKV.json -OutputFile config/devKV.kvset.json

param(
    [string]$InputFile = "config/dev.json",
    [string]$OutputFile = "config/devKV.kvset.json"
)

$schema = Get-Content $InputFile | ConvertFrom-Json
$kvset = @()

function New-ValidationError {
    param(
        [string]$Key,
        [string]$Message
    )
    throw "Feature flag '$Key' validation failed: $Message"
}

function Test-NumberInRange {
    param(
        [object]$Value
    )
    if ($null -eq $Value) { return $false }
    if ($Value -isnot [int] -and $Value -isnot [long] -and $Value -isnot [double] -and $Value -isnot [float] -and $Value -isnot [decimal]) {
        return $false
    }
    return ($Value -ge 0 -and $Value -le 100)
}

function Assert-TargetingAudience {
    param(
        [object]$Audience,
        [string]$Key
    )

    if ($Audience -isnot [pscustomobject]) {
        New-ValidationError -Key $Key -Message "'Microsoft.Targeting' requires parameters.Audience to be an object."
    }

    if ($Audience.PSObject.Properties["Users"]) {
        if ($Audience.Users -isnot [array]) {
            New-ValidationError -Key $Key -Message "'Microsoft.Targeting' Audience.Users must be an array of strings."
        }
        foreach ($user in $Audience.Users) {
            if ($user -isnot [string] -or [string]::IsNullOrWhiteSpace($user)) {
                New-ValidationError -Key $Key -Message "'Microsoft.Targeting' Audience.Users must only contain non-empty strings."
            }
        }
    }

    if ($Audience.PSObject.Properties["Groups"]) {
        if ($Audience.Groups -isnot [array]) {
            New-ValidationError -Key $Key -Message "'Microsoft.Targeting' Audience.Groups must be an array of group objects."
        }
        foreach ($group in $Audience.Groups) {
            if ($group -isnot [pscustomobject]) {
                New-ValidationError -Key $Key -Message "'Microsoft.Targeting' Audience.Groups entries must be objects."
            }

            if (-not $group.PSObject.Properties["Name"] -or [string]::IsNullOrWhiteSpace($group.Name)) {
                New-ValidationError -Key $Key -Message "'Microsoft.Targeting' group entries require a non-empty Name."
            }

            if (-not $group.PSObject.Properties["RolloutPercentage"] -or -not (Test-NumberInRange -Value $group.RolloutPercentage)) {
                New-ValidationError -Key $Key -Message "'Microsoft.Targeting' group RolloutPercentage must be a number between 0 and 100."
            }
        }
    }

    if ($Audience.PSObject.Properties["DefaultRolloutPercentage"] -and -not (Test-NumberInRange -Value $Audience.DefaultRolloutPercentage)) {
        New-ValidationError -Key $Key -Message "'Microsoft.Targeting' Audience.DefaultRolloutPercentage must be a number between 0 and 100."
    }
}

function Normalize-FeatureFlagValue {
    param(
        [object]$FeatureFlagValue,
        [string]$Key
    )

    if ($FeatureFlagValue -isnot [pscustomobject]) {
        New-ValidationError -Key $Key -Message "value must be an object."
    }

    if (-not $FeatureFlagValue.PSObject.Properties["id"] -or [string]::IsNullOrWhiteSpace($FeatureFlagValue.id)) {
        New-ValidationError -Key $Key -Message "value.id is required and must be a non-empty string."
    }

    if (-not $FeatureFlagValue.PSObject.Properties["enabled"] -or $FeatureFlagValue.enabled -isnot [bool]) {
        New-ValidationError -Key $Key -Message "value.enabled is required and must be a boolean."
    }

    $normalized = [ordered]@{}
    foreach ($prop in $FeatureFlagValue.PSObject.Properties) {
        $normalized[$prop.Name] = $prop.Value
    }

    $conditions = $null
    if ($FeatureFlagValue.PSObject.Properties["conditions"]) {
        $conditions = $FeatureFlagValue.conditions
        if ($conditions -isnot [pscustomobject]) {
            New-ValidationError -Key $Key -Message "value.conditions must be an object when provided."
        }
    } else {
        $conditions = [ordered]@{}
    }

    $requirementType = "Any"
    if ($conditions.PSObject.Properties["requirement_type"]) {
        if ($conditions.requirement_type -notin @("Any", "All")) {
            New-ValidationError -Key $Key -Message "value.conditions.requirement_type must be 'Any' or 'All'."
        }
        $requirementType = $conditions.requirement_type
    }

    $clientFilters = @()
    if ($conditions.PSObject.Properties["client_filters"]) {
        if ($conditions.client_filters -isnot [array]) {
            New-ValidationError -Key $Key -Message "value.conditions.client_filters must be an array."
        }
        foreach ($filter in $conditions.client_filters) {
            if ($filter -isnot [pscustomobject]) {
                New-ValidationError -Key $Key -Message "Each client filter must be an object."
            }
            if (-not $filter.PSObject.Properties["name"] -or [string]::IsNullOrWhiteSpace($filter.name)) {
                New-ValidationError -Key $Key -Message "Each client filter must include a non-empty name."
            }
            if ($filter.PSObject.Properties["parameters"] -and ($filter.parameters -isnot [pscustomobject])) {
                New-ValidationError -Key $Key -Message "Client filter parameters must be an object when provided."
            }

            if ($filter.name -eq "Microsoft.Percentage") {
                if (-not $filter.PSObject.Properties["parameters"] -or -not $filter.parameters.PSObject.Properties["Value"]) {
                    New-ValidationError -Key $Key -Message "'Microsoft.Percentage' requires parameters.Value."
                }
                if (-not (Test-NumberInRange -Value $filter.parameters.Value)) {
                    New-ValidationError -Key $Key -Message "'Microsoft.Percentage' parameters.Value must be a number between 0 and 100."
                }
            }

            if ($filter.name -eq "Microsoft.Targeting") {
                if (-not $filter.PSObject.Properties["parameters"] -or -not $filter.parameters.PSObject.Properties["Audience"]) {
                    New-ValidationError -Key $Key -Message "'Microsoft.Targeting' requires parameters.Audience."
                }
                Assert-TargetingAudience -Audience $filter.parameters.Audience -Key $Key
            }

            $normalizedFilter = [ordered]@{}
            foreach ($prop in $filter.PSObject.Properties) {
                $normalizedFilter[$prop.Name] = $prop.Value
            }
            $clientFilters += $normalizedFilter
        }
    }

    $normalizedConditions = [ordered]@{
        requirement_type = $requirementType
        client_filters = $clientFilters
    }
    $normalized["conditions"] = $normalizedConditions
    return $normalized
}

foreach ($item in $schema.items) {
    $key = $item.key
    $type = $item.type
    $label = if ($item.PSObject.Properties["label"]) { $item.label } else { $null }
    $tags = if ($item.PSObject.Properties["tags"]) { $item.tags } else { @{} }
    $contentType = ""
    $value = $item.value

    switch ($type) {
        "string" {
            $contentType = "text/plain"
            $kvObj = [ordered]@{
                key = $key
                value = $value
                content_type = $contentType
                tags = $tags
            }
            if ($label) { $kvObj.label = $label }
            $kvset += $kvObj
        }
        "json" {
            $contentType = "application/json"
            $value = $value | ConvertTo-Json -Compress -Depth 100
            $kvObj = [ordered]@{
                key = $key
                value = $value
                content_type = $contentType
                tags = $tags
            }
            if ($label) { $kvObj.label = $label }
            $kvset += $kvObj
        }
        "jsonarray" {
            # Split array into individual indexed items
            $contentType = "application/json"
            $index = 0
            foreach ($arrayItem in $value) {
                $indexedKey = "${key}:${index}"
                $itemValue = $arrayItem | ConvertTo-Json -Compress -Depth 100
                $kvObj = [ordered]@{
                    key = $indexedKey
                    value = $itemValue
                    content_type = $contentType
                    tags = $tags
                }
                if ($label) { $kvObj.label = $label }
                $kvset += $kvObj
                $index++
            }
        }
        "keyvault" {
            $contentType = "application/vnd.microsoft.appconfig.keyvaultref+json;charset=utf-8"
            $value = $value | ConvertTo-Json -Compress -Depth 10
            $kvObj = [ordered]@{
                key = $key
                value = $value
                content_type = $contentType
                tags = $tags
            }
            if ($label) { $kvObj.label = $label }
            $kvset += $kvObj
        }
        "featureflag" {
            $contentType = "application/vnd.microsoft.appconfig.ff+json;charset=utf-8"
            # Ensure key is in feature flag format
            if (-not $key.StartsWith('.appconfig.featureflag/')) {
                $key = ".appconfig.featureflag/$key"
            }
            $value = Normalize-FeatureFlagValue -FeatureFlagValue $value -Key $key
            $value = $value | ConvertTo-Json -Compress -Depth 20
            $kvObj = [ordered]@{
                key = $key
                value = $value
                content_type = $contentType
                tags = $tags
            }
            if ($label) { $kvObj.label = $label }
            $kvset += $kvObj
        }
        default {
            $contentType = "text/plain"
            $kvObj = [ordered]@{
                key = $key
                value = $value
                content_type = $contentType
                tags = $tags
            }
            if ($label) { $kvObj.label = $label }
            $kvset += $kvObj
        }
    }
}

@{ items = $kvset } | ConvertTo-Json -Depth 100 | Set-Content $OutputFile
Write-Host "Converted $InputFile to $OutputFile in KVSet format."
