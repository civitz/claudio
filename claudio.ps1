param(
    [string]$MachineName = "podman-machine-default"
)

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
; claudio configuration — edit and re-run to apply changes
home=~/claudehome
mountpoints=$defaultMounts
"@ | Set-Content -Path $Path -Encoding UTF8
    Write-Host "Created default config at $Path"
}

if (-not (Test-Path $ConfigFile)) {
    Write-DefaultConfig -Path $ConfigFile
}

$config = Read-IniFile -Path $ConfigFile

$homeBase = $HOME -replace '\\', '/'
$ClaudeHome = ($config['home'] -replace '^~', $homeBase)
$Mountpoints = $config['mountpoints']

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

# Check if claudio image exists
podman image exists claudio 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "The 'claudio' image is not present. Build it first:"
    Write-Host ""
    Write-Host "  cd $PSScriptRoot"
    Write-Host "  podman build -t claudio ."
    Write-Host ""
    exit 1
}

# Launch Claude container
$currentDir = $PWD.Path
podman run -it --rm `
    -v "${currentDir}:/app" `
    -v "${ClaudeHome}/.claude/:/home/claude/.claude/" `
    -v "${ClaudeHome}/claude.json:/home/claude/.claude.json" `
    --env-file "${ClaudeHome}/.env" `
    claudio
