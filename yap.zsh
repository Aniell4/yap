# yap — say what you want, review the command, then run/edit/copy it.
#   yap kill whatever is at port 5283
#   Ctrl-X Ctrl-A on a half-typed line does the same thing with what you already typed.
#
# YAP_MODEL / YAP_THINKING pick the model and its thinking level.

typeset -g YAP_MODEL=${YAP_MODEL:-}
typeset -g YAP_THINKING=${YAP_THINKING:-low}
typeset -g YAP_BACKEND=${YAP_BACKEND:-omp}
typeset -g YAP_CFG=${YAP_CFG:-$HOME/.omp/agent/config.yml}

_yap_sys='You translate one natural-language request into exactly one shell command for zsh on Linux.
Reply with exactly two parts:
1. the command, alone on the first line: one line, non-interactive, correctly quoted, no $ prefix, no code fences
2. a blank line
3. one or two sentences: what it does, and any risk (destructive, needs sudo, network)
Only use commands that are actually installed on this system; the shell flags unknown ones.
`sadf -g` already emits SVG and takes no format argument (`sadf -g -- -u`, not `sadf -g svg -- -u`).
Time windows on history tools (`sar`, `sadf`: `-s`/`-e`) are HH:MM:SS only and print nothing at all when the window starts on the previous day; prefer the whole day, or make the window conditional.
If the command depends on something that may not be set up yet (a daemon, a collecting service, a database, a package), say so in the explanation.
If the request is ambiguous, pick the most standard interpretation. Never ask questions.'

# the model omp is configured to use, unless overridden (empty = let omp decide)
_yap_model() {
  local m=
  [[ -n $YAP_MODEL ]] && { print -r -- "$YAP_MODEL"; return }
  m=$(sed -n 's/^  default:[[:space:]]*//p' "$YAP_CFG" 2>/dev/null | head -1)
  print -r -- "$m"
}

# one generation -> stdout: command, blank line, explanation
_yap_gen() {
  local req=$1 prev=$2 note=$3
  local msg="Request: $req"
  if [[ -n $note ]]; then
    msg+=$'\n\n'"$note"
    [[ -n $prev ]] && msg+=$'\nThat produced: '"$prev"
    msg+=$'\nGive a different command that satisfies the request.'
  elif [[ -n $prev ]]; then
    msg+=$'\n\nThat produced: '"$prev"$'\nGive a different command that also satisfies the request.'
  fi
  local err=$(mktemp) m=$(_yap_model)
  local args=( "$YAP_BACKEND" -p --no-session --no-tools --no-title --thinking "$YAP_THINKING" --system-prompt "$_yap_sys" )
  [[ -n $m ]] && args+=( --model "$m" )
  "${args[@]}" "$msg" 2>"$err"
  local rc=$?
  if (( rc != 0 )); then
    print -ru2 -- "${YAP_BACKEND} failed (${rc}):"
    sed 's/^/  /' "$err" | tail -15 >&2
  fi
  rm -f "$err"
  return $rc
}

