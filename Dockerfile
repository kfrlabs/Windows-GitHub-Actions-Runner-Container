# escape=`
FROM mcr.microsoft.com/windows/servercore:ltsc2025

SHELL ["C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe", "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

ARG RUNNER_VERSION=2.338.2
ARG GIT_VERSION=2.50.1

ENV RUNNER_HOME=C:\actions-runner
ENV PATH="C:\Program Files\Git\cmd;C:\Program Files\Git\bin;C:\Windows\System32;C:\Windows;C:\Windows\System32\Wbem;C:\Windows\System32\WindowsPowerShell\v1.0;C:\Windows\System32\OpenSSH"

WORKDIR C:\actions-runner

RUN $runnerArchive = Join-Path $env:TEMP 'actions-runner.zip'; `
    Invoke-WebRequest -Uri "https://github.com/actions/runner/releases/download/v${env:RUNNER_VERSION}/actions-runner-win-x64-${env:RUNNER_VERSION}.zip" -OutFile $runnerArchive; `
    Expand-Archive -LiteralPath $runnerArchive -DestinationPath $env:RUNNER_HOME; `
    Remove-Item -Force $runnerArchive; `
    $gitInstaller = Join-Path $env:TEMP 'git-installer.exe'; `
    Invoke-WebRequest -Uri "https://github.com/git-for-windows/git/releases/download/v${env:GIT_VERSION}.windows.1/Git-${env:GIT_VERSION}-64-bit.exe" -OutFile $gitInstaller; `
    $install = Start-Process -FilePath $gitInstaller -ArgumentList '/VERYSILENT', '/NORESTART', '/NOCANCEL', '/SP-' -Wait -PassThru; `
    if ($install.ExitCode -ne 0) { throw "Git installation failed with exit code $($install.ExitCode)." }; `
    Remove-Item -Force $gitInstaller

COPY entrypoint.ps1 C:\entrypoint.ps1

ENTRYPOINT ["C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe", "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "C:\\entrypoint.ps1"]
