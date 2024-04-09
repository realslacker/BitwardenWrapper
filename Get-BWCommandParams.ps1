$BitwardenCLI = Get-Command $env:USERPROFILE\.config\BitwardenWrapper\bw-v2024.2.1.exe

function Get-BWCommandParams {
    param([string] $Command)
    $Section = $null
    [System.Collections.Generic.List[string]] $HelpStrings = & $BitwardenCLI help $Command
    $HelpStrings.Where{ $_ -like 'Usage:*'}[0].Split(':',2)[1].Trim().Split(' ') | Select-Object -Skip 1 | ForEach-Object {
        $Type = $_.Trim([char[]]'[<>]').TrimEnd('s') | ForEach-Object { $_.Substring(0,1).ToUpper() + $_.Substring(1).ToLower() }
        Write-Host "Type: $Type"
        $Mandatory = $_[0] -eq '<'
        $StartIndex = $HelpStrings.IndexOf($HelpStrings.Where{$_ -match "^${Type}s?:"}[0])
        if ( $StartIndex -ne -1 ) {
            $i = $StartIndex+1
            while ( -not [string]::IsNullOrWhiteSpace($HelpStrings[$i]) ) {
                Write-Host "$i :" $HelpStrings[$i] -ForegroundColor DarkGray
                $Usage, [string]$HelpText = $HelpStrings[$i] -split '(?<=\S)\s{2,}' | ForEach-Object Trim
                $Usage = $Usage.Split(',')[-1].Trim()
                $Parameter, $Arguments = $Usage.Split(' ')
                [pscustomobject]@{
                    Type      = $Type
                    Parameter = $Parameter
                    Mandatory = $Mandatory
                    Arguments = [string[]]$Arguments
                    HelpText = $HelpText
                }
                $i++
            }
        }
    }
}

$TestResult = Get-BWCommandParams