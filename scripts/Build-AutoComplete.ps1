#Requires -Version 7.0
using namespace System.Collections.Generic

param( [switch]$Clean )

# enums: https://bitwarden.com/help/cli/#enums
$BWEnums = @{
    '--method' = 0, 1, 3
    '--format' = 'csv', 'json'
    '--shell'  = 'zsh'
}

$RepoRoot = $PSScriptRoot
while ( -not( Test-Path -Path "$RepoRoot\.git" ) ) {
    $PSParentPath = (Get-Item $RepoRoot).PSParentPath
    if ( -not $PSParentPath ) {
        Write-Error 'Could not find repo root!' -ErrorAction Stop
    }
    $RepoRoot = $PSParentPath | Convert-Path
}

$CurrentPlatform = Get-Variable -Name Is* | Where-Object { $_.Name -match '^Is(?<Platform>Windows|Linux|MacOS)$' -and $_.Value -eq $true } | ForEach-Object { $Matches.Platform.ToLower() }

$CacheFolder = Join-Path $RepoRoot 'cache'

if ( $Clean -and ( Test-Path $CacheFolder ) ) {
    Remove-Item -Path $CacheFolder -Recurse -Force -ErrorAction Stop
}

New-Item -Path $CacheFolder -ItemType Directory -Force > $null

$env:BITWARDENCLI_APPDATA_DIR = $CacheFolder

$BinaryName = 'bw' + ( $CurrentPlatform -eq 'Windows' ? '.exe' : '' )
$BinaryPath = Join-Path $CacheFolder $BinaryName
$DownloadPath = Join-Path $CacheFolder 'bw.zip'
$DownloadUri = 'https://vault.bitwarden.com/download/?app=cli&platform={0}' -f $CurrentPlatform

if ( -not( Test-Path -Path $BinaryPath ) ) {
    Write-Host 'Downloading current bw-cli binary...'
    Invoke-WebRequest -Uri $DownloadUri -OutFile $DownloadPath -ErrorAction Stop
    Expand-Archive -Path $DownloadPath -DestinationPath $CacheFolder
}

$BitwardenCLI = Get-Command $BinaryPath -ErrorAction Stop
$BitwardenCLIVersion = & $BitwardenCLI --version --raw

Write-Host 'Bitwarden CLI Version:' $BitwardenCLIVersion

$Script:__BWHelpText = @{}
function GetBWHelp {
    <#
    .SYNOPSIS
    This function cleans up the bw-cli help text and parses out a secion if requested
    #>
    [OutputType([List[string]])]
    param( [string] $Command = [NullString]::Value, [string] $Section = [NullString]::Value )
    $CommandName = $Command ?? 'none'
    if ( $Script:__BWHelpText.Keys -contains $CommandName ) {
        $HelpLines = $Script:__BWHelpText[$CommandName]
    } else {
        Write-Host 'Caching help for command:' $CommandName
        $RawHelp = & $BitwardenCLI $Command --help
        [List[string]] $HelpLines = $RawHelp -join "`n" -replace "`n {10,}", ' ' -replace '^(\w+:) ', "`$1`n" -replace '  (\w+:)\s+', "`$1`n" -split "`r?`n" -replace '^\s+'
        if ( $HelpLines[3] -ne 'Options:' ) { $HelpLines.Insert(3,'Description:') }
        $Script:__BWHelpText[$CommandName] = $HelpLines
    }
    if ( $Section ) {
        $StartIndex = $HelpLines.IndexOf($Section.TrimEnd(':') + ':') + 1
        if ( $StartIndex -eq -1 ) { return }
        $EndIndex = ( $HelpLines | Select-Object -Skip $StartIndex | Where-Object { $_ -match '^\w+:$' } | Select-Object -First 1 | ForEach-Object { $HelpLines.IndexOf($_) -2 } ) ?? $HelpLines.Count - 1
        return [List[string]] $HelpLines[$StartIndex..$EndIndex]
    } else {
        return $HelpLines
    }
}

