enum BitwardenMfaMethod {
    Authenticator   = 0
    Email           = 1
    Yubikey         = 2
}

enum BitwardenItemType {
    Undefined       = 0
    Login           = 1
    SecureNote      = 2
    Card            = 3
    Identity        = 4
}

enum BitwardenUriMatchType {
    Domain          = 0
    Host            = 1
    StartsWith      = 2
    Exact           = 3
    Regex           = 4
    Never           = 5
}

enum BitwardenFieldType {
    Text            = 0
    Hidden          = 1
    Boolean         = 2
}

enum BitwardenOrganizationUserType {
    Owner           = 0
    Admin           = 1
    User            = 2
    Manager         = 3
}

enum BitwardenOrganizationUserStatus {
    Invited         = 0
    Accepted        = 1
    Confirmed       = 2
}

function Install-BitwardenCLI {
    <#
    .SYNOPSIS
    Helper function to install bw-cli application
    .DESCRIPTION
    Helper function to install bw-cli application
    .PARAMETER Path
    Where to install the bw-cli application
    .PARAMETER Platform
    Which platform binary should be downloaded
    .PARAMETER Force
    Install even if the bw-cli application is the same or newer than the module version
    #>
    [CmdletBinding(
        SupportsShouldProcess,
        ConfirmImpact='High'
    )]
    param(

        [Parameter( Mandatory, Position=0 )]
        [Alias( 'InstallDirectory' )]
        [string]
        $Path,

        [ValidateSet( 'Windows', 'MacOS', 'Linux', 'Auto' )]
        [string]
        $Platform = 'Auto',

        [switch]
        $Force

    )

    if ( -not [environment]::Is64BitOperatingSystem ) {
        Write-Error "Cannot install on 32-bit OS"
        return
    }

    $bw = Resolve-Path -LiteralPath $Path -ErrorAction Stop |
        Get-ChildItem -Filter 'bw*' |
        Where-Object BaseName -eq 'bw' |
        Get-Command -CommandType Application

    if ( $Script:MyModuleVersion -le $bw.Version -and -not $Force ) {
        Write-Warning ( 'Installed version v{0} is the same or newer than the module version. Use -Force to install anyway.' -f $bw.Version )
        return
    }

    $VerboseDescription = 'Current version of Bitwarden CLI installed at "{0}" will be replaced.' -f $bw.FullName
    $VerboseWarning = 'Bitwarden CLI v{0} already installed at "{1}", replace?' -f $bw.Version, $bw.Path
    $Caption = 'Update Bitwarden CLI'

    if ( $bw -and -not $PSCmdlet.ShouldProcess( $VerboseDescription, $VerboseWarning, $Caption ) ) { return }

    if ( $Platform -eq 'Auto' -and $IsMacOS ) { $Platform = 'MacOS' }
    if ( $Platform -eq 'Auto' -and $IsLinux ) { $Platform = 'Linux' }
    if ( $Platform -eq 'Auto' -and $IsWindows ) { $Platform = 'Windows' }
    if ( $Platform -eq 'Auto' ) {
        Write-Error 'Failed to detect platform!' -ErrorAction Stop
    }

    $TempPath = New-TemporaryFile | ForEach-Object { Rename-Item -Path $_.FullName -NewName $_.Name.Replace( $_.Extension, '.zip' ) -PassThru }

    $DownloadUri = 'https://vault.bitwarden.com/download/?app=cli&platform={0}' -f $Platform.ToLower()
    
    Invoke-WebRequest -UseBasicParsing -Uri $DownloadUri -OutFile $TempPath.FullName

    Expand-Archive -Path $TempPath -DestinationPath $env:TEMP -Force

    Move-Item $TempPath.FullName -Destination $Path -Confirm:$false -ErrorAction Stop
    
    $Script:BitwardenCLI = Get-Command "$Path\bw.exe" -CommandType Application -ErrorAction Stop

}

function Get-BitwardenCLI {
    [CmdletBinding()]
    [OutputType( [System.Management.Automation.ApplicationInfo] )]
    param()

    if ( -not $Script:BitwardenCLI ) {
    
        # check if we should use a specific bw.exe
        if ( $env:BITWARDEN_CLI_PATH ) {
            $Script:BitwardenCLI = Get-Command $env:BITWARDEN_CLI_PATH -CommandType Application -ErrorAction SilentlyContinue
        }
        # otherwise we use whatever we can find on the path
        else {
            $Script:BitwardenCLI = Get-Command -Name bw -CommandType Application -ErrorAction SilentlyContinue
        }

    }

    if ( $Script:BitwardenCLI ) {
        return $Script:BitwardenCLI
    }
    else {
        Write-Error "Bitwarden CLI is not installed!"
        return
    }

}

