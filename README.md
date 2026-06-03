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

Open one environment directly:

```sh
shellhopper app
```

Use a custom registry:

```sh
shellhopper --config ~/.config/shellhopper/projects.tsv
```

By default, ShellHopper opens the selected environment through `tmux`. New sessions get these windows:

- `ide`: starts the configured command, usually `nvim`
- `shell`: interactive project shell
- `tasks`: project task shell that points to the Neovim task picker (`Space t r`) and lists `.vscode/tasks.json` labels when `jq` is available

The `tasks` window is intentionally a supporting shell, not a second task UI. Use it for long-running commands such as `native_sim`, display simulators, GPIO simulators, builds, or flash steps. Use Neovim's integrated terminal with `F12` for short-lived editor-local terminal work.

Disable tmux for a launch:

```sh
SHELLHOPPER_TMUX=0 shellhopper
```

List ShellHopper tmux sessions:

```sh
shellhopper --sessions
```

Kill a stale ShellHopper session and its `nvim`/container attach processes:

```sh
shellhopper --kill app
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

On Windows, the installer creates the ShellHopper Windows Terminal profile and sets a ShellHopper profile icon. Fonts are not installed by ShellHopper; install a Nerd Font manually if your terminal UI needs icon glyphs.

Docker is intentionally not installed by ShellHopper because many Windows + WSL setups use Docker Desktop or another Docker package source. Container entries work when `docker` is available inside WSL.

For devcontainer support, install the devcontainer CLI inside WSL:

```sh
npm install -g @devcontainers/cli
```