Write-Host 'Building configuration...'

$Config = [pscustomobject][ordered]@{
    Version    = $BitwardenCLIVersion
    Switches   = [List[object]]@()
    Commands   = [List[object]]@()
}

Write-Host 'Processing global switches...'

GetBWHelp -Section Options | ForEach-Object {
    if ( $_ -match '(?<Name>--\w+)(?:\s(?<Value>[\[\<]\w+[\]>]))?\s{2,}' ) {
        $Config.Switches.Add([pscustomobject][ordered]@{
            Name   = $Matches.Name
            Values = $BWEnums.Keys -contains $Matches.Name ? $BWEnums[$Matches.Name] : ( $Matches.Value ? @('') : $null )
        })
    }
}

Write-Host 'Processing commands...'

GetBWHelp -Section Commands | ForEach-Object {

    $CommandName = $_.Split(' ',2)[0]

    Write-Host 'Command:' $CommandName
    
    $CommandConfig = [pscustomobject][ordered]@{
        Name       = $CommandName
        Switches   = [List[object]]@()
        Params     = [List[object]]@()
    }

    Write-Host '  Processing command switches...'

    GetBWHelp $CommandName -Section Options | ForEach-Object {
        if ( $_ -match '(?<Name>--\w+)(?:\s(?<Value>[\[\<]\w+[\]>]))?\s{2,}' ) {
            $CommandConfig.Switches.Add([pscustomobject][ordered]@{
                Name   = $Matches.Name
                Values = $BWEnums.Keys -contains $Matches.Name ? $BWEnums[$Matches.Name] : ( $Matches.Value ? @('') : $null )
            })
        }
    }

    Write-Host '  Getting command parameter arguments...'

    [string[]] $CommandParamArgs = GetBWHelp $CommandName -Section Arguments

    Write-Host '  Getting command parameters...'

    GetBWHelp $CommandName -Section Usage |
        ForEach-Object { $_.Split(' ').Trim([char[]]'[]<>') } |
        Select-Object -Skip 3 |
        ForEach-Object {
            $CommandParamLine = $CommandParamArgs -like "$_*" | Select-Object -First 1
            [string[]] $CommandParamOptions = @('')
            if ( $CommandParamLine -and $CommandParamLine.IndexOf(':') -ne -1 ) {
                [string[]] $CommandParamOptions = $CommandParamLine.Split(':',2)[1].Trim().Split(',').Trim()
            }
            $CommandConfig.Params.Add([pscustomobject][ordered]@{
                Name = $_
                Values = $CommandParamOptions
            })
        }
    
    $Config.Commands.Add($CommandConfig)

    Write-Host '  Done with command.'

}

Write-Host 'Converting to JSON...'

$JsonConfig = $Config | ConvertTo-Json -Depth 99 -Compress

$ModulePath = Join-Path $RepoRoot 'src' 'BitwardenWrapper'
$ModuleFile = Join-Path $ModulePath 'BitwardenWrapper.psm1'
$ManifestFile = Join-Path $ModulePath 'BitwardenWrapper.psd1'

Write-Host 'Updating module...'

$ModuleContent = Get-Content -Path $ModuleFile
$ModuleContent | Where-Object { $_ -match '^(\s+\$AutoCompleteJson = )' } | ForEach-Object {
    $LineIndex = $ModuleContent.IndexOf($_)
    $ModuleContent[$LineIndex] = $Matches[1] + "'$JsonConfig'"
}
$ModuleContent | Set-Content -Path $ModuleFile

Write-Host 'Updating manifest...'

$ManifestContent = Get-Content -Path $ManifestFile
$ManifestContent | Where-Object { $_ -match '^(ModuleVersion = )' } | ForEach-Object {
    $LineIndex = $ManifestContent.IndexOf($_)
    $ManifestContent[$LineIndex] = $Matches[1] + "'$BitwardenCLIVersion'"
}
$ManifestContent | Set-Content -Path $ManifestFile

Write-Host 'Done'
