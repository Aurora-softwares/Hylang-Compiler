param(
    [Parameter(Mandatory = $true)][string]$EntryPath,
    [Parameter(Mandatory = $true, Position = 0)][string]$Action,
    [Parameter(Position = 1)][string]$Option
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Fail([string]$message) { throw $message }
function Invoke-Checked([string]$program, [string[]]$arguments) {
    & $program @arguments
    if ($LASTEXITCODE -ne 0) { Fail "$program exited with code $LASTEXITCODE" }
}
function Confirm-Change([string]$message) {
    if ($script:force) { return }
    $answer = Read-Host "$message [y/N]"
    if ($answer -cnotin @('y', 'Y', 'yes')) { Fail 'Cancelled.' }
}
function Assert-Install([string]$path) {
    $required = @('bin/hy.cmd', 'libexec/hy-core.exe', 'libexec/hy-maintenance.ps1',
        'BUILD-INFO.txt', 'README.md', 'LICENSE', 'SHA256SUMS', 'INSTALL-MANIFEST')
    $manifestPath = Join-Path $path 'INSTALL-MANIFEST'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { Fail 'Installation manifest is missing.' }
    $manifest = @(Get-Content -LiteralPath $manifestPath)
    if ($manifest.Count -ne ($required.Count + 1) -or $manifest[0] -cne 'hydrogen-install-manifest-v1') {
        Fail 'Installation manifest has an unknown format or file count.'
    }
    foreach ($file in $required) {
        if (@($manifest | Where-Object { $_ -ceq $file }).Count -ne 1) { Fail "Manifest does not own $file" }
        $item = Join-Path $path $file
        if (-not (Test-Path -LiteralPath $item -PathType Leaf)) { Fail "Installation file missing: $file" }
        if (((Get-Item -LiteralPath $item).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            Fail "Installation file is a link: $file"
        }
    }
    $allowed = @($required + @('bin', 'libexec'))
    foreach ($item in (Get-ChildItem -LiteralPath $path -Force -Recurse)) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            Fail "Installation contains a link: $($item.FullName)"
        }
        $relative = $item.FullName.Substring($path.Length + 1).Replace('\', '/')
        if ($relative -cnotin $allowed) { Fail "Unmanaged installation content: $relative" }
    }
    foreach ($line in (Get-Content -LiteralPath (Join-Path $path 'SHA256SUMS'))) {
        if ($line -cnotmatch '^([0-9a-f]{64})  ([A-Za-z0-9./_-]+)$') { Fail 'Invalid checksum list.' }
        $expected = $Matches[1]; $file = $Matches[2]
        if ($file -cnotin $required -or $file -cin @('SHA256SUMS', 'INSTALL-MANIFEST')) {
            Fail "Unowned checksum entry: $file"
        }
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $path $file)).Hash.ToLowerInvariant()
        if ($actual -cne $expected) { Fail "Installed file checksum mismatch: $file" }
    }
}
function Get-Version([string]$path) {
    $line = @(Get-Content -LiteralPath (Join-Path $path 'BUILD-INFO.txt') |
        Where-Object { $_ -clike 'Hydrogen release: *' })
    if ($line.Count -ne 1) { Fail 'Installed version is missing.' }
    $version = $line[0].Substring('Hydrogen release: '.Length)
    if ($version -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { Fail 'Invalid installed version.' }
    return $version
}
function Get-Release([string]$current) {
    $channel = 'stable'
    if ($current -match '^(alpha|beta|rc)-') { $channel = $Matches[1] }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $headers = @{ Accept = 'application/vnd.github+json'; 'User-Agent' = 'Hydrogen-updater' }
    $releases = Invoke-RestMethod -Uri 'https://api.github.com/repos/Aurora-softwares/Hylang-Compiler/releases?per_page=100' -Headers $headers -TimeoutSec 30
    $eligible = @($releases | Where-Object {
        -not $_.draft -and $_.tag_name -match '^[A-Za-z0-9][A-Za-z0-9._-]*$' -and
        $(if ($channel -eq 'stable') {
            -not $_.prerelease -and $_.tag_name -notmatch '^(alpha|beta|rc)-'
        } else { $_.tag_name.StartsWith("$channel-") })
    })
    if ($eligible.Count -eq 0) { Fail "No $channel release is published." }
    $latest = $eligible | Sort-Object -Property {
        $numeric = $_.tag_name -replace '^(alpha|beta|rc)-', '' -replace '^v', ''
        try { [version]$numeric } catch { [version]'0.0' }
    } -Descending | Select-Object -First 1
    $version = [string]$latest.tag_name
    $archiveName = "hydrogen-$version-windows-x86_64.zip"
    $asset = @($latest.assets | Where-Object { $_.name -ceq $archiveName })
    $sidecar = @($latest.assets | Where-Object { $_.name -ceq "$archiveName.sha256" })
    if ($asset.Count -ne 1 -or $sidecar.Count -ne 1) { Fail "Release $version lacks installer-compatible Windows assets." }
    $digest = [string]$asset[0].digest
    if ($digest -cnotmatch '^sha256:[0-9a-f]{64}$') { Fail 'Release asset has no trusted SHA-256 digest.' }
    $prefix = "https://github.com/Aurora-softwares/Hylang-Compiler/releases/download/$version/"
    if ([string]$asset[0].browser_download_url -cne "$prefix$archiveName" -or
        [string]$sidecar[0].browser_download_url -cne "$prefix$archiveName.sha256") {
        Fail 'Unexpected release asset URL.'
    }
    return @{ Version = $version; Name = $archiveName; Digest = $digest;
        Url = [string]$asset[0].browser_download_url; Sidecar = [string]$sidecar[0].browser_download_url }
}
function Download-Release($release, [string]$directory) {
    $archive = Join-Path $directory $release.Name
    $sidecar = "$archive.sha256"
    Invoke-Checked 'curl.exe' @('--fail', '--silent', '--show-error', '--location',
        '--proto', '=https', '--proto-redir', '=https', '--max-time', '180', '--output', $archive, $release.Url)
    Invoke-Checked 'curl.exe' @('--fail', '--silent', '--show-error', '--location',
        '--proto', '=https', '--proto-redir', '=https', '--max-time', '30', '--output', $sidecar, $release.Sidecar)
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash.ToLowerInvariant()
    if ("sha256:$actual" -cne $release.Digest -or
        (Get-Content -LiteralPath $sidecar -Raw).TrimEnd("`r", "`n") -cne "$actual  $($release.Name)") {
        Fail 'Release archive digest or sidecar checksum mismatch.'
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $name = "hydrogen-$($release.Version)-windows-x86_64"
    $allowed = @("$name/", "$name/bin/", "$name/libexec/", "$name/bin/hy.cmd",
        "$name/libexec/hy-core.exe", "$name/libexec/hy-maintenance.ps1",
        "$name/BUILD-INFO.txt", "$name/README.md", "$name/LICENSE",
        "$name/SHA256SUMS", "$name/INSTALL-MANIFEST")
    $seen = @{}
    $zip = [IO.Compression.ZipFile]::OpenRead($archive)
    try {
        foreach ($entry in $zip.Entries) {
            if ($entry.FullName -cnotin $allowed -or $seen.ContainsKey($entry.FullName)) {
                Fail "Unexpected or repeated ZIP member: $($entry.FullName)"
            }
            $seen[$entry.FullName] = $true
            if ((($entry.ExternalAttributes -shr 16) -band 0xF000) -eq 0xA000) { Fail 'ZIP contains a link.' }
        }
    } finally { $zip.Dispose() }
    [IO.Compression.ZipFile]::ExtractToDirectory($archive, $directory)
    $stage = Join-Path $directory $name
    Assert-Install $stage
    if ((Get-Version $stage) -cne $release.Version) { Fail 'Release version mismatch.' }
    return $stage
}
function Get-Owner([string]$entry) {
    $lower = $entry.ToLowerInvariant()
    if ($lower.Contains('\scoop\apps\hydrogen\') -and (Get-Command scoop -ErrorAction SilentlyContinue)) {
        $installed = @(& scoop list 2>$null)
        if ($LASTEXITCODE -eq 0 -and ($installed -join [Environment]::NewLine) -match '(?im)^\s*hydrogen\s+') { return 'scoop' }
    }
    if ($lower.Contains('\chocolatey\lib\hydrogen\') -and (Get-Command choco -ErrorAction SilentlyContinue)) {
        $installed = @(& choco list --local-only --limit-output 2>$null)
        if ($LASTEXITCODE -eq 0 -and ($installed -join [Environment]::NewLine) -match '(?im)^hydrogen\|') { return 'choco' }
    }
    if ($lower.Contains('\microsoft\winget\packages\aurorasoftwares.hydrogen_') -and
        (Get-Command winget -ErrorAction SilentlyContinue)) {
        $installed = @(& winget list --id AuroraSoftwares.Hydrogen --exact 2>$null)
        if ($LASTEXITCODE -eq 0 -and ($installed -join [Environment]::NewLine).Contains('AuroraSoftwares.Hydrogen')) {
            return 'winget'
        }
    }
    return ''
}
function Managed-Action([string]$manager) {
    Write-Output "Install method: $manager (hydrogen)"
    switch ("$manager/$Action") {
        'scoop/update-check' { Invoke-Checked 'scoop' @('status', 'hydrogen'); return }
        'scoop/update' { Invoke-Checked 'scoop' @('update', 'hydrogen'); return }
        'scoop/uninstall' { Invoke-Checked 'scoop' @('uninstall', 'hydrogen'); return }
        'choco/update-check' { Invoke-Checked 'choco' @('outdated', '--limit-output'); return }
        'choco/update' { Invoke-Checked 'choco' @('upgrade', 'hydrogen', $(if ($force) {'-y'} else {'--confirm'})); return }
        'choco/uninstall' { Invoke-Checked 'choco' @('uninstall', 'hydrogen', $(if ($force) {'-y'} else {'--confirm'})); return }
        'winget/update-check' { Invoke-Checked 'winget' @('upgrade', '--id', 'AuroraSoftwares.Hydrogen', '--exact'); return }
        'winget/update' { Invoke-Checked 'winget' @('upgrade', '--id', 'AuroraSoftwares.Hydrogen', '--exact'); return }
        'winget/uninstall' { Invoke-Checked 'winget' @('uninstall', '--id', 'AuroraSoftwares.Hydrogen', '--exact'); return }
        default { Fail "Unsupported package manager: $manager" }
    }
}

try {
    if ($Action -eq 'remove') { $Action = 'uninstall' }
    if ($Action -cnotin @('update-check', 'update', 'uninstall')) { Fail 'Unknown lifecycle command.' }
    if ($Option -and $Option -cne '--force') { Fail 'Unknown lifecycle option.' }
    if ($Option -and $Action -eq 'update-check') { Fail 'update-check does not accept --force.' }
    $force = $Option -ceq '--force'
    $entry = [IO.Path]::GetFullPath($EntryPath)
    $root = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $entry) '..')).TrimEnd('\')
    Assert-Install $root
    $manager = Get-Owner $entry
    if ($manager) { Managed-Action $manager; exit 0 }
    $standalone = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Hydrogen')).TrimEnd('\')
    if ($root -ine $standalone) { Fail 'Unknown install ownership; refusing to change files.' }
    $current = Get-Version $root
    if ($Action -eq 'uninstall') {
        Confirm-Change "Remove Hydrogen $current from $root?"
        $bin = Join-Path $root 'bin'
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        $parts = @($userPath -split ';' | Where-Object { $_ -and $_ -ine $bin })
        $backup = Join-Path (Split-Path -Parent $root) ([IO.Path]::GetRandomFileName())
        Move-Item -LiteralPath $root -Destination $backup
        try { Remove-Item -LiteralPath $backup -Recurse -Force }
        catch { Move-Item -LiteralPath $backup -Destination $root; throw }
        [Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), 'User')
        Write-Output "Removed Hydrogen $current"
        exit 0
    }
    $release = Get-Release $current
    if ($Action -eq 'update-check') {
        if ($release.Version -ceq $current) { Write-Output "Hydrogen $current is up to date." }
        else { Write-Output "Hydrogen $($release.Version) is available (installed: $current)." }
        exit 0
    }
    if ($release.Version -ceq $current -and -not $force) {
        Write-Output "Hydrogen $current is up to date."
        exit 0
    }
    Confirm-Change "Replace Hydrogen $current with $($release.Version)?"
    $parent = Split-Path -Parent $root
    $work = Join-Path $parent ([IO.Path]::GetRandomFileName())
    $backup = Join-Path $parent ([IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Path $work | Out-Null
    try {
        $stage = Download-Release $release $work
        Assert-Install $root
        Move-Item -LiteralPath $root -Destination $backup
        try { Move-Item -LiteralPath $stage -Destination $root }
        catch { Move-Item -LiteralPath $backup -Destination $root; throw }
        try { Remove-Item -LiteralPath $backup -Recurse -Force }
        catch { Write-Warning "Old release remains at $backup; remove it after closing any open files." }
        Write-Output "Updated Hydrogen to $($release.Version)"
    } finally {
        if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
    }
} catch {
    Write-Error "Hydrogen lifecycle: $($_.Exception.Message)"
    exit 1
}
