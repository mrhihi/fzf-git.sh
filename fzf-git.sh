# The MIT License (MIT)
#
# Copyright (c) 2024 Junegunn Choi
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

# shellcheck disable=SC2039
[[ $0 == - ]] && return

__fzf_git_color() {
  if [[ -n $NO_COLOR ]]; then
    echo never
  elif [[ $# -gt 0 ]] && [[ -n $FZF_GIT_PREVIEW_COLOR ]]; then
    echo "$FZF_GIT_PREVIEW_COLOR"
  else
    echo "${FZF_GIT_COLOR:-always}"
  fi
}

__fzf_git_cat() {
  if [[ -n $FZF_GIT_CAT ]]; then
    echo "$FZF_GIT_CAT"
    return
  fi

  # Sometimes bat is installed as batcat
  _fzf_git_bat_options="--style='${BAT_STYLE:-full}' --color=$(__fzf_git_color .) --pager=never"
  if command -v batcat > /dev/null; then
    echo "batcat $_fzf_git_bat_options"
  elif command -v bat > /dev/null; then
    echo "bat $_fzf_git_bat_options"
  else
    echo cat
  fi
}

# FZF_GIT_DIFF: difftastic | delta | git (default: delta, then difftastic, if installed)
# Inside fzf, the tool picked with ALT-T is kept in the preview label
__fzf_git_diff_tool() {
  local want="${FZF_GIT_DIFF:-}"
  case "$FZF_PREVIEW_LABEL" in
    *difftastic*) want=difftastic ;;
    *delta*) want=delta ;;
    *git*) want=git ;;
  esac
  case "$want" in
    git) echo git ;;
    delta) command -v delta > /dev/null && echo delta || echo git ;;
    difftastic | difft) command -v difft > /dev/null && echo difftastic || echo git ;;
    *)
      if command -v delta > /dev/null; then echo delta
      elif command -v difft > /dev/null; then echo difftastic
      else echo git
      fi
      ;;
  esac
}

__fzf_git_diff_label() {
  echo " 🔀 $(__fzf_git_diff_tool) ╱ ALT-T (diff tool) ╱ ALT-L (layout) "
}

