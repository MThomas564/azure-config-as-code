# This script reads your editable config schema (with type info) and outputs a KVSet file for Azure App Configuration import.
# Usage: pwsh -File convert-to-kvset.ps1 -InputFile config/devKV.json -OutputFile config/devKV.kvset.json

param(
    [string]$InputFile = "config/dev.json",
    [string]$OutputFile = "config/devKV.kvset.json"
)

function ConvertTo-FlatKV {
      param([string]$Prefix, $Value, [int]$Depth)

      $isArr = ($Value -is [System.Collections.IEnumerable]) -and ($Value -isnot [string])
      $isObj = $Value -is [pscustomobject]

      if ($Depth -le 0 -or (-not $isArr -and -not $isObj)) {
          return ,([pscustomobject]@{ Key = $Prefix; Value = $Value; Complex = $true })
      }
      $out = @()
      if ($isArr) {
          $i = 0
          foreach ($el in $Value) { $out += ConvertTo-FlatKV "${Prefix}:${i}" $el ($Depth-1); $i++ }
      } else {
          $baseValue = [ordered]@{}
          foreach ($p in $Value.PSObject.Properties) {
              $propertyIsArray = ($p.Value -is [System.Collections.IEnumerable]) -and ($p.Value -isnot [string])
              if ($propertyIsArray) {
                  $out += ConvertTo-FlatKV "${Prefix}:$($p.Name)" $p.Value $Depth
              } else {
                  $baseValue[$p.Name] = $p.Value
              }
          }
          if ($baseValue.Count -gt 0) {
              $out = @([pscustomobject]@{ Key = $Prefix; Value = [pscustomobject]$baseValue; Complex = $true }) + $out
          }
      }
      if ($out.Count -eq 0) {
          return ,([pscustomobject]@{ Key = $Prefix; Value = $Value; Complex = $true })
      }
      return $out
}

function New-KvObj {
    param(
        [string]$Key,
        $Value,
        [string]$ContentType,
        $Tags = @{},
        [string]$Label = $null
    )
    $kvObj = [ordered]@{
        key = $Key
        value = $Value
        content_type = $ContentType
        tags = $Tags
    }
    if($Label) {$kvObj.label = $Label}
    return $kvObj
}


$schema = Get-Content $InputFile | ConvertFrom-Json
$kvset = @()


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
            $depth = if ($item.PSObject.Properties["flattenDepth"]) { [int]$item.flattenDepth } else { 0 }
            $index = 0
            foreach ($arrayItem in $value) {
                $base = "${key}:${index}"
                if ($depth -le 0) {
                    $kvset += (New-KvObj $base ($arrayItem | ConvertTo-Json -Compress -Depth 100) "application/json" $tags $label)
                } else {
                    foreach ($leaf in (ConvertTo-FlatKV $base $arrayItem $depth)) {
                        if ($leaf.Complex) {
                            $kvset += (New-KvObj $leaf.Key ($leaf.Value | ConvertTo-Json -Compress -Depth 100) "application/json" $tags $label)
                        } else {
                            $kvset += (New-KvObj $leaf.Key ([string]$leaf.Value) "text/plain" $tags $label)
                        }
                    }
                }
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
