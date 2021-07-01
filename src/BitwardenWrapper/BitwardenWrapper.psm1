[version]$SupportedVersion = '1.16'

# check if we should use a specific bw.exe
if ( $env:BITWARDEN_CLI_PATH ) {

    $BitwardenCLI = Get-Command $env:BITWARDEN_CLI_PATH -CommandType Application -ErrorAction SilentlyContinue

} else {

    $BitwardenCLI = Get-Command -Name bw.exe -CommandType Application -ErrorAction SilentlyContinue

}

if ( -not $BitwardenCLI ) {

    Write-Warning 'No Bitwarden CLI found in your path, either specify $env:BITWARDEN_CLI_PATH or put bw.exe in your path. You can use Install-BitwardenCLI to install to C:\Windows\System32'

}

if ( $BitwardenCLI -and $BitwardenCLI.Version -lt $SupportedVersion ) {

    Write-Warning "Your Bitwarden CLI is version $($BitwardenCLI.Version) and out of date, please upgrade to at least version $SupportedVersion."

}

<#
.SYNOPSIS
 Helper function to install bw.exe to $env:windir\system32

.DESCRIPTION
 Helper function to install bw.exe to $env:windir\system32

.PARAMETER Force
 Install even if bw.exe is present
#>
function Install-BitwardenCLI {

    param( [switch]$Force )

    $ErrorActionPreference = 'Stop'

    if ( -not [environment]::Is64BitOperatingSystem ) {

        Write-Error "Cannot install on 32-bit OS"
        return

    }

    if ( -not $Force -and ( $bw = Get-Command -Name bw.exe -CommandType Application -ErrorAction SilentlyContinue ) ) {

        Write-Warning "Bitwarden CLI already installed to $($bw.Path), use -Force to install anyway"
        return

    }

    $TempPath = New-TemporaryFile | ForEach-Object { Rename-Item -Path $_.FullName -NewName $_.Name.Replace( $_.Extension, '.zip' ) -PassThru }

    Invoke-WebRequest -UseBasicParsing -Uri 'https://vault.bitwarden.com/download/?app=cli&platform=windows' -OutFile $TempPath.FullName

    Expand-Archive -Path $TempPath -DestinationPath $env:TEMP -Force

    Start-Process -FilePath powershell.exe -ArgumentList "-NoProfile -NonInteractive -NoExit -Command ""Move-Item -Path '$env:TEMP\bw.exe' -Destination '$env:windir\System32\bw.exe' -Confirm:`$false -Force""" -Verb RunAs -Wait

    $Script:BitwardenCLI = Get-Command "$env:windir\System32\bw.exe" -CommandType Application -ErrorAction Stop

}

<#
.SYNOPSIS
 The Bitwarden command-line interface (CLI) is a powerful, fully-featured tool for accessing and managing your Vault.

.DESCRIPTION
 The Bitwarden command-line interface (CLI) is a powerful, fully-featured tool for accessing and managing your Vault.
 Most features that you find in other Bitwarden client applications (Desktop, Browser Extension, etc.) are available
 from the CLI. The Bitwarden CLI is self-documented. From the command line, learn about the available commands using:
 bw --help

#>
function bw {

    if ( -not $BitwardenCLI ) {

        Write-Error "Bitwarden CLI is not installed!"
        return

    }

    [System.Collections.Generic.List[string]]$ArgumentsList = $args

    if ( ( $ArgumentsList.Contains('unlock') -or $ArgumentsList.Contains('login') ) -and $ArgumentsList.Contains('--raw') ) {

        $ArgumentsList.RemoveAt( $ArgumentsList.IndexOf('--raw') )

    }

    [string[]]$Result = & $BitwardenCLI @ArgumentsList

    try {
    
        [object[]]$JsonResult = $Result | ConvertFrom-Json
        
    } catch {
    
        Write-Verbose "JSON Parse Message:"
        Write-Verbose $_.Exception.Message
    
    }

    if ( $JsonResult ) {

        $JsonResult.Where({ $_.login }).ForEach({
        
            $_.login.password = ConvertTo-SecureString -String $_.login.password -AsPlainText -Force

            $_.login | Add-Member -MemberType NoteProperty -Name credential -Value ([pscredential]::new( $_.login.username, $_.login.password ))

        })

        $JsonResult.fields.Where({ $_.type -eq 1 }).ForEach({
        
            $_.value = ConvertTo-SecureString -String $_.value -AsPlainText -Force
        
        })

        $JsonResult.Where({ $_.passwordHistory }).passwordHistory.ForEach({
        
            $_.password = ConvertTo-SecureString -String $_.password -AsPlainText -Force
            
        })

        return $JsonResult

    } else {

        # look for session key
        if ( $Result -and $Result[-1] -like '*--session*' ) {

            $env:BW_SESSION = $Result[-1].Trim().Split(' ')[-1]
            return $Result[0]

        } else {

            return $Result

        }

    }

}

New-Alias -Name 'bw.exe' -Value 'bw'