# Usage: __fzf_git_diff SUBCOMMAND [PREVIEW]
# Builds a git diff/show command for the selected diff tool
__fzf_git_diff() {
  local sub="$1" color
  shift
  color="$(__fzf_git_color "$@")"
  if [[ $(__fzf_git_diff_tool) == difftastic ]]; then
    # difftastic reads its settings from the environment
    if [[ $# -gt 0 ]]; then
      echo "env DFT_COLOR=$color DFT_WIDTH=\$FZF_PREVIEW_COLUMNS git -c core.quotePath=false -c diff.external=difft $sub --ext-diff"
    else
      echo "env DFT_COLOR=$color git -c core.quotePath=false -c diff.external=difft $sub --ext-diff"
    fi
  else
    echo "git -c core.quotePath=false $sub --no-ext-diff --color=$color"
  fi
}

# delta is a pager, so it is applied as a filter on plain git output
__fzf_git_pager() {
  local pager
  pager="${FZF_GIT_PAGER:-${GIT_PAGER:-$(git config --get core.pager 2> /dev/null)}}"
  if [[ -z $FZF_GIT_PAGER ]] && [[ $(__fzf_git_diff_tool) == delta ]]; then
    pager=delta
  fi
  echo "${pager:-cat}"
}

# Filter for commands that write straight to the terminal
__fzf_git_diff_filter() {
  [[ $(__fzf_git_diff_tool) == delta ]] && echo '| delta'
}

if [[ $1 == --diff ]]; then
  # --diff diff|show preview|tty ARGS...: run git diff/show with the current tool
  sub=$2 target=$3
  shift 3
  if [[ $target == preview ]]; then
    eval "$(__fzf_git_diff "$sub" .) \"\$@\"" | eval "$(__fzf_git_pager)"
  else
    eval "$(__fzf_git_diff "$sub") \"\$@\" $(__fzf_git_diff_filter)"
  fi
  exit 0
elif [[ $1 == --layout-next ]]; then
  # Print the fzf action that flips the preview between below and beside the list
  if [[ ${FZF_PREVIEW_COLUMNS:-0} -gt $((${FZF_COLUMNS:-0} * 8 / 10)) ]]; then
    echo 'change-preview-window(right,border-left,60%)'
  else
    echo 'change-preview-window(down,border-top,60%)'
  fi
  exit 0
elif [[ $1 == --diff-next ]]; then
  # Print the fzf actions that switch to the next available diff tool
  tools=(git)
  command -v difft > /dev/null && tools+=(difftastic)
  command -v delta > /dev/null && tools+=(delta)
  cur=$(__fzf_git_diff_tool)
  next=${tools[0]}
  for i in "${!tools[@]}"; do
    [[ ${tools[$i]} == "$cur" ]] && next=${tools[$(((i + 1) % ${#tools[@]}))]}
  done
  echo "change-preview-label( 🔀 $next ╱ ALT-T (diff tool) ╱ ALT-L (layout) )+refresh-preview"
  exit 0
fi

if [[ $1 == --list ]]; then
  shift
  if [[ $# -eq 1 ]]; then
    branches() {
      git branch "$@" --sort=-committerdate --sort=-HEAD --format=$'%(HEAD) %(color:yellow)%(refname:short) %(color:green)(%(committerdate:relative))\t%(color:blue)%(subject)%(color:reset)' --color=$(__fzf_git_color) | column -ts$'\t'
    }
    refs() {
      git for-each-ref "$@" --sort=-creatordate --sort=-HEAD --color=$(__fzf_git_color) --format=$'%(if:equals=refs/remotes)%(refname:rstrip=-2)%(then)%(color:magenta)remote-branch%(else)%(if:equals=refs/heads)%(refname:rstrip=-2)%(then)%(color:brightgreen)branch%(else)%(if:equals=refs/tags)%(refname:rstrip=-2)%(then)%(color:brightcyan)tag%(else)%(if:equals=refs/stash)%(refname:rstrip=-2)%(then)%(color:brightred)stash%(else)%(color:white)%(refname:rstrip=-2)%(end)%(end)%(end)%(end)\t%(color:yellow)%(refname:short) %(color:green)(%(creatordate:relative))\t%(color:blue)%(subject)%(color:reset)' | column -ts$'\t'
    }
    hashes() {
      git log --date=short --format="%C(green)%C(bold)%cd %C(auto)%h%d %s (%an)" --graph --color=$(__fzf_git_color) "$@" $LIST_OPTS
    }
    case "$1" in
      branches)
        echo 'CTRL-O (open in browser) ╱ ALT-A (show all branches)'
        echo 'ALT-H (list commit hashes)'
        branches
        ;;
      all-branches)
        echo 'CTRL-O (open in browser) ╱ ALT-ENTER (accept without remote)'
        echo 'ALT-H (list commit hashes)'
        branches -a
        ;;
      hashes)
        echo 'CTRL-O (open in browser) ╱ CTRL-D (diff) ╱ CTRL-S (toggle sort)'
        echo 'ALT-R (toggle raw mode) ╱ ALT-F (list files) ╱ ALT-A (show all hashes)'
        hashes
        ;;
      all-hashes)
        echo 'CTRL-O (open in browser) ╱ CTRL-D (diff)'
        echo 'CTRL-S (toggle sort) ╱ ALT-F (list files)'
        hashes --all
        ;;
      refs)
        echo 'CTRL-O (open in browser) ╱ ALT-E (examine in editor) ╱ ALT-A (show all refs)'
        refs --exclude='refs/remotes'
        ;;
      all-refs)
        echo 'CTRL-O (open in browser) ╱ ALT-E (examine in editor) ╱ ALT-ENTER (accept without remote)'
        refs
        ;;
      *) exit 1 ;;
    esac
  elif [[ $# -gt 1 ]]; then
    set -e

    branch=$(git rev-parse --abbrev-ref HEAD 2> /dev/null)
    if [[ $branch == HEAD ]]; then
      branch=$(git describe --exact-match --tags 2> /dev/null || git rev-parse --short HEAD)
    fi

    # Only supports GitHub for now
    case "$1" in
      commit)
        hash=$(grep -o "[a-f0-9]\{7,\}" <<< "$2" | head -n 1)
        path=/commit/$hash
        ;;
      branch|remote-branch)
        branch=$(sed 's/^[* ]*//' <<< "$2" | cut -d' ' -f1)
        remote=$(git config branch."${branch}".remote || echo 'origin')
        branch=${branch#$remote/}
        path=/tree/$branch
        ;;
      remote)
        remote=$2
        path=/tree/$branch
        ;;
      file) path=/blob/$branch/$(git rev-parse --show-prefix)$2 ;;
      tag)  path=/releases/tag/$2 ;;
      *)    exit 1 ;;
    esac

    remote=${remote:-$(git config branch."${branch}".remote || echo 'origin')}
    remote_url=$(git remote get-url "$remote" 2> /dev/null || echo "$remote")

    if [[ $remote_url =~ ^git@ ]]; then
      url=${remote_url%.git}
      url=${url#git@}
      url=https://${url/://}
    elif [[ $remote_url =~ ^http ]]; then
      url=${remote_url%.git}
    fi

    case "$OSTYPE" in
      darwin*)
        open "$url$path"
        ;;
      msys)
        # Git-Bash on Windows
        start "$url$path"
        ;;
      linux*)
        # Handle WSL on Windows
        if uname -a | grep -i -q Microsoft && command -v powershell.exe; then
          powershell.exe -NoProfile start "$url$path"
        else
          xdg-open "$url$path"
        fi
        ;;
      *)
        # fall back to xdg-open for BSDs, etc.
        xdg-open "$url$path"
        ;;
    esac
    exit 0
  fi
