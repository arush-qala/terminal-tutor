# terminal-tutor

## What this is

terminal-tutor is a zsh plugin that explains what your terminal commands mean the first time you run them. After that first explanation it goes quiet, so it teaches without getting in the way. You can also ask for a breakdown any time with `explain`.

You type `git clone https://github.com/foo/bar` and above the output you see:

```
[tutor] git — version control tool: tracks changes to code and moves projects to and from the internet
[tutor]   clone — download a full copy of a project from an online address
[tutor]   https://github.com/foo/bar — the internet address of the project
```

The explanations are in plain English. No jargon, no fluff.

---

## Install (any Mac)

Run this in your terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/REPO_OWNER/terminal-tutor/main/install.sh | bash
```

Then open a new Terminal window. That's it.

What it does: downloads the plugin to `~/.terminal-tutor/app` and adds a clearly-marked block to `~/.zshrc`. Nothing else is touched. If you ever want to see exactly what it added, open `~/.zshrc` and look for the lines between `# >>> terminal-tutor >>>` and `# <<< terminal-tutor <<<`.

You need git installed. git comes with the macOS developer tools; if you don't have it yet, the Mac will offer to install the tools automatically the first time something needs them.

---

## Uninstall

```bash
tutor uninstall
```

Or, if you no longer have a terminal session with the plugin loaded:

```bash
bash ~/.terminal-tutor/app/uninstall.sh
```

This removes the marked block from `~/.zshrc` and deletes the `~/.terminal-tutor` folder. Nothing else is touched.

---

## Daily use

| What you want | How |
|---|---|
| Automatic first-time teaching | Nothing, it happens on its own |
| Explain any command on demand | `explain ls -la` |
| Explain a command that has `\|` in it | `explain 'cat log \| grep error'` (put quotes around it) |
| Pause teaching | `tutor off` |
| Resume teaching | `tutor on` |
| Forget everything and start fresh | `tutor reset` |
| See current status | `tutor status` |

---

## Add a command to the dictionary

Each command is a plain-text file in the `dictionary/` folder. The filename is the command name. Here is what `dictionary/htop` might look like:

```
summary show a live view of CPU and memory use across all running processes
flag -u only show processes belonging to the given username
flag -p watch one specific process, by its process ID number
```

The format:
- `summary`: one line describing what the command does overall
- `flag`: one line per flag or option, in the format `flag <flag-name> <plain-English description>`
- `sub`: same format as `flag`, but for subcommands (like `git clone` or `brew install`)
- Fields are whitespace-separated; everything after the flag/subcommand name is the description
- Plain English only: write it as if explaining to someone who has never used a terminal

New files take effect the next time you open a Terminal window. You do not need to run `tutor reset`.

---

## Alternatives and further learning

**tldr pages**: community-written summaries for hundreds of commands. Install with `brew install tlrc`, then type `tldr tar` to see a focused cheat sheet with real examples.

**explainshell.com**: paste any command into the browser and it highlights each part with its manual-page description. Good when you have a long command you want to dissect.

**Warp terminal**: a replacement for the default Terminal app that has AI built in. You can describe what you want to do and it suggests the command.

**An AI agent**: ask Claude Code (or any other AI assistant) to explain anything. Something like "what does `find . -name '*.log' -mtime +7 -delete` do?" works well.

---

## For developers

**Developer install**, which symlinks the repo into place so edits apply immediately without reinstalling:

```bash
./install.sh --local
```

**Run the tests:**

```bash
zsh tests/run.sh
```

**Project layout:**

```
terminal-tutor.zsh        main plugin file (hook, explain, tutor commands)
lib/
  parser.zsh              splits a command line into segments and operators
  explain.zsh             looks up segments in the dictionary and formats output
dictionary/               one plain-text file per command (~95 commands)
  _operators              special file for shell operators (|, &&, >, etc.)
install.sh                installer (curl one-liner and --local dev mode)
uninstall.sh              removes the ~/.zshrc block and all files
tests/
  run.sh                  test runner (79 tests)
tools/
  style-playground.html   browser tool used to pick the output style
docs/                     design specs and planning documents
```
