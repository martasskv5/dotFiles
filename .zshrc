# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH

export EDITOR=nano
export ZSH="$HOME/.oh-my-zsh"

#ZSH_THEME="agnosterzak"
ZSH_THEME=""

plugins=(
    git
    archlinux
    zsh-autosuggestions
    zsh-syntax-highlighting
)

source $ZSH/oh-my-zsh.sh

export ANTHROPIC_AUTH_TOKEN="freecc"
export ANTHROPIC_BASE_URL="http://localhost:8082"

# Check archlinux plugin commands here
# https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/archlinux

# Display Pokemon-colorscripts
# Project page: https://gitlab.com/phoneybadger/pokemon-colorscripts#on-other-distros-and-macos
#pokemon-colorscripts --no-title -s -r #without fastfetch
pokemon-colorscripts --no-title -s -r | fastfetch -c $HOME/.config/fastfetch/config-pokemon.jsonc --logo-type file-raw --logo-height 10 --logo-width 5 --logo -

# fastfetch. Will be disabled if above colorscript was chosen to install
#fastfetch -c $HOME/.config/fastfetch/config-compact.jsonc

# Set-up icons for files/directories in terminal using lsd
alias ls='lsd'
alias l='ls -l'
alias la='ls -a'
alias lla='ls -la'
alias lt='ls --tree'

alias cls='clear'
alias ssh='kitty +kitten ssh'
alias obsidian='/usr/bin/obsidian'
alias cat='bat'
alias img='chafa'

# Set-up FZF key bindings (CTRL R for fuzzy history finder)
source <(fzf --zsh)

HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt appendhistory

# Package installer wrapper
i() {
  local pkg_manager="pacman"
  local force=""
  local confirm="--noconfirm"
  local pkgs=()

  # Parse flags
  while [[ $1 == -* ]]; do
    case $1 in
      -y|--yay)
        pkg_manager="yay"
        force="yay"
        ;;
      -p|--pacman)
        pkg_manager="pacman"
        force="pacman"
        ;;
      -c|--confirm)
        confirm=""
        ;;
      -h|--help)
        echo "Usage: i [-p|-y] [-c] <package>..."
        echo "  -p, --pacman    Install directly with pacman"
        echo "  -y, --yay       Install directly with yay"
        echo "  -c, --confirm   Ask for confirmation before installing"
        echo "  Without flags:  Try pacman first, then yay if not found (auto-confirm)"
        return 0
        ;;
      *)
        echo "Unknown option: $1"
        return 1
        ;;
    esac
    shift
  done

  # No packages provided
  if [[ $# -eq 0 ]]; then
    echo "Usage: i [-p|-y] [-c] <package>..."
    echo "  -p, --pacman    Install directly with pacman"
    echo "  -y, --yay       Install directly with yay"
    echo "  -c, --confirm   Ask for confirmation before installing"
    echo "  Without flags:  Try pacman first, then yay if not found (auto-confirm)"
    return 1
  fi

  pkgs=("$@")

  # Direct install with specified package manager
  if [[ -n $force ]]; then
    if [[ $pkg_manager == "yay" ]]; then
      echo "Installing with yay: ${pkgs[*]}"
      yay -S "$confirm" "${pkgs[@]}"
    else
      echo "Installing with pacman: ${pkgs[*]}"
      sudo pacman -S "${pkgs[@]}"
    fi
    return $?
  fi

  # Try pacman first, then yay if not found
  for pkg in "${pkgs[@]}"; do
    if pacman -Ss "^${pkg}$" &>/dev/null; then
      echo "Found '$pkg' in repos, installing with pacman..."
      sudo pacman -S "$pkg"
    else
      echo "Package '$pkg' not found in pacman, trying yay (AUR)..."
      yay -S "$confirm" "$pkg"
    fi
  done
}

# Package updater wrapper
u() {
  local confirm="--noconfirm"
  local pkg_manager=""

  # Parse flags
  while [[ $1 == -* ]]; do
    case $1 in
      -y|--yay)
        pkg_manager="yay"
        ;;
      -p|--pacman)
        pkg_manager="pacman"
        ;;
      -c|--confirm)
        confirm=""
        ;;
      -h|--help)
        echo "Usage: u [-p|-y] [-c]"
        echo "  -p, --pacman    Update with pacman only"
        echo "  -y, --yay       Update with yay only"
        echo "  -c, --confirm   Ask for confirmation before updating"
        echo "  Without flags:  Update both pacman and AUR"
        return 0
        ;;
      *)
        echo "Unknown option: $1"
        return 1
        ;;
    esac
    shift
  done

  # Default: update both pacman and AUR
  if [[ -z $pkg_manager ]]; then
    echo "=== Updating pacman repos ==="
    sudo pacman -Syu "$confirm"
    echo ""
    echo "=== Updating AUR packages ==="
    yay -Syu "$confirm"
  elif [[ $pkg_manager == "yay" ]]; then
    echo "Updating with yay..."
    yay -Syu "$confirm"
  else
    echo "Updating with pacman..."
    sudo pacman -Syu
  fi
}

# Package remover wrapper
r() {
  local confirm="--noconfirm"
  local pkg_manager=""
  local recursive=false

  # Parse flags
  while [[ $1 == -* ]]; do
    case $1 in
      -y|--yay)
        pkg_manager="yay"
        ;;
      -p|--pacman)
        pkg_manager="pacman"
        ;;
      -c|--confirm)
        confirm=""
        ;;
      -r|--recursive)
        recursive=true
        ;;
      -h|--help)
        echo "Usage: r [-p|-y] [-c] [-r] <package>..."
        echo "  -p, --pacman    Remove with pacman"
        echo "  -y, --yay       Remove with yay"
        echo "  -c, --confirm   Ask for confirmation before removing"
        echo "  -r, --recursive Remove dependencies as well (pacman -Rcs)"
        echo "  Without flags:  Remove with pacman"
        return 0
        ;;
      *)
        echo "Unknown option: $1"
        return 1
        ;;
    esac
    shift
  done

  # No packages provided
  if [[ $# -eq 0 ]]; then
    echo "Usage: r [-p|-y] [-c] [-r] <package>..."
    echo "  -p, --pacman    Remove with pacman"
    echo "  -y, --yay       Remove with yay"
    echo "  -c, --confirm   Ask for confirmation before removing"
    echo "  -r, --recursive Remove dependencies as well (pacman -Rcs)"
    return 1
  fi

  # Default to pacman if no package manager specified
  if [[ -z $pkg_manager ]]; then
    pkg_manager="pacman"
  fi

  local pkgs=("$@")

  if [[ $pkg_manager == "yay" ]]; then
    echo "Removing with yay: ${pkgs[*]}"
    if $recursive; then
      yay -Rcs "$confirm" "${pkgs[@]}"
    else
      yay -R "$confirm" "${pkgs[@]}"
    fi
  else
    echo "Removing with pacman: ${pkgs[*]}"
    if $recursive; then
      sudo pacman -Rcs "${pkgs[@]}"
    else
      sudo pacman -R "${pkgs[@]}"
    fi
  fi
}

# Set ssh agent
#eval $(keychain --eval --agents ssh id_rsa)
#eval "$(ssh-agent -s)"
export SSH_AUTH_SOCK="/tmp/ssh-agent-$USER.sock"

# pnpm
export PNPM_HOME="/home/martinko/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end


# Load Angular CLI autocompletion.
source <(ng completion script)

# Load starship
eval "$(starship init zsh)"
export PATH="$HOME/.local/bin:$PATH"
