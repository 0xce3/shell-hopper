# ShellHopper

One Windows Terminal profile. Many development environments.

ShellHopper is a lightweight Windows + WSL launcher for hopping into Docker containers, devcontainers, local project shells, and Neovim-ready development sessions.

## Install

From PowerShell:

```powershell
irm https://raw.githubusercontent.com/0xce3/shell-hopper/main/shellhopper.ps1 | iex
```

For custom installer parameters, download the installer first:

```powershell
$ProgressPreference = "SilentlyContinue"; $installer = Invoke-RestMethod "https://api.github.com/repos/0xce3/shell-hopper/contents/install.ps1?ref=main"; $path = Join-Path $env:TEMP "shellhopper-install.ps1"; [IO.File]::WriteAllBytes($path, [Convert]::FromBase64String(($installer.content -replace "\s", "")))
```

Skip font installation when your terminal font is already configured:

```powershell
powershell -ExecutionPolicy Bypass -File $path -SkipFontInstall
```

Use a specific WSL distribution:

```powershell
powershell -ExecutionPolicy Bypass -File $path -WslDistribution Ubuntu-22.04
```

Optionally install a Neovim config as part of setup:

```powershell
powershell -ExecutionPolicy Bypass -File $path -NvimConfigRepo https://github.com/example/nvim-config.git
```

## Usage

Open the `ShellHopper` Windows Terminal profile, or run inside WSL:

```sh
shellhopper
```

List known environments:

```sh
shellhopper --list
```

Use a custom registry:

```sh
shellhopper --config ~/.config/shellhopper/projects.tsv
```

By default, ShellHopper opens the selected environment through `tmux`. New sessions get these windows:

- `ide`: starts the configured command, usually `nvim`
- `shell`: interactive project shell
- `tasks`: spare shell for build, test, and flash commands
- `logs`: spare shell for serial output or logs

Disable tmux for a launch:

```sh
SHELLHOPPER_TMUX=0 shellhopper
```

## Project Registry

ShellHopper reads a tab-separated project registry from:

```text
~/.config/shellhopper/projects.tsv
```

Format:

```text
name	kind	target	workspace	command
app	wsl	-	/home/user/src/app	nvim
app-container	container	app-dev	/workspaces/app	nvim
app-devcontainer	devcontainer	/home/user/src/app	/workspaces/app	nvim
```

Kinds:

- `wsl`: opens a command in a local WSL directory
- `container`: starts and attaches to an existing Docker container
- `devcontainer`: starts a devcontainer from a local project path, then attaches

When Docker is available, ShellHopper also discovers existing containers automatically. It tries to infer a readable project name from `devcontainer.local_folder`, then Docker Compose labels, then the container name. It also detects workspace mounts such as `/workspaces/app` and `/workspace`.

## Requirements

The installer prepares the WSL side with:

- `git`
- `curl`
- `fzf`
- `jq`
- `neovim`
- `ripgrep`
- `fd-find`
- `tmux`

On Windows, the installer also installs `JetBrainsMono Nerd Font`, configures the ShellHopper Windows Terminal profile to use it, and sets a ShellHopper profile icon. The font enables icons in terminal UIs such as Neovim file explorers.

Skip font installation:

```powershell
powershell -ExecutionPolicy Bypass -File $path -SkipFontInstall
```

Docker is intentionally not installed by ShellHopper because many Windows + WSL setups use Docker Desktop or another Docker package source. Container entries work when `docker` is available inside WSL.

For devcontainer support, install the devcontainer CLI inside WSL:

```sh
npm install -g @devcontainers/cli
```
