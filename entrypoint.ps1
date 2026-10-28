$ErrorActionPreference = 'Stop'

function Stop-WithMessage {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    [Console]::Error.WriteLine($Message)
    exit 1
}

$runnerHome = $env:RUNNER_HOME
if ([string]::IsNullOrWhiteSpace($runnerHome)) {
    $runnerHome = 'C:\actions-runner'
}

$runnerName = $env:RUNNER_NAME
if ([string]::IsNullOrWhiteSpace($runnerName)) {
    $runnerName = $env:COMPUTERNAME
}

$runnerWorkdir = $env:RUNNER_WORKDIR
if ([string]::IsNullOrWhiteSpace($runnerWorkdir)) {
    $runnerWorkdir = '_work'
}

$runnerLabels = $env:RUNNER_LABELS
if ([string]::IsNullOrWhiteSpace($runnerLabels)) {
    $runnerLabels = 'windows,windows-2025'
}

$configPath = Join-Path $runnerHome 'config.cmd'
$runPath = Join-Path $runnerHome 'run.cmd'
if (-not (Test-Path -LiteralPath $configPath) -or -not (Test-Path -LiteralPath $runPath)) {
    Stop-WithMessage "The GitHub Actions Runner was not found in '$runnerHome'."
}

$runnerFile = Join-Path $runnerHome '.runner'
$alreadyConfigured = Test-Path -LiteralPath $runnerFile
$forceReconfigure = $env:RUNNER_FORCE_RECONFIGURE -eq '1' -or $env:RUNNER_FORCE_RECONFIGURE -eq 'true'
$skipConfiguration = $alreadyConfigured -and -not $forceReconfigure

if ($skipConfiguration) {
    Write-Host "Runner already configured in '$runnerHome'; skipping configuration."
    if (-not [string]::IsNullOrWhiteSpace($env:RUNNER_TOKEN)) {
        Write-Host 'RUNNER_TOKEN is set but ignored because the runner is already configured. Set RUNNER_FORCE_RECONFIGURE=1 with a fresh token to reconfigure.'
    }
}
else {
    if ([string]::IsNullOrWhiteSpace($env:GITHUB_URL)) {
        Stop-WithMessage 'GITHUB_URL is required.'
    }

    if ([string]::IsNullOrWhiteSpace($env:RUNNER_TOKEN)) {
        Stop-WithMessage 'RUNNER_TOKEN is required.'
    }
}

Push-Location $runnerHome
$configured = $false
$runnerExitCode = 1

try {
    if (-not $skipConfiguration) {
        $configArguments = @(
            '--unattended',
            '--url', $env:GITHUB_URL,
            '--token', $env:RUNNER_TOKEN,
            '--name', $runnerName,
            '--labels', $runnerLabels,
            '--work', $runnerWorkdir,
            '--replace'
        )

        & $configPath @configArguments
        if ($LASTEXITCODE -ne 0) {
            throw "Runner configuration failed with exit code $LASTEXITCODE."
        }
        $configured = $true
    }

    & $runPath
    $runnerExitCode = $LASTEXITCODE
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    $runnerExitCode = 1
}
finally {
    if ($configured) {
        if (-not [string]::IsNullOrWhiteSpace($env:RUNNER_REMOVE_TOKEN)) {
            & $configPath remove --unattended --token $env:RUNNER_REMOVE_TOKEN
            if ($LASTEXITCODE -ne 0) {
                [Console]::Error.WriteLine('Runner removal failed. Remove the offline runner from GitHub manually if needed.')
                if ($runnerExitCode -eq 0) {
                    $runnerExitCode = 1
                }
            }
        }
        else {
            [Console]::Error.WriteLine('RUNNER_REMOVE_TOKEN was not provided; the runner may remain offline in GitHub after shutdown.')
        }
    }

    Pop-Location
}

exit $runnerExitCode
