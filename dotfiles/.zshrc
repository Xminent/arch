# Spawn random colorscripts
colorscript random

# Path to your oh-my-zsh installation.
export ZSH="/home/xminent/.oh-my-zsh"

# Path to local/bin directory
export PATH=$PATH:~/.local/bin

# Use p10k
ZSH_THEME="powerlevel10k/powerlevel10k"

# Plugins for zsh
plugins=(
    git
    zsh-autosuggestions
    zsh-syntax-highlighting
)

source $ZSH/oh-my-zsh.sh

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# Use colorls for ls if available
if [ -x "$(command -v colorls)" ]; then
    alias ls='colorls'
    alias la='colorls -al'
fi
