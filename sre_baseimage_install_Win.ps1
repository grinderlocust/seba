<#
.SYNOPSIS
    SRE base install for Windows images
    The below procedure will run a simple Powershell procedure to
    * download and install the git package on windows.
    * download the 'DCD-Salt' repository
    * install and configure a 'masterless' salt-minion

.DESCRIPTION
    SRE base install for Windows images
    The below procedure will run a simple Powershell procedure to
    * download and install the git package on windows.
    * download the 'DCD-Salt' repository
    * install and configure a 'masterless' salt-minion

.EXAMPLE
    ./baseInstall.ps1 -AzurePersonalAccessToken <Token>
    The AzurePersonalAccessToken is required to clone the DCD-Salt repository
    Runs without any parameters. Uses all the default values/settings.

.NOTES
    All of the parameters are optional. The default should be the latest
    version. The architecture is dynamically determined by the script.
#>

#===============================================================================
# Commandlet Binding
#===============================================================================
[CmdletBinding()]
Param(
  [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
  [string]$AzurePersonalAccessToken = "",

  [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
  # Doesn't support versions prior to "YYYY.M.R-B"
  # [ValidatePattern('^201\d\.\d{1,2}\.\d{1,2}(\-\d{1})?|(rc\d)$')]
  [string]$git_version = "2.25.0",

  [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
  [string]$git_repourl = "https://github.com/git-for-windows/git/releases/download/v${git_version}.windows.1/",

  [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
  [boolean]$installWinUpdates = $false
)

# Powershell supports only TLS 1.0 by default. Add support up to TLS 1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]'Tls,Tls11,Tls12'

#===============================================================================
# Script Functions
#===============================================================================
function Get-IsAdministrator {
  $Identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
  $Principal = New-Object System.Security.Principal.WindowsPrincipal($Identity)
  $Principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-IsUacEnabled {
  (Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System).EnableLua -ne 0
}

#===============================================================================
# Check for Elevated Privileges
#===============================================================================
If (!(Get-IsAdministrator)) {
  If (Get-IsUacEnabled) {
    # We are not running "as Administrator" - so relaunch as administrator
    # Create a new process object that starts PowerShell
    $newProcess = new-object System.Diagnostics.ProcessStartInfo "PowerShell";

    # Specify the current script path and name as a parameter`
    $parameters = "/VERYSILENT /NORESTART /SP- /NOCANCEL"
    $newProcess.Arguments = $myInvocation.MyCommand.Definition, $parameters

    # Specify the current working directory
    $newProcess.WorkingDirectory = "$script_path"

    # Indicate that the process should be elevated
    $newProcess.Verb = "runas";

    # Start the new process
    [System.Diagnostics.Process]::Start($newProcess);

    # Exit from the current, unelevated, process
    Exit
  }
  Else {
    Throw "You must be administrator to run this script"
  }
}

#===============================================================================
# Verify Parameters
#===============================================================================
Write-Verbose "Git version: $git_version"
Write-Verbose "Git repourl: $git_repourl"

#===============================================================================
# Detect architecture
#===============================================================================
If ([IntPtr]::Size -eq 4) {
  $arch = "32-bit"
}
Else {
  $arch = "64-bit"
}

#===============================================================================
# Download git setup file
#===============================================================================
$gitExe = "Git-${git_version}-${arch}.exe"
Write-Output "Downloading Git installer $gitExe"
$webclient = New-Object System.Net.WebClient
$url = "$git_repourl/$gitExe"
$file = "C:\Windows\Temp\$gitExe"
$webclient.DownloadFile($url, $file)

#===============================================================================
# Set the parameters for the installer
#===============================================================================

$git_parameters = "/VERYSILENT /NORESTART /SP- /NOCANCEL"

#===============================================================================
# Install git silently
#===============================================================================
#Wait for process to exit before continuing.
Write-Output "Installing Git ..."
Start-Process C:\Windows\Temp\$gitExe -ArgumentList "$git_parameters" -Wait -NoNewWindow -PassThru | Out-Null

#===============================================================================
# Install Complete
#===============================================================================
Write-Output "Git successfully installed"

#===============================================================================
# Clone DCD-Salt repository to local minion
#===============================================================================
#Add git to %PATH% in case it's not there
if ( !($env:PATH -match "git") ) { $env:Path += ";C:\Program Files\Git\cmd"; }
if ( !($env:PATH -match "salt") ) { $env:Path += ";C:\salt"; }

# AzurePersonalAccessToken is stored in 'DragonProduction' keyVault; secretName: DCD-Salt-Git-AccessToken
$saltGitResult = salt-call.bat --local git.clone C:\salt\_DCD-Salt "https://salt-git-service-account:${AzurePersonalAccessToken}@nuanceninjas.visualstudio.com/DCD-Salt/_git/DCD-Salt"

Write-Output $saltGitResult

#===============================================================================
# Setup local minion and start the service
#===============================================================================
# Set config for local masterless minion
# Settings below are default settings to run salt-minion in a masterless way.
$minionContent = @"
multiprocessing: false
file_client: local
win_repo_cachefile: C:\salt\_DCD-Salt\salt\win\repo-ng\winrepo.p
win_repo: C:\salt\_DCD-Salt\salt\win\repo-ng\salt-winrepo-ng_git
file_roots:
  base:
    - C:\salt\_DCD-Salt\salt
    - C:\salt\_DCD-Salt\formulas
    - C:\salt\_DCD-Salt\salt\roles
pillar_roots:
  base:
    - C:\salt\_DCD-Salt\pillar
  dev:
    - C:\salt\_DCD-Salt\pillar\dev
  qa:
    - C:\salt\_DCD-Salt\pillar\qa
  lab:
    - C:\salt\_DCD-Salt\pillar\lab
  staging:
    - C:\salt\_DCD-Salt\pillar\staging
  production:
    - C:\salt\_DCD-Salt\pillar\production
grains:
  deployment_method: imageHost
"@

Set-Content "C:\salt\conf\minion" $minionContent

Set-Content "C:\salt\conf\minion_id" $env:COMPUTERNAME

#Configure service
$service = Get-Service "salt-minion" -ErrorAction SilentlyContinue

if ($service) {
  Set-Service $service.Name -StartupType "Automatic"
  Restart-Service $service.Name
}
else {
  "Minion service not found"
}

# Apply all Windows updates if required; default false
if ($installWinUpdates) {
  Write-Output "Get additional Windows Updates DSC Module"
  Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
  Install-Module -Name xWindowsUpdate -Force -AllowClobber
  Install-Module -Name PSWindowsUpdate -Force -AllowClobber

  Write-Output "Run Windows Updates"
  Get-WUInstall -WindowsUpdate -AcceptAll -UpdateType Software -IgnoreReboot
  Get-WUInstall -MicrosoftUpdate -AcceptAll -IgnoreUserInput -IgnoreReboot

  Install-WindowsUpdate -AcceptAll -IgnoreUserInput -AutoReboot
}