fi

if [[ $- =~ i ]] || [[ $1 = --run ]]; then # ----------------------------------

if [[ $__fzf_git_fzf ]]; then
  eval "$__fzf_git_fzf"
else
  # Redefine this function to change the options
  _fzf_git_fzf() {
    fzf --height 100% --tmux 100%,100% \
      --layout reverse --multi --min-height 20+ \
      --no-separator --header-border horizontal \
      --border-label-pos 2 \
      --color 'label:blue' \
      --preview-window 'right,50%' --preview-border line \
      --bind 'ctrl-/:change-preview-window(down,50%|hidden|)' "$@"
  }
fi

# On macOS, Option+key types a special character instead of sending Alt, so
# every alt-X binding also gets bound to that character (US layout).
# Option+E is a dead key and cannot be bound.
__fzf_git_run() {
  local args=() arg key char
  set -- --bind "alt-l:transform:bash \"$__fzf_git\" --layout-next" "$@"
  for arg in "$@"; do
    args+=("$arg")
    [[ $OSTYPE == darwin* ]] || continue
    [[ $arg =~ ^alt-([a-z]):(.*)$ ]] || continue
    key=${BASH_REMATCH[1]:-${match[1]}}
    case "$key" in
      a) char='å' ;;
      f) char='ƒ' ;;
      h) char='˙' ;;
      l) char='¬' ;;
      r) char='®' ;;
      t) char='†' ;;
      *) continue ;;
    esac
    args+=(--bind "$char:${arg#*:}")
  done
  _fzf_git_fzf "${args[@]}"
}

_fzf_git_check() {
  git rev-parse > /dev/null 2>&1 && return

  [[ -n $TMUX ]] && tmux display-message "Not in a git repository"
  return 1
}

__fzf_git=${BASH_SOURCE[0]:-${(%):-%x}}
__fzf_git=$(readlink -f "$__fzf_git" 2> /dev/null || /usr/bin/ruby --disable-gems -e 'puts File.expand_path(ARGV.first)' "$__fzf_git" 2> /dev/null)

