$ConfigFile = "$HOME\claudio.ini"

function Get-DefaultMountpoints {
    $mounts = [System.Collections.Generic.List[string]]::new()
    $mounts.Add("C:\Users\$env:USERNAME:/Users/$env:USERNAME")
    foreach ($drive in [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady }) {
        $letter = $drive.Name[0].ToString().ToLower()
        $hostPath = $drive.Name.TrimEnd('\')
        $mounts.Add("${hostPath}:/mnt/${letter}")
    }
    return $mounts -join ","
}

function Read-IniFile ([string]$Path) {
    $config = @{}
    foreach ($line in Get-Content $Path) {
        $line = $line.Trim()
        if ($line -match '^([^=;#\[]+)=(.*)$') {
            $config[$matches[1].Trim()] = $matches[2].Trim()
        }
    }
    return $config
}

function Write-DefaultConfig ([string]$Path) {
    $defaultMounts = Get-DefaultMountpoints
    @"
; claudio configuration
; host directory holding Claude's settings, credentials and .env
home=~/claudehome
; host:machine paths shared with the Podman machine. Only applied when the
; machine is created: to change them, remove the machine and run claudio again
mountpoints=$defaultMounts
; check for a newer Claude Code once the image is this many days old (0 = never)
update_check_days=7
"@ | Set-Content -Path $Path -Encoding UTF8
    Write-Host "Created default config at $Path"
}

if (-not (Test-Path $ConfigFile)) {
    Write-DefaultConfig -Path $ConfigFile
}

$config = Read-IniFile -Path $ConfigFile

$homeBase = $HOME -replace '\\', '/'
$ClaudeHome = if ($config['home']) { $config['home'] -replace '^~', $homeBase } else { "$homeBase/claudehome" }
$Mountpoints = "$($config['mountpoints'])"
$MachineName = if ($config['machine']) { $config['machine'] } else { "podman-machine-default" }
$MountpointsStampFile = "$HOME\.claudio-mountpoints-$MachineName"
$UpdateCheckDays = if ($config['update_check_days'] -match '^\d+$') { [int]$config['update_check_days'] } else { 7 }
$UpdateStampFile = "$HOME\.claudio-update-check"

# Check machine state via JSON output
$machineJson = podman machine list --format json 2>$null
$machines = $machineJson | ConvertFrom-Json

$machine = $machines | Where-Object { $_.Name -eq $MachineName }

if (-not $machine) {
    Write-Host "Podman machine '$MachineName' does not exist."
    $confirm = Read-Host "Create it now? (y/N)"
    if ($confirm -notmatch '^[Yy]$') {
        Write-Host "Aborted."
        exit 1
    }

    Write-Host "Creating Podman machine..."
    podman machine init `
        --cpus 2 `
        --disk-size 50 `
        --memory 4096 `
        --volume $Mountpoints `
        --username $env:USERNAME `
        --rootful=false `
        --now `
        $MachineName

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Machine creation failed."
        exit 1
    }
}
elseif ($machine.Running -ne $true) {
    Write-Host "Starting Podman machine '$MachineName'..."
    podman machine start $MachineName
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Machine failed to start."
        exit 1
    }
}
else {
    Write-Host "Podman machine '$MachineName' is already running."
}

# mountpoints only take effect when the machine is created: remember the ones
# in use (taking the current ones as baseline for machines created before
# this check existed) and warn when claudio.ini no longer matches
if (-not $machine -or -not (Test-Path $MountpointsStampFile)) {
    Set-Content -Path $MountpointsStampFile -Value $Mountpoints
}
elseif ("$(Get-Content $MountpointsStampFile -Raw)".Trim() -ne $Mountpoints) {
    Write-Warning ("mountpoints in $ConfigFile changed since machine '$MachineName' was created, " +
        "but they only apply when the machine is created. To apply them, run " +
        "'podman machine rm $MachineName' and then claudio again.")
}

# Check if claudio image exists
podman image exists claudio 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "The 'claudio' image is not present."
    $confirm = Read-Host "Build it now? (y/N)"
    if ($confirm -match '^[Yy]$') {
        podman build -t claudio $PSScriptRoot
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Image build failed."
            exit 1
        }
    }
    else {
        Write-Host ""
        Write-Host "Build it first:"
        Write-Host ""
        Write-Host "  cd $PSScriptRoot"
        Write-Host "  podman build -t claudio ."
        Write-Host ""
        exit 1
    }
}