Register-ArgumentCompleter -CommandName bw -ScriptBlock {

    param(
        $WordToComplete,
        $CommandAst,
        $CursorPosition
    )

    $__Commands = @{
        login          = '--raw --method --code --sso --check --help'
        logout         = '--help'
        lock           = '--help'
        unlock         = '--check --raw --help'
        sync           = '--force --last --help'
        list           = '--search --url --folderid --collectionid --organizationid --trash --help'
        get            = '--itemid --output --organizationid --help'
        create         = '--file --itemid --organizationid --help'
        edit           = '--organizationid --help'
        delete         = '--itemid --organizationid --permanent --help'
        restore        = '--help'
        share          = '--help'
        confirm        = '--organizationid --help'
        import         = '--formats --help'
        export         = '--output --format --organizationid --help'
        generate       = '--uppercase --lowercase --number --special --passphrase --length --words --separator --help'
        encode         = '--help'
        config         = '--web-vault --api --identity --icons --notifications --events --help'
        update         = '--raw --help'
        completion     = '--shell --help'
        status         = '--help'
    }

    $__CommandAutoComplete = @{
        list           = 'items folders collections organizations org-collections org-members'
        get            = 'item username password uri totp exposed attachment folder collection org-collection organization template fingerprint'
        create         = 'item attachment folder org-collection'
        edit           = 'item item-collections folder org-collection'
        delete         = 'item attachment folder org-collection'
        restore        = 'item'
        confirm        = 'org-member'
        import         = '1password1pif 1passwordwincsv ascendocsv avastcsv avastjson aviracsv bitwardencsv bitwardenjson blackberrycsv blurcsv buttercupcsv chromecsv clipperzhtml codebookcsv dashlanejson encryptrcsv enpasscsv enpassjson firefoxcsv fsecurefsk gnomejson kasperskytxt keepass2xml keepassxcsv keepercsv lastpasscsv logmeoncecsv meldiumcsv msecurecsv mykicsv operacsv padlockcsv passboltcsv passkeepcsv passmanjson passpackcsv passwordagentcsv passwordbossjson passworddragonxml passwordwallettxt pwsafexml remembearcsv roboformcsv safeincloudxml saferpasscsv securesafecsv splashidcsv stickypasswordxml truekeycsv upmcsv vivaldicsv yoticsv zohovaultcsv'
        config         = 'server'
        '--method'     = '0 1 3'
        '--format'     = 'csv json'
        '--shell'      = 'zsh'
    }

    $__CommonParams    = '--pretty --raw --response --quiet --nointeraction --session --version --help'

    $__HasCompleter    = 'list get create edit delete restore confirm import config ' +     # commands with auto-complete
                         '--session ' +                                                     # provide session variable
                         '--method --code ' +                                               # login
                         '--search --url --folderid --collectionid --organizationid ' +     # list
                         '--itemid --output ' +                                             # get
                         '--format ' +                                                      # export
                         '--length --words --separator ' +                                  # generate
                         '--web-vault --api --identity --icons --notifications --events ' + # config
                         '--shell'                                                          # completion

    function ConvertTo-ArgumentsArray {

        function __args { $args }

        Invoke-Expression "__args $args"

    }

    $InformationPreference = 'Continue'
    $ConsoleWidth = $Host.UI.RawUI.BufferSize.Width - 2

    # trim off the command name and the $WordToComplete
    $ArgumentsList = $CommandAst -replace '^bw(.exe)?\s+' -replace "\s+$WordToComplete$"

    # split the $ArgumentsList into an array
    [string[]]$ArgumentsArray = ConvertTo-ArgumentsArray $ArgumentsList

    # check for the current command, returns first command that appears in the
    # $ArgumentsArray ignoring parameters any other strings
    $CurrentCommand = $ArgumentsArray |
        Where-Object { $_ -in $__Commands.Keys } |
        Select-Object -First 1

    # if the $ArgumentsArray is empty OR there is no $CurrentCommand then we
    # output all of the commands and common parameters that match the last
    # $WordToComplete
    if ( $ArgumentsArray.Count -eq 0 -or -not $CurrentCommand ) {

        return $__Commands.Keys + $__CommonParams.Split(' ') |
            Where-Object { $_ -notin $ArgumentsArray } |
            Where-Object { $_ -like "$WordToComplete*" }
    
    }

    # if the last complete argument has auto-complete options then we output
    # the auto-complete option that matches the $LastChunk
    if ( $ArgumentsArray[-1] -in $__HasCompleter.Split(' ') ) {

        # if the last complete argument exists in the $__CommandAutoComplete
        # hashtable keys then we return the options
        if ( $ArgumentsArray[-1] -in $__CommandAutoComplete.Keys ) {

            return $__CommandAutoComplete[ $ArgumentsArray[-1] ].Split(' ') |
                Where-Object { $_ -like "$WordToComplete*" }

        }
    
        # if it doesn't have a key then we just want to pause for user input
        # so we return an empty string. this pauses auto-complete until the
        # user provides input.
        else {
    
            return @( '' )

        }

    }

    # finally if $CurrentCommand is set and the current option doesn't have
    # it's own auto-complete we return the remaining options in the current
    # command's auto-complete list
    return $__Commands[ $CurrentCommand ].Split(' ') |
        Where-Object { $_ -notin $ArgumentsArray } |
        Where-Object { $_ -like "$WordToComplete*" }

}
