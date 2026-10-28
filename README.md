# Windows GitHub Actions Runner Container

A Docker image based on Windows Server Core LTSC 2025 that configures a self-hosted GitHub Actions runner at startup. It installs the official `actions/runner` and Git for Windows; no tokens are included in the image.

## Requirements

- A Windows Server 2025 host with Docker Engine configured for Windows containers.
- A host OS version compatible with the `ltsc2025` image. Windows containers are tied to the host Windows version; consult the [Microsoft compatibility matrix](https://learn.microsoft.com/virtualization/windowscontainers/deploy-containers/version-compatibility) before deployment.
- Docker Compose v2 if you use the Compose example.
- A temporary GitHub runner registration token for the target repository or organization.

## Build the image

On a Windows host configured for Windows containers:

```powershell
docker build -t windows-github-runner .
```

The runner and Git versions are pinned in the Dockerfile `ARG` values. To update them, pass `--build-arg RUNNER_VERSION=... --build-arg GIT_VERSION=...` to `docker build`, or set these values in `.env` for Compose, then rebuild the image. CI checks the build on `windows-2025`.

## Start a runner

Create a temporary registration token in GitHub under **Settings → Actions → Runners → New self-hosted runner**. The token is specific to the repository or organization and expires quickly; provide a valid token at startup:

```powershell
docker run --rm `
  -e GITHUB_URL="https://github.com/my-org/my-repository" `
  -e RUNNER_TOKEN="<registration-token>" `
  -e RUNNER_NAME="windows-runner-01" `
  -e RUNNER_LABELS="windows,windows-2025" `
  windows-github-runner
```

`GITHUB_URL` and `RUNNER_TOKEN` are required. The default name is the container's computer name, the default labels are `windows,windows-2025`, and the working directory is `_work`. GitHub automatically adds the runner's default labels (`self-hosted`, the operating system, and the architecture). Do not include `self-hosted` in `RUNNER_LABELS`.

| Variable | Description | Default value |
| --- | --- | --- |
| `GITHUB_URL` | GitHub repository or organization URL | Required |
| `RUNNER_TOKEN` | Temporary registration token | Required |
| `RUNNER_NAME` | Registered runner name | Computer name |
| `RUNNER_LABELS` | Comma-separated custom labels | `windows,windows-2025` |
| `RUNNER_WORKDIR` | Runner working directory | `_work` |
| `RUNNER_REMOVE_TOKEN` | Temporary runner removal token | None |
| `RUNNER_FORCE_RECONFIGURE` | Set to `1` or `true` with a fresh `RUNNER_TOKEN` to overwrite an existing configuration | None (skip `config.cmd` if already configured) |

## Restart behavior

If `C:\actions-runner\.runner` already exists, the entrypoint skips `config.cmd` and starts `run.cmd` directly. `GITHUB_URL` and `RUNNER_TOKEN` are only required for the first configuration. This makes `docker restart` and `unless-stopped` safe: registration tokens expire quickly and cannot be reused on every restart.

Configuration uses `--replace`, so a fresh container with the same `RUNNER_NAME` can take over a stale GitHub entry when given a valid token.

To reconfigure an existing container with a new token, URL, name, labels, or work directory, restart it once with `RUNNER_FORCE_RECONFIGURE=1` and a fresh `RUNNER_TOKEN`. Otherwise recreate it from scratch, which always configures cleanly:

```powershell
docker stop github-runner
docker rm github-runner
docker run -d --name github-runner --restart unless-stopped `
  -e GITHUB_URL="https://github.com/my-org/my-repository" `
  -e RUNNER_TOKEN="<nouveau-token>" `
  windows-github-runner
```

If the container keeps exiting with `Cannot configure the runner because it is already configured`, it was created by the old entrypoint; rebuild the image and recreate the container with a fresh token.

## Docker Compose and multiple runners

Copy `.env.example` to `.env`, fill in the values locally, then run:

```powershell
docker compose up -d --build
```

The `.env` file is ignored by Git and excluded from the build context. Never commit it. Scaled replicas share the same Compose settings and registration token; an unset name is derived from each container's computer name:

```powershell
docker compose up -d --build --scale github-runner=3
```

The runners share the same labels and Compose configuration. If your setup requires distinct tokens, names, or labels, deploy multiple separately configured services.

## Removal and shutdown

The registration token does not grant permission to remove a runner. To allow the entrypoint to call `config.cmd remove` after the runner stops, also provide `RUNNER_REMOVE_TOKEN`, generated with the GitHub removal endpoint for the corresponding repository or organization. This token is temporary as well: if it expires before the container stops, removal will fail. Without a valid removal token, the runner starts normally, but its GitHub entry may remain offline and require manual removal.

`docker stop` gives the runner time to shut down before forcing the container to stop. The entrypoint attempts removal only if configuration succeeded and a removal token is available. The runner is not configured in ephemeral mode, so it can receive multiple jobs during the container's lifetime.

## Use in a workflow

```yaml
jobs:
  build:
    runs-on:
      - self-hosted
      - windows
      - windows-2025
    steps:
      - uses: actions/checkout@v4
      - name: Build
        shell: powershell
        run: Write-Host "Running in a Windows container"
```

## Limitations

- The image provides Git and the runner, not the full toolset available on GitHub-hosted runners. Explicitly add the tools your workflows need.
- Access to the host's Docker engine from a Windows container is not configured. Windows Docker-in-Docker is not supported by default or guaranteed by this project.
- Windows containers require a compatible Windows host and cannot be built or run on a standard Linux host.
- Avoid passing secrets in images, build arguments, or files tracked by Git. Prefer a secret manager or inject variables at runtime. Environment variables remain accessible to processes in the container.

## CI

Pull requests run lightweight validation on Ubuntu (`PSScriptAnalyzer` on `entrypoint.ps1`, `docker compose config`, and a check that the pinned runner/Git release URLs exist). The Windows image is built on `windows-2025` only when merging to `main` (or manually via workflow dispatch). It does not publish an image to a registry. Building the Windows image requires a host and Docker engine compatible with Windows containers.
