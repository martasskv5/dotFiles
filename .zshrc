# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH

export EDITOR=nvim
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
#pokemon-colorscripts --no-title -s -r | fastfetch -c $HOME/.config/fastfetch/config-pokemon.jsonc --logo-type file-raw --logo-height 10 --logo-width 5 --logo -

# fastfetch. Will be disabled if above colorscript was chosen to install
fastfetch -c $HOME/.config/fastfetch/config-compact.jsonc

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
        echo "  Without flags:  Bulk install: pacman packages first, then AUR via yay"
        echo "                  (no prompts by default)"
        return 0
        ;;
      *)
        echo "Unknown option: $1"
        return 1
        ;;
    esac
    shift
  done

  if [[ $# -eq 0 ]]; then
    echo "Usage: i [-p|-y] [-c] <package>..."
    return 1
  fi

  pkgs=("$@")

  # Direct install with specified package manager (single bulk call)
  if [[ -n $force ]]; then
    if [[ $pkg_manager == "yay" ]]; then
      echo "Installing with yay: ${pkgs[*]}"
      yay -S $confirm "${pkgs[@]}"
    else
      echo "Installing with pacman: ${pkgs[*]}"
      sudo pacman -S $confirm "${pkgs[@]}"
    fi
    return $?
  fi

  # Auto mode: split into repo vs AUR, then bulk-install each group
  local repo_pkgs=()
  local aur_pkgs=()

  for pkg in "${pkgs[@]}"; do
    if pacman -Ss "^${pkg}$" &>/dev/null; then
      repo_pkgs+=("$pkg")
    else
      aur_pkgs+=("$pkg")
    fi
  done

  if [[ ${#repo_pkgs[@]} -gt 0 ]]; then
    echo "Installing from repos (pacman): ${repo_pkgs[*]}"
    sudo pacman -S $confirm "${repo_pkgs[@]}" || return $?
  fi

  if [[ ${#aur_pkgs[@]} -gt 0 ]]; then
    echo "Installing from AUR (yay): ${aur_pkgs[*]}"
    yay -S $confirm "${aur_pkgs[@]}" || return $?
  fi
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
  *":$PNPM_HOME/bin:"*) ;;
  *) export PATH="$PNPM_HOME/bin:$PATH" ;;
esac
# pnpm end


# Load Angular CLI autocompletion.
source <(ng completion script)

# Load starship
eval "$(starship init zsh)"
export PATH="$HOME/.local/bin:$PATH"

. "$HOME/.cargo/env"


# shellcheck shell=bash

# =============================================================================
#
# Utility functions for zoxide.
#

# pwd based on the value of _ZO_RESOLVE_SYMLINKS.
function __zoxide_pwd() {
    \builtin pwd -L
}

# cd + custom logic based on the value of _ZO_ECHO.
function __zoxide_cd() {
    # shellcheck disable=SC2164
    \builtin cd -- "$@"
}

# =============================================================================
#
# Hook configuration for zoxide.
#

# Hook to add new entries to the database.
function __zoxide_hook() {
    # shellcheck disable=SC2312
    \command zoxide add -- "$(__zoxide_pwd)"
}

# Initialize hook.
\builtin typeset -ga precmd_functions
\builtin typeset -ga chpwd_functions
# shellcheck disable=SC2034,SC2296
precmd_functions=("${(@)precmd_functions:#__zoxide_hook}")
# shellcheck disable=SC2034,SC2296
chpwd_functions=("${(@)chpwd_functions:#__zoxide_hook}")
chpwd_functions+=(__zoxide_hook)

# Report common issues.
function __zoxide_doctor() {
    [[ ${_ZO_DOCTOR:-1} -ne 0 ]] || return 0
    [[ $- == *i* ]] || return 0
    [[ ${chpwd_functions[(Ie)__zoxide_hook]:-} -eq 0 ]] || return 0

    _ZO_DOCTOR=0
    \builtin printf '%s\n' \
        'zoxide: detected a possible configuration issue.' \
        'Please ensure that zoxide is initialized right at the end of your shell configuration file (usually ~/.zshrc).' \
        '' \
        'If the issue persists, consider filing an issue at:' \
        'https://github.com/ajeetdsouza/zoxide/issues' \
        '' \
        'Disable this message by setting _ZO_DOCTOR=0.' \
        '' >&2
}

# =============================================================================
#
# When using zoxide with --no-cmd, alias these internal functions as desired.
#

# Jump to a directory using only keywords.
function __zoxide_z() {
    __zoxide_doctor
    if [[ "$#" -eq 0 ]]; then
        __zoxide_cd ~
    elif [[ "$#" -eq 1 ]] && [[ "$1" = '-' ]]; then
        __zoxide_cd "${OLDPWD}"
    elif [[ "$#" -eq 1 ]] && { [[ "$1" =~ ^[-+][0-9]+$ ]] || (\builtin cd -q -- "$1") &>/dev/null; }; then
        __zoxide_cd "$1"
    elif [[ "$#" -eq 2 ]] && [[ "$1" = "--" ]]; then
        __zoxide_cd "$2"
    else
        \builtin local result
        # shellcheck disable=SC2312
        result="$(\command zoxide query --exclude "$(__zoxide_pwd)" -- "$@")" && __zoxide_cd "${result}"
    fi
}

# Jump to a directory using interactive search.
function __zoxide_zi() {
    __zoxide_doctor
    \builtin local result
    result="$(\command zoxide query --interactive -- "$@")" && __zoxide_cd "${result}"
}

# =============================================================================
#
# Commands for zoxide. Disable these using --no-cmd.
#

function z() {
    __zoxide_z "$@"
}

function zi() {
    __zoxide_zi "$@"
}

# Completions.
if [[ -o zle ]]; then
    __zoxide_result=''

    function __zoxide_z_complete() {
        # Only show completions when the cursor is at the end of the line.
        # shellcheck disable=SC2154
        [[ "${#words[@]}" -eq "${CURRENT}" ]] || return 0

        if [[ "${#words[@]}" -eq 2 ]]; then
            # Show completions for local directories.
            _cd -/

        elif [[ "${words[-1]}" == '' ]]; then
            # Show completions for Space-Tab.
            # shellcheck disable=SC2086
            __zoxide_result="$(\command zoxide query --exclude "$(__zoxide_pwd || \builtin true)" --interactive -- ${words[2,-1]} 2>/dev/null)" || __zoxide_result=''

            # Set a result to ensure completion doesn't re-run
            compadd -Q -S "" -- ""

            # Bind '\e[0n' to helper function.
            \builtin bindkey '\e[0n' '__zoxide_z_complete_helper'
            # Sends query device status code, which results in a '\e[0n' being sent to console input.
            \builtin printf '\e[5n'

            # Report that the completion was successful, so that we don't fall back
            # to another completion function.
            return 0
        fi
    }

    function __zoxide_z_complete_helper() {
        if [[ -n "${__zoxide_result}" ]]; then
            # shellcheck disable=SC2034,SC2296
            BUFFER="z ${(q-)__zoxide_result}"
            __zoxide_result=''
            \builtin zle reset-prompt
            \builtin zle accept-line
        else
            \builtin zle reset-prompt
        fi
    }
    \builtin zle -N __zoxide_z_complete_helper

    [[ "${+functions[compdef]}" -ne 0 ]] && \compdef __zoxide_z_complete z
fi

# =============================================================================
