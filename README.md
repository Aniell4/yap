# yap

Say what you want. Review the command. Then run it.

`yap` turns a plain-English request into one shell command, shows it with a short explanation, and puts `[r]un [a]lternatives [c]opy [e]dit [q]uit` under it. Nothing executes until you say so.

```
❯ yap kill whatever is at port 5283
Generating (anthropic, claude-sonnet-5-5)...

lsof -tiTCP:5283 -sTCP:LISTEN | xargs -r kill

  Terminates processes listening on TCP port 5283; requires sufficient permission
  to signal them.

[r]un   [a]lternatives   [c]opy   [e]dit   [q]uit
```

## Keys

| key | |
|---|---|
| `r` / `Enter` | run it in your shell |
| `a` | a different command for the same request |
| `c` | copy it to the clipboard |
| `e` | put it back on the prompt, editable |
| `q` / `Esc` / `Ctrl-C` | drop it |

`Ctrl-X Ctrl-A` on a half-typed line feeds that line to `yap` instead of retyping it.

## Requirements

- zsh
- [omp](https://omp.sh) configured with at least one model (`yap` drives `omp -p`)
- optional: `xclip`/`wl-copy`/`xsel` for `[c]`, `command-not-found` or `brew` for `[r]`-installs

## Install

```sh
git clone https://github.com/Aniell4/yap ~/.config/yap
~/.config/yap/install.sh
```

`install.sh` adds one `source` line to your `~/.zshrc` and stops there; nothing else is touched. Open a new shell afterwards.

Or by hand:

```sh
git clone https://github.com/Aniell4/yap ~/.config/yap
echo 'source ~/.config/yap/yap.zsh' >> ~/.zshrc
```

Want the command to be called `ai`? `alias ai=yap` after the source line.

## Configuration

Set before the `source` line (or `export` from your shell):

| variable | default | |
|---|---|---|
| `YAP_MODEL` | your omp default model | model to generate with, `provider/model` |
| `YAP_THINKING` | `low` | `off` … `max` |
| `YAP_KEY` | `^X^A` | the widget binding |
| `YAP_BACKEND` | `omp` | binary to call |
| `YAP_CFG` | `~/.config/omp/agent/config.yml` | where the default model is read from |

## Missing tools

If the command needs a binary you don't have, `yap` says so instead of letting the shell fail, and `r` installs it first:

```
  sadf not installed — [r] installs it and runs
```

Packages are resolved through `command-not-found` (apt) or taken as formula names (brew). When nothing resolves, it regenerates with the missing name fed back, twice, then shows what it has.

## How it works

One `omp -p --no-session --no-tools` call with a system prompt that asks for a single `zsh` line, a blank line, and one or two sentences. The reply is parsed, the command is checked against your `PATH`, and the frame is drawn with plain escape codes — no dependencies beyond `zsh`, no daemon, no state.

The keyboard is in `-icanon`/`-echo` while the frame is up, so keys pressed during generation queue instead of leaking into the terminal; `stty` is restored before anything runs, so `sudo` still prompts normally.

## Caveats

- `r` runs under your shell with `eval` — same trust you'd give a typed line, not a sandbox.
- The model sees only your sentence, not your files: it can pick a plausible-but-wrong tool.
- Prompt-injection in filenames/paths is not reflected into the command unless you paste it in.

## License

MIT — see [LICENSE](LICENSE).