_fzf_git_files() {
  local root query extract_file_name

  # Outside a git repository, fall back to the file search of fzf.
  # --force-tty-in is required when the caller has no tty on its standard
  # input, which is the case for the tmux bindings.
  if ! git rev-parse > /dev/null 2>&1; then
    root=$PWD
    if [[ -n $HOME ]] && [[ $root == "$HOME" || $root == "$HOME"/* ]]; then
      root="~${root#"$HOME"}"
    fi
    __fzf_git_run -m --force-tty-in \
      --border-label "📁 Files in $root " \
      --header 'ALT-E (open in editor)' \
      --bind "alt-e:execute:${EDITOR:-vim} {}" \
      --preview "$(__fzf_git_cat) {}" "$@"
    return
  fi

  root=$(git rev-parse --show-toplevel)
  [[ -n "$(git rev-parse --show-prefix)" ]] && query='!../ '

  read -r -d "" extract_file_name <<'EOF'
"$(cut -c4- <<< {} | sed 's/.* -> //;s/^"//;s/"$//;s/\\"/"/g')"
EOF

  (
    git -c core.quotePath=false -c color.status=$(__fzf_git_color) status --short --no-branch --untracked-files=all
    git -c core.quotePath=false ls-files "$root" | grep -vxFf <(
      git -c core.quotePath=false status --short --untracked-files=no |
        cut -c4- | sed -e 's/.* -> //' -e '/^"[^"\\]*"$/ { s/^"//;s/"$//; }'
      echo :
    ) | sed 's/^/   /'
  ) |
    __fzf_git_run -m --ansi --nth 2..,.. \
      --border-label '📁 Files ' \
      --header 'CTRL-O (open in browser) ╱ ALT-E (open in editor)' \
      --bind "ctrl-o:execute-silent:bash \"$__fzf_git\" --list file $extract_file_name" \
      --bind "alt-e:execute:${EDITOR:-vim} $extract_file_name" \
      --query "$query" \
      --preview-label "$(__fzf_git_diff_label)" \
      --bind "alt-t:transform:bash \"$__fzf_git\" --diff-next" \
      --preview-window down,border-top,60% \
      --bind 'ctrl-/:change-preview-window(down,80%|hidden|)' \
      --preview "bash \"$__fzf_git\" --diff diff preview -- $extract_file_name; $(__fzf_git_cat) $extract_file_name" "$@" |
    cut -c4- | sed 's/.* -> //'
}

_fzf_git_tree_files() {
  _fzf_git_check || return

  local treeish cdup prefix
  cdup="$(git rev-parse --show-cdup)"
  prefix="$(git rev-parse --show-prefix)"
  for treeish in "$@"; do
    git diff-tree --root --no-commit-id --name-only --line-prefix="$cdup" "$treeish" -r
  done | sort -u | sed "s|^$cdup$prefix||" |
    __fzf_git_run -m \
      --border-label "📂 Files in $* " \
      --header 'CTRL-O (open in browser) ╱ ALT-E (open in editor)' \
      --bind "ctrl-o:execute-silent:bash \"$__fzf_git\" --list file {}" \
      --bind "alt-e:execute:${EDITOR:-vim} {}" \
      --preview-label "$(__fzf_git_diff_label)" \
      --bind "alt-t:transform:bash \"$__fzf_git\" --diff-next" \
      --preview-window down,border-top,60% \
      --bind 'ctrl-/:change-preview-window(down,80%|hidden|)' \
      --preview "bash \"$__fzf_git\" --diff diff preview -- {}; $(__fzf_git_cat) {}"
}

_fzf_git_branches() {
  _fzf_git_check || return

  local shell
  [[ -n ${BASH_VERSION:-} ]] && shell=bash || shell=zsh

  bash "$__fzf_git" --list branches |
  __fzf_git_fzf=$(declare -f _fzf_git_fzf) __fzf_git_run --ansi \
    --border-label '🌲 Branches ' \
    --header-lines 2 \
    --tiebreak begin \
    --preview-window down,border-top,40% \
    --color hl:underline,hl+:underline \
    --no-hscroll \
    --bind 'ctrl-/:change-preview-window(down,70%|hidden|)' \
    --bind "ctrl-o:execute-silent:bash \"$__fzf_git\" --list branch {}" \
    --bind "alt-a:change-border-label(🌳 All branches)+reload:bash \"$__fzf_git\" --list all-branches" \
    --bind "alt-h:become:LIST_OPTS=\$(cut -c3- <<< {} | cut -d' ' -f1) $shell \"$__fzf_git\" --run hashes" \
    --bind "alt-enter:become:printf '%s\n' {+} | cut -c3- | sed 's@[^/]*/@@'" \
    --preview "git log --oneline --graph --date=short --color=$(__fzf_git_color .) --pretty='format:%C(auto)%cd %h%d %s' \$(cut -c3- <<< {} | cut -d' ' -f1) --" "$@" |
  sed 's/^\* //' | awk '{print $1}' # Slightly modified to work with hashes as well
}

_fzf_git_tags() {
  _fzf_git_check || return
  git tag --sort -version:refname |
  __fzf_git_run --preview-window down,border-top,60% \
    --bind 'ctrl-/:change-preview-window(down,80%|hidden|)' \
    --border-label '📛 Tags ' \
    --header 'CTRL-O (open in browser)' \
    --bind "ctrl-o:execute-silent:bash \"$__fzf_git\" --list tag {}" \
    --bind 'alt-r:toggle-raw' \
    --preview-label "$(__fzf_git_diff_label)" \
    --bind "alt-t:transform:bash \"$__fzf_git\" --diff-next" \
    --preview "bash \"$__fzf_git\" --diff show preview {}" "$@"
}

_fzf_git_hashes() {
  _fzf_git_check || return
  bash "$__fzf_git" --list hashes |
  __fzf_git_run --ansi --no-sort --bind 'ctrl-s:toggle-sort' --bind 'alt-r:toggle-raw' \
    --border-label '🍡 Hashes ' \
    --header-lines 2 \
    --bind "ctrl-o:execute-silent:bash \"$__fzf_git\" --list commit {}" \
    --bind "ctrl-d:execute:grep -o '[a-f0-9]\{7,\}' <<< {} | head -n 1 | xargs bash \"$__fzf_git\" --diff diff tty > /dev/tty" \
    --bind "alt-a:change-border-label(🍇 All hashes)+reload:bash \"$__fzf_git\" --list all-hashes" \
    --bind "alt-f:become:echo ::tree_files;
      awk 'match(\$0, /[a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9]*/) { print substr(\$0, RSTART, RLENGTH) }' {+f} |
        xargs bash \"$__fzf_git\" --run tree_files" \
    --color hl:underline,hl+:underline \
    --preview-label "$(__fzf_git_diff_label)" \
    --bind "alt-t:transform:bash \"$__fzf_git\" --diff-next" \
    --preview-window down,border-top,60% \
    --bind 'ctrl-/:change-preview-window(down,80%|hidden|)' \
    --preview "grep -o '[a-f0-9]\{7,\}' <<< {} | head -n 1 | xargs bash \"$__fzf_git\" --diff show preview" "$@" |
  awk '
    NR==1 && $0=="::tree_files" {
      mode="tree_files"
      next
    }

    mode=="tree_files" {
      print
      next
    }

    match($0, /[a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9]*/) {
      print substr($0, RSTART, RLENGTH)
    }
  '
}

_fzf_git_remotes() {
  _fzf_git_check || return
  git remote -v | awk '{print $1 "\t" $2}' | uniq |
  __fzf_git_run --tac \
    --border-label '📡 Remotes ' \
    --header 'CTRL-O (open in browser)' \
    --bind "ctrl-o:execute-silent:bash \"$__fzf_git\" --list remote {1}" \
    --preview-window right,70% \
    --preview "git log --oneline --graph --date=short --color=$(__fzf_git_color .) --pretty='format:%C(auto)%cd %h%d %s' '{1}/$(git rev-parse --abbrev-ref HEAD)' --" "$@" |
  cut -d$'\t' -f1
}

_fzf_git_stashes() {
  _fzf_git_check || return
  git stash list | __fzf_git_run \
    --border-label '🥡 Stashes ' \
    --header 'CTRL-X (drop stash)' \
    --bind 'ctrl-x:reload(git stash drop -q {1}; git stash list)' \
    --preview-window down,border-top,60% \
    --bind 'ctrl-/:change-preview-window(down,80%|hidden|)' \
    -d: --preview-label "$(__fzf_git_diff_label)" \
    --bind "alt-t:transform:bash \"$__fzf_git\" --diff-next" \
    --preview "bash \"$__fzf_git\" --diff show preview --first-parent {1}" "$@" |
  cut -d: -f1
}

_fzf_git_lreflogs() {
  _fzf_git_check || return
  git reflog --color=$(__fzf_git_color) --format="%C(blue)%gD %C(yellow)%h%C(auto)%d %gs" | __fzf_git_run --ansi \
    --border-label '📒 Reflogs ' \
    --bind 'alt-r:toggle-raw' \
    --preview-label "$(__fzf_git_diff_label)" \
    --bind "alt-t:transform:bash \"$__fzf_git\" --diff-next" \
    --preview-window down,border-top,60% \
    --bind 'ctrl-/:change-preview-window(down,80%|hidden|)' \
    --preview "bash \"$__fzf_git\" --diff show preview {1}" "$@" |
  awk '{print $1}'
}

_fzf_git_each_ref() {
  _fzf_git_check || return
  bash "$__fzf_git" --list refs | __fzf_git_run --ansi \
    --nth 2,2.. \
    --tiebreak begin \
    --border-label '☘️  Each ref ' \
    --header-lines 1 \
    --preview-window down,border-top,40% \
    --color hl:underline,hl+:underline \
    --no-hscroll \
    --bind 'ctrl-/:change-preview-window(down,70%|hidden|)' \
    --bind "ctrl-o:execute-silent:bash \"$__fzf_git\" --list {1} {2}" \
    --bind "alt-e:execute:${EDITOR:-vim} <(git show {2}) < /dev/tty > /dev/tty" \
    --bind "alt-a:change-border-label(🍀 Every ref)+reload:bash \"$__fzf_git\" --list all-refs" \
    --bind "alt-enter:become:printf '%s\n' {+2} | sed 's@[^/]*/@@'" \
    --preview "git log --oneline --graph --date=short --color=$(__fzf_git_color .) --pretty='format:%C(auto)%cd %h%d %s' {2} --" \
    --accept-nth 2 \
    "$@"
}

_fzf_git_worktrees() {
  _fzf_git_check || return
  git worktree list | __fzf_git_run \
    --border-label '🌴 Worktrees ' \
    --header 'CTRL-X (remove worktree)' \
    --bind 'ctrl-x:reload(git worktree remove {1} > /dev/null; git worktree list)' \
    --preview-window down,border-top,60% \
    --bind 'ctrl-/:change-preview-window(down,80%|hidden|)' \
    --preview "
      git -c color.status=$(__fzf_git_color .) -C {1} status --short --branch
      echo
      git log --oneline --graph --date=short --color=$(__fzf_git_color .) --pretty='format:%C(auto)%cd %h%d %s' {2} --
    " "$@" |
  awk '{print $1}'
}

_fzf_git_menu() {
  _fzf_git_check || return

  local choice result
  while true; do
    choice=$(
      {
        printf '%s\t%s\n' files 'Files            CTRL-G CTRL-F'
        printf '%s\t%s\n' branches 'Branches         CTRL-G CTRL-B'
        printf '%s\t%s\n' tags 'Tags             CTRL-G CTRL-T'
        printf '%s\t%s\n' remotes 'Remotes          CTRL-G CTRL-R'
        printf '%s\t%s\n' hashes 'Commit hashes    CTRL-G CTRL-H'
        printf '%s\t%s\n' stashes 'Stashes          CTRL-G CTRL-S'
        printf '%s\t%s\n' lreflogs 'Reflogs          CTRL-G CTRL-L'
        printf '%s\t%s\n' worktrees 'Worktrees        CTRL-G CTRL-W'
        printf '%s\t%s\n' each_ref 'Each ref         CTRL-G CTRL-E'
      } | __fzf_git_run --no-multi --delimiter $'\t' --with-nth 2.. \
        --height 40% --tmux 60%,50% --no-preview \
        --border-label '🧭 Git ' \
        --header 'ENTER to open ╱ ESC to close' | cut -f1
    )
    [[ -n $choice ]] || return

    # Leaving a screen without selecting anything goes back to the menu
    result=$("_fzf_git_$choice")
    if [[ -n $result ]]; then
      printf '%s\n' "$result"
      return
    fi
  done
}

fi # --------------------------------------------------------------------------

if [[ $1 = --run ]]; then
  shift
  type=$1
  shift
  eval "_fzf_git_$type" "$@"

elif [[ $- =~ i ]]; then # ------------------------------------------------------
if [[ -n "${BASH_VERSION:-}" ]]; then
  __fzf_git_init() {
    bind -m emacs-standard '"\er":  redraw-current-line'
    bind -m emacs-standard '"\C-z": vi-editing-mode'
    bind -m vi-command     '"\C-z": emacs-editing-mode'
    bind -m vi-insert      '"\C-z": emacs-editing-mode'

    local o c
    for o in "$@"; do
      c=${o:0:1}
      if [[ $c == '?' ]]; then
        o=${o:1}
        bind -m emacs-standard '"\C-g?":    " \C-u \C-a\C-k`_fzf_git_'$o'`\e\C-e\C-y\C-a\C-y\ey\C-h\C-e\er \C-h"'
        bind -m vi-command     '"\C-g?":    "\C-z\C-g?\C-z"'
        bind -m vi-insert      '"\C-g?":    "\C-z\C-g?\C-z"'
        continue
      fi
      bind -m emacs-standard '"\C-g\C-'$c'": " \C-u \C-a\C-k`_fzf_git_'$o'`\e\C-e\C-y\C-a\C-y\ey\C-h\C-e\er \C-h"'
      bind -m vi-command     '"\C-g\C-'$c'": "\C-z\C-g\C-'$c'\C-z"'
      bind -m vi-insert      '"\C-g\C-'$c'": "\C-z\C-g\C-'$c'\C-z"'
      bind -m emacs-standard '"\C-g'$c'":    " \C-u \C-a\C-k`_fzf_git_'$o'`\e\C-e\C-y\C-a\C-y\ey\C-h\C-e\er \C-h"'
      bind -m vi-command     '"\C-g'$c'":    "\C-z\C-g'$c'\C-z"'
      bind -m vi-insert      '"\C-g'$c'":    "\C-z\C-g'$c'\C-z"'
    done
  }
elif [[ -n "${ZSH_VERSION:-}" ]]; then
  __fzf_git_join() {
    local item
    while read -r item; do
      echo -n -E "${(q)${(Q)item}} "
    done
  }

  __fzf_git_init() {
    setopt localoptions no_glob
    local m o key
    for o in "$@"; do
      key=${o[1]}
      [[ $key == "?" ]] && o=${o#\?}
      eval "fzf-git-$o-widget() { local result=\$(_fzf_git_$o | __fzf_git_join); zle reset-prompt; LBUFFER+=\$result }"
      eval "zle -N fzf-git-$o-widget"
      for m in emacs vicmd viins; do
        [[ $key == "?" ]] || eval "bindkey -M $m '^g^$key' fzf-git-$o-widget"
        eval "bindkey -M $m '^g$key' fzf-git-$o-widget"
      done
    done
  }
fi
__fzf_git_init files branches tags remotes hashes stashes lreflogs each_ref worktrees '?menu'

fi # --------------------------------------------------------------------------
