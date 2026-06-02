# ShellHopper

One Windows Terminal profile. Many development environments.

ShellHopper is a lightweight Windows + WSL launcher for hopping into Docker containers, devcontainers, local project shells, and Neovim-ready development sessions.

## Install

From PowerShell:

```powershell
irm https://raw.githubusercontent.com/0xce3/shell-hopper/main/install.ps1 | iex
```

Debuggable install:

```powershell
iwr https://raw.githubusercontent.com/0xce3/shell-hopper/main/install.ps1 -OutFile $env:TEMP\shellhopper-install.ps1
powershell -ExecutionPolicy Bypass -File $env:TEMP\shellhopper-install.ps1
```

Use a specific WSL distribution:

```powershell
powershell -ExecutionPolicy Bypass -File $env:TEMP\shellhopper-install.ps1 -WslDistribution Ubuntu-22.04
```

Optionally install a Neovim config as part of setup:

```powershell
powershell -ExecutionPolicy Bypass -File $env:TEMP\shellhopper-install.ps1 -NvimConfigRepo https://github.com/example/nvim-config.git
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

## Requirements

The installer prepares the WSL side with:

- `git`
- `curl`
- `fzf`
- `jq`
- `docker.io`
- `neovim`
- `ripgrep`
- `fd-find`

For devcontainer support, install the devcontainer CLI inside WSL:

```sh
npm install -g @devcontainers/cli
```

