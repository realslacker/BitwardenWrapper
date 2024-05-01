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

# the bw-cli version the module was built against
# NOTE: The following line is updated programatically, do not change spacing
[version] $BitwardenCLIVersion = '2024.3.1'

# NOTE: Cannot use Join-Path with more than two arguments in PowerShell < 6.0
$ModuleCacheFolder = [IO.Path]::Combine( '~', '.config', 'BitwardenWrapper' )
if ( -not( Test-Path -Path $ModuleCacheFolder ) ) {
    New-Item -Path $ModuleCacheFolder -ItemType Directory -ErrorAction Stop > $null
}

if ( -not $env:BITWARDENCLI_APPDATA_DIR ) {

    # tell bitwarden where to store data
    $env:BITWARDENCLI_APPDATA_DIR = [IO.Path]::Combine( ( $ModuleCacheFolder | Resolve-Path | Convert-Path ), 'appdata' )

}

# file indication that bitwarden is unlocked
# allows sharing lock status across sessions
$UnlockedFile = [IO.Path]::Combine( $env:BITWARDENCLI_APPDATA_DIR, '.unlocked' )

# file storing session key
$SessionXmlPath = [IO.Path]::Combine( $env:BITWARDENCLI_APPDATA_DIR, 'session.xml' )
if ( -not( Test-Path Env:\BW_SESSION ) -and ( Test-Path $SessionXmlPath -PathType Leaf ) ) {
    $env:BW_SESSION = (Import-Clixml -Path $SessionXmlPath).GetNetworkCredential().Password
}

# if a bw application exists in the Cache folder we'll use
# that, otherwise use the version that matches this module
$BitwardenCLI = Get-Command ([IO.Path]::Combine( $ModuleCacheFolder, 'bw' )) -CommandType Application -ErrorAction SilentlyContinue
if ( -not $BitwardenCLI ) {

    $Platform = 'Unsupported'
    if ( $PSVersionTable.PSVersion -lt '6.0' ) {
        # NOTE: only set on Windows PowerShell where this variable otherwise doesn't exist
        [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingCmdletAliases', '', Scope='Function')]
        $IsWindows = $true
        $Platform = 'Windows'
    }
    if ( $IsMacOS   ) { $Platform = 'MacOS'   }
    if ( $IsLinux   ) { $Platform = 'Linux'   }
    if ( $IsWindows ) { $Platform = 'Windows' }
    if ( $Platform -eq 'Unsupported' ) {
        Write-Error "You appear to be using an unsupported platform. Please manually install a bw-cli binary into $ModuleCacheFolder." -ErrorAction Stop
    }

    $DefaultPath = [IO.Path]::Combine( $ModuleCacheFolder, ( 'bw' + ('','.exe')[$IsWindows] ) )
    $TargetPath  = [IO.Path]::Combine( $ModuleCacheFolder, ( 'bw-v' + $BitwardenCLIVersion + ('','.exe')[$IsWindows] ) )

    if ( Test-Path -Path $TargetPath ) {

        $BitwardenCLI = Get-Command $TargetPath -CommandType Application -ErrorAction Stop

    } else {

        Write-Warning "Downloading Bitwarden CLI v$BitwardenCLIVersion..."

        $DownloadUri = "https://github.com/bitwarden/clients/releases/download/cli-v{0}/bw-{1}-{0}.zip" -f $BitwardenCLIVersion, $Platform.ToLower()
        $DownloadPath = [IO.Path]::Combine( $ModuleCacheFolder, 'bw-cli.zip' )
    
        Invoke-WebRequest -UseBasicParsing -Uri $DownloadUri -OutFile $DownloadPath

        Expand-Archive -Path $DownloadPath -DestinationPath $ModuleCacheFolder -Force
        Remove-Item -Path $DownloadPath -Force -Confirm:$false -ErrorAction SilentlyContinue
        Get-Item -Path $DefaultPath | Move-Item -Destination $TargetPath
        if ( $Platform -ne 'Windows' ) {
            chmod +x $TargetPath
        }
    
        $BitwardenCLI = Get-Command $TargetPath -CommandType Application -ErrorAction Stop

    }

}

New-Alias -Name 'bw-cli' -Value $BitwardenCLI.Path

[version] $BitwardenCLIVersionAvailable = & $BitwardenCLI --version
if ( $BitwardenCLIVersionAvailable -lt $BitwardenCLIVersion ) {
    Write-Warning ( 'The version of bw-cli is lower than the version tested with this module. Please update ''{0}'' to version {1}.' -f $BitwardenCLI.Path, $BitwardenCLIVersion )
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
    process {

        [System.Collections.Generic.List[string]]$ArgumentsList = $args

        # run bw and capture result
        if ( $_ ) {
            [string[]] $Result = $_ | & $Script:BitwardenCLI @ArgumentsList
        } else {
            [string[]] $Result = & $Script:BitwardenCLI @ArgumentsList
        }

        # remove the .unlocked file if the command is lock
        # unlocked file just used to allow easy detection of
        # lock status for prompt decoration and auto locking
        # scripts
        if ( $ArgumentsList.IndexOf('lock') -ge 0 ) {
            Remove-Item $Script:UnlockedFile -ErrorAction SilentlyContinue
        }
        
        # if --raw is specified we just return the result
        # without doing any post processing
        if ( $ArgumentsList.IndexOf('--raw') -ge 0 ) { return $Result }
        
        # try to parse the result as JSON
        try {

            $DepthSplat = @{}
            if ( (Get-Command ConvertFrom-Json).Parameters.ContainsKey('Depth') ) {
                $DepthSplat.Depth = 99
            }
        
            [object[]]$JsonResult = $Result | ConvertFrom-Json @DepthSplat -ErrorAction SilentlyContinue
            
        } catch {
        
            Write-Verbose 'JSON Parse Message:'
            Write-Verbose $_.Exception.Message
        
        }

        # if parsing is successful we do some post processing
        if ( $JsonResult ) {

            Write-Verbose 'Processing JSON output...'

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
                        New-Item $Script:UnlockedFile -Force > $null
                    } else {
                        Remove-Item $Script:UnlockedFile -ErrorAction SilentlyContinue
                    }
                }

                $_

            })

        }
        
        else {

            Write-Verbose 'Processing text output...'

            # look for session key
            if ( $Result -and $Result[-1] -like '*--session*' ) {

                Write-Verbose 'Found session key, unlocking...'

                New-Item $Script:UnlockedFile -Force > $null

                $env:BW_SESSION = $Result[-1].Trim().Split(' ')[-1]

                # export session key into cache
                [pscredential]::new( 'SessionKey', ( $env:BW_SESSION | ConvertTo-SecureString -AsPlainText -Force) ) | Export-Clixml -Path $Script:SessionXmlPath

                $Result[0]

            } else {

                $Result

            }

        }

    }

}

