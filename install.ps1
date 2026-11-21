# Installs m1, the command-line tool of m1cro.cloud, on Windows from the
# registry its releases are published to:
#
#   irm https://m1cro.cloud/install.ps1 | iex
#
# $env:M1_VERSION picks a version (the latest by default), $env:M1_INSTALL_DIR
# the folder (%LOCALAPPDATA%\m1 by default). m1 is under the PolyForm
# Noncommercial License 1.0.0: https://m1cro.cloud/LICENSE.md
# Runs on Windows PowerShell 5.1 and PowerShell 7.

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

& {
  $registry = if ($env:M1_REGISTRY) { $env:M1_REGISTRY } else { 'https://ghcr.io' }
  $repository = if ($env:M1_REPOSITORY) { $env:M1_REPOSITORY } else { 'lastfrake/m1-cli' }
  $dir = if ($env:M1_INSTALL_DIR) { $env:M1_INSTALL_DIR } else { Join-Path $env:LOCALAPPDATA 'm1' }
  $file = 'm1-windows-amd64.exe'

  # The registry lets anyone pull, with a token it gives without a login.
  $challenge = $null
  try {
    $null = Invoke-WebRequest -UseBasicParsing "$registry/v2/"
  } catch {
    $response = $_.Exception.Response
    if ($null -ne $response) {
      if ($response.Headers -is [System.Net.WebHeaderCollection]) {
        $challenge = $response.Headers['WWW-Authenticate']
      } else {
        $challenge = ($response.Headers.WwwAuthenticate | ForEach-Object { $_.ToString() }) -join ','
      }
    }
  }
  $headers = @{}
  if ($challenge -match '^\s*Bearer\s') {
    $realm = if ($challenge -match 'realm="([^"]*)"') { $Matches[1] } else { throw "m1: the registry names no realm for its token" }
    $service = if ($challenge -match 'service="([^"]*)"') { $Matches[1] } else { '' }
    $token = (Invoke-RestMethod -UseBasicParsing "${realm}?service=$service&scope=repository:${repository}:pull").token
    if (-not $token) { throw "m1: the registry gave no token to pull $repository" }
    $headers.Authorization = "Bearer $token"
  }

  $version = $env:M1_VERSION
  if (-not $version) {
    # The highest release, X.Y.Z alone.
    $tags = (Invoke-RestMethod -UseBasicParsing -Headers $headers "$registry/v2/$repository/tags/list").tags
    $version = $tags | Where-Object { $_ -match '^\d+\.\d+\.\d+$' } | Sort-Object { [version]$_ } | Select-Object -Last 1
    if (-not $version) { throw 'm1: no version of m1 is published' }
  }

  $manifestHeaders = $headers.Clone()
  $manifestHeaders.Accept = 'application/vnd.oci.image.manifest.v1+json'
  try {
    $manifest = Invoke-RestMethod -UseBasicParsing -Headers $manifestHeaders "$registry/v2/$repository/manifests/$version"
  } catch {
    throw "m1: no m1 $version in $registry/$repository"
  }
  # The layer whose title is the file of Windows.
  $layer = $manifest.layers | Where-Object { $_.annotations.'org.opencontainers.image.title' -eq $file } | Select-Object -First 1
  if (-not $layer) { throw "m1: m1 $version has no build $file" }

  $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("m1-" + [guid]::NewGuid())
  New-Item -ItemType Directory -Path $tmp | Out-Null
  try {
    $download = Join-Path $tmp 'm1.exe'
    Invoke-WebRequest -UseBasicParsing -Headers $headers -OutFile $download "$registry/v2/$repository/blobs/$($layer.digest)"
    $digest = 'sha256:' + (Get-FileHash -Algorithm SHA256 $download).Hash.ToLowerInvariant()
    if ($digest -ne $layer.digest) { throw "m1: $file of m1 $version does not match its digest $($layer.digest); nothing is installed" }
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Move-Item -Force $download (Join-Path $dir 'm1.exe')
  } finally {
    Remove-Item -Recurse -Force $tmp
  }

  Write-Host "m1 $version is installed as $(Join-Path $dir 'm1.exe')"
  $path = [Environment]::GetEnvironmentVariable('Path', 'User')
  if (-not (($path -split ';') -contains $dir)) {
    Write-Host "Add $dir to PATH to run it as m1, for example:"
    Write-Host "  [Environment]::SetEnvironmentVariable('Path', `"$dir;`$([Environment]::GetEnvironmentVariable('Path', 'User'))`", 'User')"
  }
  Write-Host 'm1 is under the PolyForm Noncommercial License 1.0.0: https://m1cro.cloud/LICENSE.md'
}
