param([Parameter(Mandatory = $true)][string]$SourceDir)
$ErrorActionPreference = 'Stop'
$work = Join-Path $env:RUNNER_TEMP ([IO.Path]::GetRandomFileName())
$originalLocalAppData = $env:LOCALAPPDATA
New-Item -ItemType Directory -Path $work | Out-Null
try {
    $assets = Join-Path $work 'assets'
    New-Item -ItemType Directory -Path $assets | Out-Null
    $core = Join-Path $env:SystemRoot 'System32\whoami.exe'
    $packager = Join-Path $SourceDir 'cmake\PackageHydrogenWindowsRelease.cmake'
    foreach ($version in @('alpha-0.0.2', 'alpha-0.0.3')) {
        & cmake "-DSOURCE_DIR=$SourceDir" "-DINPUT_BINARY=$core" "-DVERSION=$version" "-DRELEASES_DIR=$assets" -P $packager | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Could not package Windows fixture $version" }
    }
    $env:LOCALAPPDATA = $work
    $env:MOCK_ASSETS = $assets
    $env:MOCK_VERSION = 'alpha-0.0.3'
    $env:MOCK_MAINTENANCE = Join-Path $SourceDir 'scripts\hy-maintenance.ps1'
    $root = Join-Path $work 'Hydrogen'
    $env:MOCK_ENTRY = Join-Path $root 'bin\hy.cmd'
    $oldName = 'hydrogen-alpha-0.0.2-windows-x86_64'
    $newName = 'hydrogen-alpha-0.0.3-windows-x86_64'
    $oldArchive = Join-Path $assets "$oldName.zip"
    $newArchive = Join-Path $assets "$newName.zip"
    $env:MOCK_DIGEST = (Get-FileHash -Algorithm SHA256 $newArchive).Hash.ToLowerInvariant()
    $wrapper = Join-Path $work 'run-action.ps1'
    @'
function Invoke-RestMethod {
    param($Uri, $Headers, $TimeoutSec)
    $name = "hydrogen-$env:MOCK_VERSION-windows-x86_64.zip"
    $prefix = "https://github.com/Aurora-softwares/Hylang-Compiler/releases/download/$env:MOCK_VERSION/"
    return [pscustomobject]@{
        tag_name = $env:MOCK_VERSION; draft = $false; prerelease = $true
        assets = @(
            [pscustomobject]@{ name = $name; digest = "sha256:$env:MOCK_DIGEST"; browser_download_url = "$prefix$name" },
            [pscustomobject]@{ name = "$name.sha256"; browser_download_url = "$prefix$name.sha256" }
        )
    }
}
function curl.exe {
    $outputIndex = [Array]::IndexOf($args, '--output')
    if ($outputIndex -lt 0) { throw 'Missing curl output argument' }
    $url = $args[$args.Count - 1]
    $name = ($url -split '/')[-1]
    Copy-Item -LiteralPath (Join-Path $env:MOCK_ASSETS $name) -Destination $args[$outputIndex + 1]
    $global:LASTEXITCODE = 0
}
function Move-Item {
    param([string]$LiteralPath, [string]$Destination)
    if ($env:MOCK_FAIL_ACTIVATE -eq '1' -and $LiteralPath.EndsWith("-windows-x86_64")) {
        throw 'Injected activation failure'
    }
    Microsoft.PowerShell.Management\Move-Item -LiteralPath $LiteralPath -Destination $Destination
}
if ($env:MOCK_FORCE -eq '1') {
    & $env:MOCK_MAINTENANCE -EntryPath $env:MOCK_ENTRY $env:MOCK_ACTION --force
} else {
    & $env:MOCK_MAINTENANCE -EntryPath $env:MOCK_ENTRY $env:MOCK_ACTION
}
'@ | Set-Content -LiteralPath $wrapper -Encoding UTF8
    function Run-Action([string]$action, [bool]$force) {
        $env:MOCK_ACTION = $action
        $env:MOCK_FORCE = if ($force) { '1' } else { '0' }
        $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $wrapper 2>&1 | Out-String
        return @{ Code = $LASTEXITCODE; Output = $output }
    }
    function Install-Old {
        $stage = Join-Path $work ([IO.Path]::GetRandomFileName())
        Expand-Archive -LiteralPath $oldArchive -DestinationPath $stage
        Move-Item -LiteralPath (Join-Path $stage $oldName) -Destination $root
    }
    Install-Old
    $versionOutput = & cmd.exe /c (Join-Path $root 'bin\hy.cmd') --version | Out-String
    if ($versionOutput -notmatch 'Hydrogen alpha-0.0.2') { throw 'Windows launcher version failed' }
    $result = Run-Action 'update-check' $false
    if ($result.Code -ne 0 -or $result.Output -notmatch 'alpha-0.0.3 is available') {
        throw "Update check failed: $($result.Output)"
    }
    $result = Run-Action 'update' $true
    if ($result.Code -ne 0 -or $result.Output -notmatch 'Updated Hydrogen to alpha-0.0.3') {
        throw "Standalone update failed: $($result.Output)"
    }
    if ((Get-Content (Join-Path $root 'BUILD-INFO.txt') -First 1) -cne
        'Hydrogen release: alpha-0.0.3') { throw 'Updated release did not activate' }
    $result = Run-Action 'uninstall' $true
    if ($result.Code -ne 0 -or (Test-Path -LiteralPath $root)) {
        throw "Standalone uninstall failed: $($result.Output)"
    }
    Install-Old
    $env:MOCK_FAIL_ACTIVATE = '1'
    $result = Run-Action 'update' $true
    if ($result.Code -eq 0 -or
        (Get-Content (Join-Path $root 'BUILD-INFO.txt') -First 1) -cne
        'Hydrogen release: alpha-0.0.2') {
        throw "Activation failure did not restore the previous release: $($result.Output)"
    }
    Write-Output 'Windows standalone check, update, uninstall, and activation rollback passed'
} finally {
    $env:LOCALAPPDATA = $originalLocalAppData
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
