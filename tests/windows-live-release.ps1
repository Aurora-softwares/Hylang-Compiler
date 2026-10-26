param([Parameter(Mandatory = $true)][string]$ExpectedVersion)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

if ($ExpectedVersion -cnotmatch '^alpha-[0-9]+\.[0-9]+\.[0-9]+$') {
    throw 'ExpectedVersion must be an alpha release tag such as alpha-0.0.3.'
}

$work = Join-Path $env:RUNNER_TEMP ([IO.Path]::GetRandomFileName())
$originalLocalAppData = $env:LOCALAPPDATA
$originalChannel = $env:HYDROGEN_CHANNEL
$originalUserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
New-Item -ItemType Directory -Path $work | Out-Null

function Invoke-Hy([string[]]$Arguments) {
    $output = & $script:launcher @Arguments 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "hy $($Arguments -join ' ') failed: $output"
    }
    return $output
}

try {
    $env:LOCALAPPDATA = $work
    $env:HYDROGEN_CHANNEL = 'alpha'
    $installer = Join-Path $work 'install.ps1'
    Invoke-WebRequest -UseBasicParsing -Uri 'https://hylang.co.uk/install.ps1' -OutFile $installer
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer
    if ($LASTEXITCODE -ne 0) { throw 'The public Windows installer failed.' }

    $script:launcher = Join-Path $work 'Hydrogen\bin\hy.cmd'
    if ((Invoke-Hy @('--version')).Trim() -cne "Hydrogen $ExpectedVersion") {
        throw 'The public installer selected an unexpected release.'
    }
    $check = Invoke-Hy @('update-check')
    if ($check -notmatch [regex]::Escape("Hydrogen $ExpectedVersion is up to date.")) {
        throw "Unexpected update-check result: $check"
    }
    $updated = Invoke-Hy @('update', '--force')
    if ($updated -notmatch [regex]::Escape("Updated Hydrogen to $ExpectedVersion")) {
        throw "Forced update did not reinstall the published release: $updated"
    }

    $projectDir = Join-Path $work 'project'
    New-Item -ItemType Directory -Path $projectDir | Out-Null
    $project = Join-Path $projectDir 'App.hyproj'
    @('format = 2', 'type = "exe"', 'sources = ["Program.hy"]') |
        Set-Content -LiteralPath $project -Encoding Ascii
    'public class Program { public static int Main(string[] args) { return 0; } }' |
        Set-Content -LiteralPath (Join-Path $projectDir 'Program.hy') -Encoding Ascii
    $search = Invoke-Hy @('package', 'search', 'math')
    if ($search -notmatch 'hydrogen\.math') { throw "Public registry search failed: $search" }
    Invoke-Hy @('package', 'add', $project, 'hydrogen.math@0.1.0') | Out-Null
    $packageDir = Join-Path $projectDir '.hylang\packages\hydrogen.math\0.1.0'
    if (-not (Test-Path -LiteralPath (Join-Path $packageDir 'hydrogen.math.hyproj'))) {
        throw 'The public registry package was not installed in the project.'
    }
    Remove-Item -LiteralPath $packageDir -Recurse -Force
    Invoke-Hy @('package', 'restore', $project) | Out-Null
    if (-not (Test-Path -LiteralPath (Join-Path $packageDir 'hydrogen.math.hyproj'))) {
        throw 'Package restore did not fetch the published package.'
    }
    Invoke-Hy @('package', 'remove', $project, 'hydrogen.math') | Out-Null
    if ((Get-Content -LiteralPath $project -Raw) -match 'hydrogen\.math\s*=') {
        throw 'Package removal left the dependency in the project.'
    }

    $removed = Invoke-Hy @('uninstall', '--force')
    if ($removed -notmatch [regex]::Escape("Removed Hydrogen $ExpectedVersion") -or
        (Test-Path -LiteralPath (Join-Path $work 'Hydrogen'))) {
        throw "Published release uninstall failed: $removed"
    }
    Write-Output "Public Windows installer, release, registry, update, and uninstall passed for $ExpectedVersion"
} finally {
    [Environment]::SetEnvironmentVariable('Path', $originalUserPath, 'User')
    $env:LOCALAPPDATA = $originalLocalAppData
    $env:HYDROGEN_CHANNEL = $originalChannel
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
