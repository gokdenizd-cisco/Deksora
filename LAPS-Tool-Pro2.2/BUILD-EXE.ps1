# Build the standalone Windows x64 executable.
# Requires network access for SDK installation and initial NuGet restore.
# Installs .NET 10 SDK via WinGet when necessary; falls back to .NET 8 SDK.
# The EXE itself never installs the .NET SDK or desktop runtime.
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot

function Find-DotNet {
    $candidates = @()
    foreach ($baseDir in @($env:ProgramFiles, $env:ProgramW6432, 'C:\Program Files')) {
        if (-not $baseDir) { continue }
        $candidate = Join-Path $baseDir 'dotnet\dotnet.exe'
        if (Test-Path -LiteralPath $candidate) { $candidates += $candidate }
    }
    if ($candidates.Count -gt 0) { return $candidates[0] }
    $command = Get-Command dotnet.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    return $null
}

function Read-Sdks([string]$dotnetPath) {
    if (-not $dotnetPath) { return @() }
    try { return @(& $dotnetPath --list-sdks 2>$null) } catch { return @() }
}

function Has-SdkMajor([string[]]$sdks, [int]$major) {
    return [bool](@($sdks | Where-Object { $_ -match ("^" + $major + "\.") }).Count -gt 0)
}

function Install-Sdk([int]$major) {
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        Write-Warning 'WinGet est absent. Impossible de telecharger automatiquement le SDK.'
        return $false
    }
    $id = "Microsoft.DotNet.SDK.$major"
    Write-Host "Installation du SDK $major via WinGet ($id)..." -ForegroundColor Cyan
    & winget.exe install --id $id --exact --source winget --silent --accept-package-agreements --accept-source-agreements
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        Write-Warning "WinGet a retourne le code $code pour $id."
        return $false
    }
    return $true
}

Write-Host '============================================' -ForegroundColor Cyan
Write-Host 'LAPS Tool Pro - Compilation automatique'
Write-Host '============================================' -ForegroundColor Cyan
Write-Host ''

$dotnet = Find-DotNet
$sdks = @(Read-Sdks $dotnet)

if (-not (Has-SdkMajor $sdks 10)) {
    Write-Host '.NET 10 SDK non detecte. Tentative installation de la derniere version stable...' -ForegroundColor Yellow
    $null = Install-Sdk 10
    $dotnet = Find-DotNet
    $sdks = @(Read-Sdks $dotnet)
}

if (-not (Has-SdkMajor $sdks 10) -and -not (Has-SdkMajor $sdks 8)) {
    Write-Host '.NET 10 indisponible. Installation de secours : .NET 8 SDK...' -ForegroundColor Yellow
    $null = Install-Sdk 8
    $dotnet = Find-DotNet
    $sdks = @(Read-Sdks $dotnet)
}

if (-not (Has-SdkMajor $sdks 10) -and -not (Has-SdkMajor $sdks 8)) {
    Write-Host 'ERREUR : aucun SDK .NET 10 ou 8 trouve.' -ForegroundColor Red
    Write-Host 'Installez un SDK depuis https://dotnet.microsoft.com/download puis relancez BUILD-EXE.cmd.'
    exit 1
}

$framework = if (Has-SdkMajor $sdks 10) { 'net10.0-windows' } else { 'net8.0-windows' }
Write-Host "SDK choisi : $framework" -ForegroundColor Green
Write-Host "Compilateur : $dotnet"
$output = Join-Path $PSScriptRoot 'EXE'
New-Item -ItemType Directory -Path $output -Force | Out-Null

# Remove stale assets created for a different TFM by older builder versions.
foreach ($folder in @('obj', 'bin')) {
    $path = Join-Path $PSScriptRoot $folder
    if (Test-Path -LiteralPath $path) {
        Write-Host "Nettoyage : $folder (anciens fichiers de compilation)..." -ForegroundColor DarkGray
        Remove-Item -LiteralPath $path -Force -Recurse -ErrorAction Stop
    }
}

$project = Join-Path $PSScriptRoot 'LapsToolPro.csproj'
$targetProperty = "-p:LapsTargetFramework=$framework"

# Restore is deliberately separated from publish and gets the same TFM property.
# This prevents NETSDK1005 (assets file has no target for the selected framework).
Write-Host "Restauration NuGet pour $framework / win-x64..." -ForegroundColor Cyan
& $dotnet restore $project `
    --runtime win-x64 `
    $targetProperty
if ($LASTEXITCODE -ne 0) {
    Write-Host 'Echec de la restauration .NET. Verifiez le reseau, NuGet et les politiques de votre entreprise.' -ForegroundColor Red
    exit 1
}

Write-Host "Compilation et publication autonome pour $framework..." -ForegroundColor Cyan
& $dotnet publish $project `
    --configuration Release `
    --runtime win-x64 `
    --framework $framework `
    --self-contained true `
    --no-restore `
    --output $output `
    $targetProperty `
    '-p:PublishSingleFile=true' `
    '-p:IncludeNativeLibrariesForSelfExtract=true' `
    '-p:PublishTrimmed=false' `
    '-p:EnableCompressionInSingleFile=true' `
    '-p:DebugSymbols=false' `
    '-p:DebugType=none'
if ($LASTEXITCODE -ne 0) {
    Write-Host 'La compilation a echoue. Consultez les erreurs affichees ci-dessus.' -ForegroundColor Red
    exit $LASTEXITCODE
}

$exe = Join-Path $output 'LAPS-Tool-Pro.exe'
if (-not (Test-Path -LiteralPath $exe)) {
    Write-Host 'Erreur : publication terminee sans EXE.' -ForegroundColor Red
    exit 1
}
Write-Host ''
Write-Host 'EXE PRET :' -ForegroundColor Green
Write-Host "  $exe" -ForegroundColor Green
Write-Host 'Il est autonome : aucun SDK ni runtime .NET requis sur les postes clients.'
Write-Host 'Windows LAPS et des droits AD restent necessaires pour interroger les secrets.'
exit 0