if ( $IsWindows ) {
    New-Alias -Name 'bw.exe' -Value 'bw'
}


# Scriptblock for Test-BWAutoComplete and the argument completer
$AutoCompleteScript = {
    param( $WordToComplete, $CommandAst, $CursorPosition )

    # Instantiate the AutoComplete configuration
    # NOTE: The following line is updated programatically, do not change spacing
    $AutoCompleteJson = '{"Version":"2024.3.1","Switches":[{"Name":"--pretty","Values":null},{"Name":"--raw","Values":null},{"Name":"--response","Values":null},{"Name":"--cleanexit","Values":null},{"Name":"--quiet","Values":null},{"Name":"--nointeraction","Values":null},{"Name":"--session","Values":[""]},{"Name":"--version","Values":null},{"Name":"--help","Values":null}],"Commands":[{"Name":"login","Switches":[{"Name":"--method","Values":[0,1,3]},{"Name":"--code","Values":[""]},{"Name":"--sso","Values":null},{"Name":"--apikey","Values":null},{"Name":"--passwordenv","Values":[""]},{"Name":"--passwordfile","Values":[""]},{"Name":"--check","Values":null},{"Name":"--help","Values":null}],"Params":[{"Name":"email","Values":[""]},{"Name":"password","Values":[""]}]},{"Name":"logout","Switches":[{"Name":"--help","Values":null}],"Params":[]},{"Name":"lock","Switches":[{"Name":"--help","Values":null}],"Params":[]},{"Name":"unlock","Switches":[{"Name":"--check","Values":null},{"Name":"--passwordenv","Values":[""]},{"Name":"--passwordfile","Values":[""]},{"Name":"--help","Values":null}],"Params":[{"Name":"password","Values":[""]}]},{"Name":"sync","Switches":[{"Name":"--force","Values":null},{"Name":"--last","Values":null},{"Name":"--help","Values":null}],"Params":[]},{"Name":"generate","Switches":[{"Name":"--uppercase","Values":null},{"Name":"--lowercase","Values":null},{"Name":"--number","Values":null},{"Name":"--special","Values":null},{"Name":"--passphrase","Values":null},{"Name":"--length","Values":[""]},{"Name":"--words","Values":[""]},{"Name":"--minNumber","Values":[""]},{"Name":"--minSpecial","Values":[""]},{"Name":"--separator","Values":[""]},{"Name":"--capitalize","Values":null},{"Name":"--includeNumber","Values":null},{"Name":"--ambiguous","Values":null},{"Name":"--help","Values":null}],"Params":[]},{"Name":"encode","Switches":[{"Name":"--help","Values":null}],"Params":[]},{"Name":"config","Switches":[{"Name":"--api","Values":[""]},{"Name":"--identity","Values":[""]},{"Name":"--icons","Values":[""]},{"Name":"--notifications","Values":[""]},{"Name":"--events","Values":[""]},{"Name":"--help","Values":null}],"Params":[{"Name":"setting","Values":[""]},{"Name":"value","Values":[""]}]},{"Name":"update","Switches":[{"Name":"--help","Values":null}],"Params":[]},{"Name":"completion","Switches":[{"Name":"--shell","Values":"zsh"},{"Name":"--help","Values":null}],"Params":[]},{"Name":"status","Switches":[{"Name":"--help","Values":null}],"Params":[]},{"Name":"serve","Switches":[{"Name":"--hostname","Values":[""]},{"Name":"--port","Values":[""]},{"Name":"--help","Values":null}],"Params":[]},{"Name":"list","Switches":[{"Name":"--search","Values":[""]},{"Name":"--url","Values":[""]},{"Name":"--folderid","Values":[""]},{"Name":"--collectionid","Values":[""]},{"Name":"--organizationid","Values":[""]},{"Name":"--trash","Values":null},{"Name":"--help","Values":null}],"Params":[{"Name":"object","Values":["items","folders","collections","org-collections","org-members","organizations"]}]},{"Name":"get","Switches":[{"Name":"--itemid","Values":[""]},{"Name":"--output","Values":[""]},{"Name":"--organizationid","Values":[""]},{"Name":"--help","Values":null}],"Params":[{"Name":"object","Values":["item","username","password","uri","totp","notes","exposed","attachment","folder","collection","org-collection","organization","template","fingerprint","send"]},{"Name":"id","Values":[""]}]},{"Name":"create","Switches":[{"Name":"--file","Values":[""]},{"Name":"--itemid","Values":[""]},{"Name":"--organizationid","Values":[""]},{"Name":"--help","Values":null}],"Params":[{"Name":"object","Values":["item","attachment","folder","org-collection"]},{"Name":"encodedJson","Values":[""]}]},{"Name":"edit","Switches":[{"Name":"--organizationid","Values":[""]},{"Name":"--help","Values":null}],"Params":[{"Name":"object","Values":["item","item-collections","folder","org-collection"]},{"Name":"id","Values":[""]},{"Name":"encodedJson","Values":[""]}]},{"Name":"delete","Switches":[{"Name":"--itemid","Values":[""]},{"Name":"--organizationid","Values":[""]},{"Name":"--permanent","Values":null},{"Name":"--help","Values":null}],"Params":[{"Name":"object","Values":["item","attachment","folder","org-collection"]},{"Name":"id","Values":[""]}]},{"Name":"restore","Switches":[{"Name":"--help","Values":null}],"Params":[{"Name":"object","Values":["item"]},{"Name":"id","Values":[""]}]},{"Name":"move","Switches":[{"Name":"--help","Values":null}],"Params":[{"Name":"id","Values":[""]},{"Name":"organizationId","Values":[""]},{"Name":"encodedJson","Values":[""]}]},{"Name":"confirm","Switches":[{"Name":"--organizationid","Values":[""]},{"Name":"--help","Values":null}],"Params":[{"Name":"object","Values":["org-member"]},{"Name":"id","Values":[""]}]},{"Name":"import","Switches":[{"Name":"--formats","Values":null},{"Name":"--organizationid","Values":[""]},{"Name":"--help","Values":null}],"Params":[{"Name":"format","Values":[""]},{"Name":"input","Values":[""]}]},{"Name":"export","Switches":[{"Name":"--output","Values":[""]},{"Name":"--format","Values":["csv","json"]},{"Name":"--password","Values":[""]},{"Name":"--organizationid","Values":[""]},{"Name":"--help","Values":null}],"Params":[]},{"Name":"share","Switches":[{"Name":"--help","Values":null}],"Params":[{"Name":"id","Values":[""]},{"Name":"organizationId","Values":[""]},{"Name":"encodedJson","Values":[""]}]},{"Name":"send","Switches":[{"Name":"--file","Values":null},{"Name":"--deleteInDays","Values":[""]},{"Name":"--maxAccessCount","Values":[""]},{"Name":"--hidden","Values":null},{"Name":"--name","Values":[""]},{"Name":"--notes","Values":[""]},{"Name":"--fullObject","Values":null},{"Name":"--help","Values":null}],"Params":[{"Name":"command","Values":[""]},{"Name":"data","Values":[""]}]},{"Name":"receive","Switches":[{"Name":"--password","Values":[""]},{"Name":"--passwordenv","Values":[""]},{"Name":"--passwordfile","Values":[""]},{"Name":"--obj","Values":null},{"Name":"--output","Values":[""]},{"Name":"--help","Values":null}],"Params":[{"Name":"url","Values":[""]}]},{"Name":"help","Switches":[{"Name":"--pretty","Values":null},{"Name":"--raw","Values":null},{"Name":"--response","Values":null},{"Name":"--cleanexit","Values":null},{"Name":"--quiet","Values":null},{"Name":"--nointeraction","Values":null},{"Name":"--session","Values":[""]},{"Name":"--version","Values":null},{"Name":"--help","Values":null}],"Params":[]}]}'
    $AutoCompleteConfiguration = $AutoCompleteJson | ConvertFrom-Json -Depth 99

    # trim off the command name and the $WordToComplete
    $ArgumentsList = $CommandAst -replace '^bw(?:\.exe)?\s+' -replace "\s*$WordToComplete$"

    # split the $ArgumentsList into an array
    [string[]] $ArgumentsArray = Invoke-Expression "&{`$args} $ArgumentsList"

    # filter for returned values
    $MatchFilter = { $_ -notin $ArgumentsArray -and $_ -like "$WordToComplete*" }

    # check for the current command, returns first command that appears in the
    # $ArgumentsArray ignoring parameters any other strings
    $CurrentCommand = $AutoCompleteConfiguration.Commands | Where-Object { $ArgumentsArray -contains $_.Name }
    $CurrentSwitch = $null

    # if there are elements in the ArgumentsArray get the current switch argument
    # if it requires a value be provided
    if ( $ArgumentsArray.Count -ne 0 ) {
        
        if ( $CurrentCommand ) {
            $CurrentSwitch = $CurrentCommand.Switches | Where-Object { $_.Name -eq $ArgumentsArray[-1] -and $null -ne $_.Values } | Select-Object -First 1
        } else {
            $CurrentSwitch = $AutoCompleteConfiguration.Switches | Where-Object { $_.Name -eq $ArgumentsArray[-1] -and $null -ne $_.Values } | Select-Object -First 1
        }

        # if the last argument is a switch with a completer then we do that
        if ( $CurrentSwitch ) {
            if ( $CurrentSwitch.Values ) {
                return $CurrentSwitch.Values |
                    Where-Object $MatchFilter
            }
            return $WordToComplete
        }

    }

    # if the $ArgumentsArray is empty OR there is no $CurrentCommand then we
    # output all of the commands and common parameters that match the last
    # $WordToComplete
    if ( $ArgumentsArray.Count -eq 0 -or -not $CurrentCommand ) {

        return $AutoCompleteConfiguration.Commands.Name + $AutoCompleteConfiguration.Switches.Name |
            Where-Object $MatchFilter

    }

    # if the last complete argument is the command name and there are params for this
    # command then we want to force parameter configuration
    [string[]] $NonSwitchParamsAfterCommand = $ArgumentsArray | Select-Object -Skip ( $ArgumentsArray.IndexOf($CurrentCommand.Name) + 1 ) | Where-Object { $_ -notlike '--*' }
    if ( $WordToComplete -notlike '-*' -and $NonSwitchParamsAfterCommand.Count -lt $CurrentCommand.Params.Count ) {
        $CurrentParam = $CurrentCommand.Params | Select-Object -Skip $NonSwitchParamsAfterCommand.Count -First 1
        if ( $CurrentParam.Values ) {
            return $CurrentParam.Values |
                Where-Object $MatchFilter
        }
        return $WordToComplete
    }

    # if we get here then all we have left is switches for the current command
    return $CurrentCommand.Switches.Name |
        Where-Object $MatchFilter

}

Register-ArgumentCompleter -CommandName bw -ScriptBlock $AutoCompleteScript
Register-ArgumentCompleter -CommandName bw-cli -ScriptBlock $AutoCompleteScript

# testing script, not exported by default
New-Item -Path Function:\Test-BWAutoComplete -Value $AutoCompleteScript

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
