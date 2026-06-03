# Install Details

The Windows installer:

1. Installs basic WSL packages.
2. Installs `shellhopper` to `~/.local/bin/shellhopper`.
3. Creates `~/.config/shellhopper/projects.tsv` if it does not exist.
4. Adds or updates a Windows Terminal profile named `ShellHopper`.
5. Installs `tmux` inside WSL for project sessions.
6. Optionally clones and syncs a Neovim config when `-NvimConfigRepo` is provided.

ShellHopper tmux sessions now create `ide`, `shell`, and `tasks` windows. The old placeholder `logs` window is not created. Use `shellhopper --sessions` to inspect existing sessions and `shellhopper --kill NAME` to clean up a stale session.

Docker is not installed by default. ShellHopper uses the existing `docker` CLI when it is available inside WSL.

The Windows Terminal profile icon can be changed during installation:

```powershell
powershell -ExecutionPolicy Bypass -File $env:TEMP\shellhopper-install.ps1 -ProfileIcon "⚡"
```

Fonts are not installed by ShellHopper. Install a Nerd Font manually if your terminal UI needs icon glyphs.
