# Install Details

The Windows installer:

1. Installs basic WSL packages.
2. Installs `shellhopper` to `~/.local/bin/shellhopper`.
3. Creates `~/.config/shellhopper/projects.tsv` if it does not exist.
4. Adds or updates an iconless Windows Terminal profile named `ShellHopper` with a hidden scrollbar.
5. Optionally clones and syncs a Neovim config when `-NvimConfigRepo` is provided.

ShellHopper launches each selected environment as two Windows Terminal tabs: `<name>:nvim` for the configured editor command and `<name>:shell` for an interactive shell in the same workspace. It also creates direct Windows Terminal profiles named `<name> [nvim]` and `<name> [shell]` so either tab can be started later without opening the ShellHopper picker.

Docker is not installed by default. ShellHopper uses the existing `docker` CLI when it is available inside WSL. Discovered Docker containers create direct Windows Terminal profiles named `<name> [nvim]` and `<name> [shell]` when selected; these profiles start stopped containers before attaching.

ShellHopper does not set Windows Terminal profile icons. Fonts are not installed by ShellHopper. Install a Nerd Font manually if your terminal UI needs icon glyphs.
