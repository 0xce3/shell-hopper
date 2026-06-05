# Install Details

The Windows installer:

1. Installs basic WSL packages.
2. Installs `shellhopper` to `~/.local/bin/shellhopper`.
3. Creates `~/.config/shellhopper/projects.tsv` if it does not exist.
4. Adds or updates an iconless Windows Terminal profile named `ShellHopper` with a hidden scrollbar.
5. Installs `tmux` inside WSL for project sessions.
6. Optionally clones and syncs a Neovim config when `-NvimConfigRepo` is provided.

ShellHopper tmux sessions create `ide`, `shell`, and `serial` windows. Existing sessions are reused. Use `shellhopper --sessions` to inspect sessions and `shellhopper --kill NAME` to clean up a stale session.

Docker is not installed by default. ShellHopper uses the existing `docker` CLI when it is available inside WSL. Discovered Docker containers create direct Windows Terminal profiles named `<name>` when selected; these profiles start stopped containers before attaching.

ShellHopper does not set Windows Terminal profile icons. Fonts are not installed by ShellHopper. Install a Nerd Font manually if your terminal UI needs icon glyphs.
