#!/bin/sh
# add yap to ~/.zshrc; idempotent, touches nothing else
set -eu

dir=$(cd "$(dirname "$0")" && pwd)
line="source $dir/yap.zsh"
rc=${ZDOTDIR:-$HOME}/.zshrc

touch "$rc"
if grep -Fqx "$line" "$rc"; then
  echo "already in $rc"
else
  printf '\n# yap\n%s\n' "$line" >> "$rc"
  echo "added to $rc"
fi

echo "open a new shell, then: yap list the biggest files here"