# raw reply -> YAP_CMD / YAP_DESC
_yap_parse() {
  local -a lines=( "${(@f)1}" ) D=() cand=()
  local l
  local -i i
  YAP_CMD= YAP_DESC=
  for (( i = 1; i <= ${#lines}; i++ )); do
    l=${lines[i]}
    [[ $l == *[[:graph:]]* ]] || continue
    [[ $l == '```'* ]] && continue
    cand+=( $i )
  done
  # drop leading prose like "Here you go:" while a real line remains
  while (( ${#cand} > 1 )) && [[ ${lines[cand[1]]} == *: || ${lines[cand[1]]} == '<'*'>' ]] && [[ ${lines[cand[1]]} != *'|'* ]]; do
    shift cand
  done
  (( ${#cand} )) || return 1
  local -i ci=${cand[1]}
  YAP_CMD=${lines[ci]}
  YAP_CMD=${YAP_CMD#\$ }
  YAP_CMD=${YAP_CMD#\`}
  YAP_CMD=${YAP_CMD%\`}
  YAP_CMD=${YAP_CMD%$'\r'}
  for (( i = ci + 1; i <= ${#lines}; i++ )); do
    l=${lines[i]}
    [[ $l == '```'* ]] && continue
    [[ $l == *[[:graph:]]* ]] && D+=( "$l" )
  done
  YAP_DESC=${(F)D}
}

_yap_frame() {
  local cmd=$1 desc=$2 prov=${3%%/*} mod=${3#*/} notice=$4 label=
  [[ -n $3 ]] && label=" ($prov, $mod)"
  [[ -z $3 ]] && label=""
  (( YAP_LINES )) && printf '\e[%dA\r\e[J' "$YAP_LINES"
  local w=$(( ${COLUMNS:-100} - 4 ))
  (( w < 30 )) && w=30
  local -a T K l
  T=( "Generating${label}..." "" ); K=( h "" )
  for l in "${(@f)$(print -rn -- "$cmd" | fold -w "$w")}"; do T+=( "$l" ); K+=( c ); done
  T+=( "" ); K+=( "" )
  for l in "${(@f)$(print -rn -- "$desc" | fold -s -w "$w")}"; do T+=( "  $l" ); K+=( d ); done
  if [[ -n $notice ]]; then
    T+=( "" ); K+=( "" )
    for l in "${(@f)$(print -rn -- "$notice" | fold -s -w "$w")}"; do T+=( "$l" ); K+=( n ); done
  fi
  T+=( "" "" ); K+=( "" k )
  local i
  for i in {1..${#T}}; do
    case $K[i] in
      c) printf '\e[38;5;210m%s\e[0m\n' "$T[i]" ;;
      n) printf '\e[33m%s\e[0m\n' "$T[i]" ;;
      k) printf '\e[1m[r]\e[0mun   \e[1m[a]\e[0mlternatives   \e[1m[c]\e[0mopy   \e[1m[e]\e[0mdit   \e[1m[q]\e[0muit\n' ;;
      *) print -r -- "$T[i]" ;;
    esac
  done
  printf '\e[7m \e[0m\n'
  # frame rows + the cursor-block row + the empty row the cursor sits on
  YAP_LINES=$(( ${#T} + 2 ))
}

# first plain command word in $1 that is not installed (empty when all exist)
_yap_missing() {
  emulate -L zsh
  setopt extendedglob
  local seg w
  local -A found
  local -a toks
  for seg in "${(@s:|:)1}"; do
    toks=( ${(z)seg} )
    while (( ${#toks} )); do
      w=${toks[1]}
      [[ $w == (''|[[:space:]]##|';'|'&&'|'||'|'('|')'|'{'|'}'|'\\') ]] && { shift toks; continue }
      [[ $w == *=* || $w == 'if' || $w == 'then' || $w == 'while' || $w == 'do' ]] && { shift toks; continue }
      [[ $w == '!' ]] && { shift toks; continue }
      break
    done
    (( ${#toks} )) || continue
    w=${toks[1]}
    [[ $w == [\$\(\"\']* ]] && continue
    [[ $w == [[:alnum:]_.+-]## ]] || continue
    (( ${+commands[$w]} || ${+builtins[$w]} || ${+functions[$w]} || ${+aliases[$w]} )) && continue
    (( found[$w]++ )) || print -r -- "$w"
  done
}

# missing binaries -> apt packages (unique); fails if any cannot be resolved
_yap_pkgs() {
  emulate -L zsh
  local b p out
  local -A seen
  for b in "$@"; do
    out=$(/usr/lib/command-not-found "$b" 2>&1)
    p=${${(M)${(f)out}:#sudo apt install *}[1]}
    [[ -n $p ]] || return 1
    p=${${p#sudo apt install }%% *}
    p=${p%,}
    [[ -n $p && -z $seen[$p] ]] || continue
    seen[$p]=1
    print -r -- "$p"
  done
}

# command line that installs the given binaries, or fail when there is none
_yap_installer() {
  emulate -L zsh
  local -a pkgs miss=( "$@" )
  if [[ -x /usr/lib/command-not-found ]] && (( ${+commands[apt-get]} )); then
    pkgs=( ${(f)"$(_yap_pkgs $miss)"} ) || return 1
    (( ${#pkgs} )) || return 1
    print -r -- "sudo apt-get install -y ${(j: :)pkgs}"
    return 0
  fi
  if (( ${+commands[brew]} )); then
    print -r -- "brew install ${(j: :)miss}"
    return 0
  fi
  return 1
}

_yap_copy() {
  if (( $+commands[wl-copy] )); then print -rn -- "$1" | wl-copy
  elif (( $+commands[xclip] )); then print -rn -- "$1" | xclip -selection clipboard
  elif (( $+commands[xsel] )); then print -rn -- "$1" | xsel -b
  else return 1; fi
}

yap() {
  emulate -L zsh
  setopt no_flow_control
  [[ $1 == -- ]] && shift
  local req="$*"
  if [[ -z ${req//[[:space:]]/} ]]; then
    printf '\e[38;5;210m❯\e[0m '
    read -r req || return 130
  fi
  [[ -n ${req//[[:space:]]/} ]] || return 0

  # raw keyboard for the whole generation+menu: keys pressed early are queued
  # instead of echoed, and nothing needs Enter
  local saved=$(stty -g 2>/dev/null)
  [[ -n $saved ]] && stty -echo -icanon min 1 time 0
  YAP_ACT=
  { _yap_loop "$req" } always { [[ -n $saved ]] && stty "$saved" }
  local rc=$?
  case $YAP_ACT in
    run)
      printf '\r\e[2K\e[1A\r\e[2K'
      if [[ -n $YAP_INSTALL ]]; then
        printf '\e[2m%s\e[0m\n' "$YAP_INSTALL"
        if ! eval -- "$YAP_INSTALL"; then
          printf '\e[31minstall failed — not running\e[0m\n'
          return 1
        fi
        rehash
      fi
      eval -- "$YAP_CMD"
      printf '\e[2m[exit %d]\e[0m\n' $? ;;
    copy)
      if _yap_copy "$YAP_CMD"; then
        printf '\e[2mcopied\e[0m\n'
      else
        printf '\e[2mno clipboard tool (xclip/wl-copy) — press e\e[0m\n'
      fi ;;
    edit)
      if [[ -n $WIDGET ]]; then
        YAP_RESULT=$YAP_CMD
        YAP_STATUS=edit
      else
        print -z -- "$YAP_CMD"
      fi ;;
  esac
  return $rc
}

# render, regenerate, and record the choice in YAP_ACT
_yap_loop() {
  local req=$1 model=$(_yap_model) prev= raw key note= miss= notice= install=
  local -a missl
  local -i tries=0
  YAP_INSTALL=
  YAP_LINES=0
  while true; do
    (( YAP_LINES )) && printf '\e[%dA\r\e[J' "$YAP_LINES"
    YAP_LINES=0
    if [[ -n $model ]]; then
      printf 'Generating (%s, %s)...\n' "${model%%/*}" "${model#*/}"
    else
      printf 'Generating...\n'
    fi
    YAP_LINES=1
    if ! raw=$(_yap_gen "$req" "$prev" "$note"); then
      print -r -- "${raw:-no answer}"
      return 1
    fi
    _yap_parse "$raw"
    if [[ -z $YAP_CMD ]]; then
      print -r -- "no command returned"; print -r -- "$raw"
      return 1
    fi
    miss=$(_yap_missing "$YAP_CMD")
    missl=( ${(f)miss} )
    notice=; install=; YAP_INSTALL=
    if (( ${#missl} )); then
      if install=$(_yap_installer $missl) && [[ -n $install ]]; then
        notice="${(j:, :)missl} not installed — [r] installs it and runs"
        YAP_INSTALL=$install
      elif (( tries < 2 )); then
        (( tries++ ))
        note="\`${(j:, :)missl}\` not installed here."
        prev=$YAP_CMD
        continue
      fi
    fi
    note=""
    _yap_frame "$YAP_CMD" "${YAP_DESC:-—}" "$model" "$notice"
    if ! read -k1 key; then
      YAP_LINES=0; return 130
    fi
    case $key in
      r|$'\r'|$'\n') YAP_LINES=0; YAP_ACT=run;  return 0 ;;
      c)             YAP_LINES=0; YAP_ACT=copy; return 0 ;;
      e)             YAP_LINES=0; YAP_ACT=edit; return 0 ;;
      a)             prev=$YAP_CMD ;;
      *)             YAP_LINES=0; YAP_ACT=quit; return 0 ;;
    esac
  done
}

yap-widget() {
  local buf=$BUFFER
  BUFFER=
  zle reset-prompt
  print
  yap -- "$buf"
  if [[ $YAP_STATUS == edit ]]; then
    BUFFER=$YAP_RESULT
    CURSOR=${#BUFFER}
  fi
  YAP_STATUS=
  zle reset-prompt
}
: ${YAP_KEY:='^X^A'}
zle -N yap-widget
bindkey "$YAP_KEY" yap-widget