function Test-BitwardenCLIVersionCurrent {
    [CmdletBinding()]
    param()

    if ( -not $Script:ModuleVersion ) {
        [version]$Script:ModuleVersion = Import-PowerShellDataFile -Path (Get-PSCallStack)[0].ScriptName.Replace('.psm1', '.psd1') -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ModuleVersion
    }

    [version]$CliVersion = bw --version --raw

    $VersionIsCurrent = $CliVersion -ge $Script:ModuleVersion

    if ( $VersionIsCurrent ) {
        Write-Information ( 'Your Bitwarden CLI v{0} is current.' -f $CliVersion )
    }
    else {
        Write-Warning ( 'Your Bitwarden CLI v{0} is out of date, please upgrade to at least v{1}.' -f $CliVersion, $ModuleVersion )
    }

    return $VersionIsCurrent

}

function bw {
    <#
    .SYNOPSIS
    The Bitwarden command-line interface (CLI) is a powerful, fully-featured tool for accessing and managing your Vault.
    .DESCRIPTION
    The Bitwarden command-line interface (CLI) is a powerful, fully-featured tool for accessing and managing your Vault.
    Most features that you find in other Bitwarden client applications (Desktop, Browser Extension, etc.) are available
    from the CLI. The Bitwarden CLI is self-documented. From the command line, learn about the available commands using:
    bw --help
    #>

    $bw = Get-BitwardenCLI -ErrorAction Stop
    
    [System.Collections.Generic.List[string]]$ArgumentsList = $args

    $SessionParams = @()
    
    if ( $ArgumentsList.Contains('--session') ) {
        $SessionParamIndex = $ArgumentsList.IndexOf('--session')
        $SessionParams = @(
            '--session',
            $ArgumentsList[ $SessionParamIndex + 1 ]
        )
        $ArgumentsList.RemoveRange( $SessionParamIndex, 2 )
    }
    elseif ( $env:BW_SESSION ) {
        $SessionParams = @(
            '--session',
            $env:BW_SESSION
        )
    }
    elseif ( Test-Path ~\.config\BitwardenWrapper\session.xml -PathType Leaf ) {
        $SessionParams = @(
            '--session',
            (Import-Clixml -Path ~\.config\BitwardenWrapper\session.xml).GetNetworkCredential().Password
        )
    }

    #if ( ( $ArgumentsList.Contains('unlock') -or $ArgumentsList.Contains('login') ) -and $ArgumentsList.Contains('--raw') ) {
    #    $ArgumentsList.RemoveAt( $ArgumentsList.IndexOf('--raw') )
    #}

    [string[]]$Result = & $bw @SessionParams @ArgumentsList

    if ( $ArgumentsList.IndexOf('lock') -ge 0 ) {
        Remove-Item ~\.config\BitwardenWrapper\.unlocked -ErrorAction SilentlyContinue
    }
    
    if ( $ArgumentsList.IndexOf('--raw') -ge 0 ) { return $Result }
    
    try {
    
        [object[]]$JsonResult = $Result | ConvertFrom-Json -ErrorAction SilentlyContinue
        
    } catch {
    
        Write-Verbose "JSON Parse Message:"
        Write-Verbose $_.Exception.Message
    
    }

    if ( $JsonResult ) {

        $JsonResult.ForEach({

            if ( $_.type ) {
            
                if ( $_.object -eq 'item' ) {
                    
                    [BitwardenItemType]$_.type = [int]$_.type
                
                } elseif ( $_.object -eq 'org-member' ) {
                    
                    [BitwardenOrganizationUserType]$_.type = [int]$_.type
                    [BitwardenOrganizationUserStatus]$_.status = [int]$_.status

                }

            }

            if ( $_.login ) {

                if ( $null -ne $_.login.password ) {

                    $_.login.password = ConvertTo-SecureString -String $_.login.password -AsPlainText -Force

                } else {

                    $_.login.password = [System.Security.SecureString]::new()

                }

                $_.login | Add-Member -MemberType NoteProperty -Name credential -Value ([pscredential]::new( $_.login.username, $_.login.password ))

                $_.login.uris.ForEach({ [BitwardenUriMatchType]$_.match = [int]$_.match })
            
            }

            if ( $_.passwordHistory ) {

                $_.passwordHistory.ForEach({
        
                    $_.password = ConvertTo-SecureString -String $_.password -AsPlainText -Force
                    
                })

            }

            if ( $_.identity.ssn ) {

                $_.identity.ssn = ConvertTo-SecureString -String $_.identity.ssn -AsPlainText -Force
                
            }

            if ( $_.fields ) {

                $_.fields.ForEach({

                    [BitwardenFieldType]$_.type = [int]$_.type

                    if ( $_.type -eq [BitwardenFieldType]::Hidden ) {

                        $_.value = ConvertTo-SecureString -String $_.value -AsPlainText -Force

                    }
                
                })

            }

            if ( $_.status ) {
                if ( $_.status -eq 'unlocked' ) {
                    New-Item ~\.config\BitwardenWrapper\.unlocked -Force > $null
                } else {
                    Remove-Item ~\.config\BitwardenWrapper\.locked -ErrorAction SilentlyContinue
                }
            }

            $_

        })

    }
    
    else {

        # look for session key
        if ( $Result -and $Result[-1] -like '*--session*' ) {

            New-Item ~\.config\BitwardenWrapper\.unlocked -Force > $null

            $SessionParams = @(
                '--session',
                $Result[-1].Trim().Split(' ')[-1]
            )

            [pscredential]::new( 'SessionKey', ( $SessionParams[1] | ConvertTo-SecureString -AsPlainText -Force) ) | Export-Clixml -Path ~\.config\BitwardenWrapper\session.xml
            $Result[0]

        } else {

            $Result

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
        login          = '--raw --method --code --sso --apikey --passwordenv --passwordfile --check --help'
        logout         = '--help'
        lock           = '--help'
        unlock         = '--check --passwordenv --passwordfile --raw --help'
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
        generate       = '--uppercase --lowercase --number --special --passphrase --length --words --separator --capitalize --includeNumber --help'
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

    $__CommonParams    = '--pretty --raw --response --cleanexit --quiet --nointeraction --session --version --help'

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


function Get-BWCredential {
    
    param(

        [Parameter( Position = 1)]
        [Alias( 'UserName', 'Email' )]
        [string]
        $Search,

        [string]
        $Url,

        [ValidateSet( 'Choose', 'Error' )]
        [string]
        $MultipleAction = 'Error'

    )
    
    [System.Collections.Generic.List[string]]$SearchParams = 'list', 'items'

    if ( $Search ) {
        $SearchParams.Add( '--search' )
        $SearchParams.Add( $Search )
    }

    if ( $Url ) {
        $SearchParams.Add( '--url' )
        $SearchParams.Add( $Url )
    }

    [object[]]$Result = bw @SearchParams | Where-Object { $_.login.credential }

    if ( $Result.Count -eq 0 ) {
        Write-Error 'No results returned'
        return
    }

    if ( $Result.Count -gt 1 -and $MultipleAction -eq 'Error' ) {
        Write-Error 'Multiple entries returned'
        return
    }
    
    $Result | Select-BWCredential

}

function Select-BWCredential {
    <#
    .SYNOPSIS
    Select a credential from those returned from the Bitwarden CLI
    
    .DESCRIPTION
    Select a credential from those returned from the Bitwarden CLI
    #>
    param(

        [Parameter( Mandatory = $true, ValueFromPipeline = $true )]
        [pscustomobject[]]
        $BitwardenItems

    )

    begin {

        $ChooserProperties = @(
            @{ Name = '    '     ; Expression = { '{0,3})' -f $Result.IndexOf($_)            } }
            @{ Name = 'Name'     ; Expression = { $_.name                                    } }
            @{ Name = 'UserName' ; Expression = { $_.login.username                          } }
            @{ Name = 'Uri'      ; Expression = { $_.login.uris.uri | Select-Object -First 1 } }
        )

        [System.Collections.ArrayList]$Result = @()

    }

    process {

        $BitwardenItems.Where({ $_.login }) | ForEach-Object { $Result.Add($_) > $null }

    }

    end {

        if ( $Result.Count -eq 0 ) {
            Write-Error 'No results returned'
            return
        }
        
        if ( $Result.Count -gt 1 ) {
    
            $Result | Select-Object $ChooserProperties | Format-Table | Out-Host
            
            $Selection = ( Read-Host 'Selection' ) -as [int]
    
        }
        else {

            $Selection = 0
        
        }
    
        if ( $null -eq $Result[$Selection] ) { return }

        $Credential = $Result[$Selection].login.credential

        if ( -not [string]::IsNullOrEmpty( $Result[$Selection].login.totp ) ) {
            $Credential | Add-Member -MemberType ScriptProperty -Name TOTP -Value ([scriptblock]::Create("bw get totp $($Result[$Selection].id) --raw"))
        }
    
        return $Result[$Selection].login.credential

    }

}
