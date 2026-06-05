# ShellHopper

One Windows Terminal launcher. Direct profiles for the environments you use.

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

By default, ShellHopper opens the selected environment through `tmux`. If the project session already exists, ShellHopper attaches to it. New sessions get these windows:

- `ide`: starts the configured command, usually `nvim`
- `shell`: interactive project shell
- `serial`: interactive project shell reserved for serial-console work

The `serial` window starts as a normal shell so it is useful immediately, and can later be wired to a project-specific serial-console command.

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

When Docker is available, ShellHopper also discovers existing containers automatically, including stopped containers. It tries to infer a readable project name from `devcontainer.local_folder`, then Docker Compose labels, then the container name. It also detects workspace mounts such as `/workspaces/app` and `/workspace`.

When you select a discovered Docker container or devcontainer from the ShellHopper menu, ShellHopper creates or updates a direct Windows Terminal profile named `<name>`. Opening that profile later skips the menu, starts the container if needed, and attaches to the existing tmux session when one is available.

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

On Windows, the installer creates the ShellHopper Windows Terminal profile without a custom icon and hides the profile scrollbar. Generated direct environment profiles use the same iconless, hidden-scrollbar settings. Fonts are not installed by ShellHopper; install a Nerd Font manually if your terminal UI needs icon glyphs.

Docker is intentionally not installed by ShellHopper because many Windows + WSL setups use Docker Desktop or another Docker package source. Container entries work when `docker` is available inside WSL.

For devcontainer support, install the devcontainer CLI inside WSL:

```sh
npm install -g @devcontainers/cli
```
