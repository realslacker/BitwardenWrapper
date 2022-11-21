# BitwardenWrapper
Wrapper module for Bitwarden CLI bw.exe. Includes parameter completion and type juggling for output.

## Features

* JSON output automatically converted to PSCustomObjects
* Passwords automatically converted to SecureString
* PSCredential objects added to output
* Login and Unlock automatically create $env:BW_SESSION
* Session key stored in cli-xml and used across windows automatically
* Parameter completion for bw.exe parameters
* Installer function

## Installation
Install from the PSGallery

```powershell
Install-Module -Name BitwardenWrapper -Force
```

## Security
To support auto-lock on Windows you can import a scheduled task that will lock bw-cli on workstation
lock, or shutdown.

[Windows Scheduled Task Definition](task/Bitwarden CLI Auto-Lock.xml)

If anyone can contribute a similar file for MacOS or Linux please make a PR.