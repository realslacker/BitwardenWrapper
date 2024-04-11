# BitwardenWrapper
Wrapper module for Bitwarden CLI bw.exe. Includes parameter completion and type juggling for output.

## Features

* JSON output automatically converted to PSCustomObjects
* Passwords automatically converted to SecureString
* PSCredential objects added to output
* Login and Unlock automatically
* Session key stored in cli-xml and used across windows automatically
* Parameter completion for bw.exe parameters
* Installer function

## Installation
Install from the PSGallery

```powershell
Install-Module -Name BitwardenWrapper -Force
```
## Usage
Loading the module should automatically install the matching bw-cli binary from Bitwarden's site.

After loading you can use bw and bw.exe on Windows for auto-complete and object conversion, or bw-cli
for original functionality with auto-complete only.

## Security
To support auto-lock on Windows you can import a scheduled task that will lock bw-cli on workstation
lock, or shutdown.

[Windows Scheduled Task Definition](task/Bitwarden%20CLI%20Auto-Lock.xml)

If anyone can contribute a similar file for MacOS or Linux please make a PR.
