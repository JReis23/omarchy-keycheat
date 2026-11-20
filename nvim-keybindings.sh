#!/bin/bash

# omarchy:summary=Print the Neovim keymaps Keycheat lists

# Neovim has no annotated listing command of the kind Omarchy ships for Hyprland
# and tmux, so this starts a headless instance with the user's own config, lets
# Lazy.nvim load the plugins (`User VeryLazy`), and runs the dump beside this
# script. The timeout keeps a plugin that waits for input from leaving the panel
# on "reading" forever.

set -o pipefail

command -v nvim >/dev/null 2>&1 || {
  echo "nvim-keybindings: Neovim not found" >&2
  exit 1
}

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

NVIM_KEYCHEAT_DUMP="$here/nvim-keybindings.lua" \
  timeout 15 nvim --headless -i NONE \
    --cmd 'set nomore' \
    +'doautocmd User VeryLazy' \
    +'lua dofile(vim.env.NVIM_KEYCHEAT_DUMP)' \
    +qa
