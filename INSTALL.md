# Install Details

The Windows installer:

1. Installs basic WSL packages.
2. Installs `shellhopper` to `~/.local/bin/shellhopper`.
3. Creates `~/.config/shellhopper/projects.tsv` if it does not exist.
4. Adds or updates a Windows Terminal profile named `ShellHopper`.
5. Installs `tmux` inside WSL for project sessions.
6. Optionally clones and syncs a Neovim config when `-NvimConfigRepo` is provided.

Docker is not installed by default. ShellHopper uses the existing `docker` CLI when it is available inside WSL.

The recommended one-command installer uses `shellhopper.ps1`. The bootstrap stays small and downloads the current `install.ps1` through the GitHub API:

```powershell
irm https://raw.githubusercontent.com/0xce3/shell-hopper/main/shellhopper.ps1 | iex
```

The Windows Terminal profile icon can be changed during installation:

```powershell
powershell -ExecutionPolicy Bypass -File $path -ProfileIcon "⚡"
```

Fonts are not installed by ShellHopper. Install a Nerd Font manually if your terminal UI needs icon glyphs.
