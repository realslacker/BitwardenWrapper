# BitwardenWrapper
Wrapper module for Bitwarden CLI bw.exe. Includes parameter completion and type juggling for output.

## Features

* JSON output automatically converted to PSCustomObjects
* Passwords automatically converted to SecureString
* PSCredential objects added to output
* Login and Unlock automatically create $env:BW_SESSION
* Parameter completion for bw.exe parameters
* Installer function

## Installation
Install from the PSGallery

```powershell
Install-Module -Name BitwardenWrapper -Force
```
