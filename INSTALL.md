# Install Details

The Windows installer:

1. Installs basic WSL packages.
2. Installs `shellhopper` to `~/.local/bin/shellhopper`.
3. Creates `~/.config/shellhopper/projects.tsv` if it does not exist.
4. Adds or updates a Windows Terminal profile named `ShellHopper`.
5. Optionally clones and syncs a Neovim config when `-NvimConfigRepo` is provided.

