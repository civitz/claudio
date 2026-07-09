param(
    [string]$MachineName = "podman-machine-default"
)

$ClaudeHome = "c:/Users/roberto/claudehome"

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
        --volume "C:\Users\roberto:/Users/roberto,C:\:/mnt/c,D:\progetti:/mnt/d/progetti" `
        --username roberto `
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
    Write-Host "  cd D:\progetti\claudio"
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