# Once the image (or the last check) is older than update_check_days, compare
# the Claude Code version inside the image with the latest release
function Get-LastUpdateCheck {
    $last = [DateTimeOffset]::FromUnixTimeSeconds([long](podman image inspect claudio --format '{{.Created.Unix}}'))
    if (Test-Path $UpdateStampFile) {
        $stamp = (Get-Content $UpdateStampFile -TotalCount 1) -as [long]
        if ($stamp -and $stamp -gt $last.ToUnixTimeSeconds()) {
            $last = [DateTimeOffset]::FromUnixTimeSeconds($stamp)
        }
    }
    return $last
}

function Get-LatestClaudeVersion {
    # PowerShell 5.1 may not enable TLS 1.2 by default
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    try {
        $latest = Invoke-RestMethod -Uri "https://downloads.claude.ai/claude-code-releases/latest" -TimeoutSec 5
        if ("$latest".Trim() -match '^\d+\.\d+\.\d+$') { return $matches[0] }
    }
    catch {}
    return $null
}

if ($UpdateCheckDays -gt 0 -and (Get-LastUpdateCheck) -lt [DateTimeOffset]::UtcNow.AddDays(-$UpdateCheckDays)) {
    Write-Host "Checking for Claude Code updates..."
    $latest = Get-LatestClaudeVersion
    $installed = if ("$(podman run --rm claudio --version 2>$null)" -match '^\d+\.\d+\.\d+') { $matches[0] }

    if ($latest -and $installed -and [version]$installed -lt [version]$latest) {
        Write-Host "The 'claudio' image has Claude Code $installed, $latest is available."
        $confirm = Read-Host "Rebuild the image now? (y/N)"
        if ($confirm -match '^[Yy]$') {
            podman build -t claudio --build-arg "CLAUDE_CODE_VERSION=$latest" $PSScriptRoot
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "Image rebuild failed, continuing with Claude Code $installed."
            }
        }
    }

    # Remember the check (also when declined or offline) so it runs again
    # only after another update_check_days
    [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() | Set-Content -Path $UpdateStampFile
}

# Map the host directory to a unique path under /app, so each project gets
# its own Claude memory (e.g. C:\work\foo -> /app/c/work/foo)
$currentDir = $PWD.Path
if ($currentDir -match '^\\\\') {
    $containerDir = "/app/unc/" + ($currentDir.Substring(2) -replace '\\', '/')
}
else {
    $containerDir = "/app/" + $currentDir.Substring(0, 1).ToLower() + ($currentDir.Substring(2) -replace '\\', '/')
}
$containerDir = $containerDir.TrimEnd('/')

# podman fails on missing bind-mount sources and env files: create them
# on first run
New-Item -ItemType Directory -Force -Path "$ClaudeHome/claude" | Out-Null
if (-not (Test-Path "$ClaudeHome/claude.json")) {
    Set-Content -Path "$ClaudeHome/claude.json" -Value '{}' -Encoding Ascii
}
if (-not (Test-Path "$ClaudeHome/.env")) {
    @"
# Environment for the claudio container, one VAR=value per line.
# Leave the credentials unset to log in with /login inside Claude (the login
# is kept in claude/), or set one of:
#CLAUDE_CODE_OAUTH_TOKEN=
#ANTHROPIC_API_KEY=
"@ | Set-Content -Path "$ClaudeHome/.env" -Encoding Ascii
    Write-Host "Created $ClaudeHome/.env: edit it to set credentials or other variables."
}

$podmanArgs = @(
    "run", "-it", "--rm",
    "-v", "${currentDir}:${containerDir}",
    "-w", $containerDir,
    "-v", "${ClaudeHome}/claude/:/home/claude/.claude/",
    "-v", "${ClaudeHome}/claude.json:/home/claude/.claude.json",
    "--env-file", "${ClaudeHome}/.env",
    "claudio"
)

# Launch Claude container, forwarding any extra arguments to claude.
# claudio.bat sets CLAUDIO_ARGS to the raw command line: --% appends it verbatim,
# so podman parses it as typed instead of going through PowerShell's re-quoting.
if ($env:CLAUDIO_ARGS) {
    podman @podmanArgs --% %CLAUDIO_ARGS%
}
else {
    podman @podmanArgs @args
}

# powershell -File only reports 0/1 on its own: propagate claude's exit code
exit $LASTEXITCODE
