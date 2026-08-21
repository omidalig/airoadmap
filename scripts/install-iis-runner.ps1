#Requires -RunAsAdministrator
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$repositoryUrl = "https://github.com/omidalig/airoadmap"
$runnerName = "AiRoadmap-IIS"
$runnerLabel = "airoadmap-production"
$runnerDirectory = "C:\actions-runner"
$deploymentDirectory = "D:\Sites\Skyboard\AiRoadmap"
$serviceAccount = "NT AUTHORITY\NETWORK SERVICE"
$releaseApi = "https://api.github.com/repos/actions/runner/releases/latest"

function Write-Step([string]$Message) {
  Write-Host "`n==> $Message" -ForegroundColor Cyan
}

Write-Step "Checking prerequisites"
if ([Environment]::Is64BitOperatingSystem -ne $true) {
  throw "This installer requires 64-bit Windows."
}

if (Test-Path -LiteralPath (Join-Path $runnerDirectory ".runner")) {
  throw "A runner is already configured in $runnerDirectory. Remove it from GitHub before reinstalling."
}

$registrationTokenSecure = Read-Host "Paste the temporary GitHub runner registration token" -AsSecureString
$tokenPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($registrationTokenSecure)
try {
  $registrationToken = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($tokenPointer)
} finally {
  [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($tokenPointer)
}

if ([string]::IsNullOrWhiteSpace($registrationToken)) {
  throw "The registration token cannot be empty."
}

Write-Step "Resolving the latest GitHub Actions Runner release"
$headers = @{ "User-Agent" = "AiRoadmap-Runner-Installer" }
$release = Invoke-RestMethod -Uri $releaseApi -Headers $headers
$asset = $release.assets |
  Where-Object { $_.name -like "actions-runner-win-x64-*.zip" } |
  Select-Object -First 1

if (-not $asset) {
  throw "The Windows x64 runner package was not found in the latest GitHub release."
}

New-Item -ItemType Directory -Path $runnerDirectory -Force | Out-Null
$archivePath = Join-Path $runnerDirectory $asset.name

Write-Step "Downloading $($asset.name)"
Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $archivePath -Headers $headers

if ($asset.digest -and $asset.digest.StartsWith("sha256:")) {
  Write-Step "Verifying the runner package checksum"
  $expectedHash = $asset.digest.Substring(7)
  $actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($actualHash -ne $expectedHash.ToLowerInvariant()) {
    throw "The downloaded runner package checksum does not match GitHub's published checksum."
  }
}

Write-Step "Extracting the runner"
Expand-Archive -LiteralPath $archivePath -DestinationPath $runnerDirectory -Force
Remove-Item -LiteralPath $archivePath -Force

Write-Step "Preparing the IIS deployment directory"
New-Item -ItemType Directory -Path $deploymentDirectory -Force | Out-Null
& icacls.exe $deploymentDirectory /grant "*S-1-5-20:(OI)(CI)M" /T /Q
if ($LASTEXITCODE -ne 0) {
  throw "Failed to grant Modify permission to NETWORK SERVICE on $deploymentDirectory."
}

Write-Step "Registering the runner and installing its Windows Service"
$configPath = Join-Path $runnerDirectory "config.cmd"
Push-Location $runnerDirectory
try {
  & $configPath `
    --unattended `
    --url $repositoryUrl `
    --token $registrationToken `
    --name $runnerName `
    --labels $runnerLabel `
    --work "_work" `
    --runasservice `
    --windowslogonaccount $serviceAccount

  if ($LASTEXITCODE -ne 0) {
    throw "GitHub runner configuration failed with exit code $LASTEXITCODE."
  }
} finally {
  $registrationToken = $null
  Pop-Location
}

$serviceFile = Join-Path $runnerDirectory ".service"
if (-not (Test-Path -LiteralPath $serviceFile)) {
  throw "The runner service file was not created."
}

$serviceName = (Get-Content -Raw -LiteralPath $serviceFile).Trim()
$service = Get-Service -Name $serviceName
if ($service.Status -ne "Running") {
  Start-Service -Name $serviceName
  $service = Get-Service -Name $serviceName
}

Write-Host "`nRunner installation completed successfully." -ForegroundColor Green
Write-Host "Runner:      $runnerName"
Write-Host "Label:       $runnerLabel"
Write-Host "Service:     $serviceName"
Write-Host "Status:      $($service.Status)"
Write-Host "Deploy path: $deploymentDirectory"
Write-Host "`nThe queued GitHub Actions deployment can now continue automatically."
