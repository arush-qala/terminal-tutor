# terminal-tutor — Design Spec

**Date:** 2026-06-10
**Status:** Approved by Arush (chat, 2026-06-10)
**Audience note:** Arush is not a software engineer. All user-facing text (README, install steps, tutor output) must be written in plain English with no unexplained jargon.

## Purpose

A zsh plugin for macOS Terminal that teaches Arush what his commands mean as he types them, so he builds terminal literacy passively while following install instructions for AI tools and other web tutorials. Must be trivially installable and uninstallable on any Mac (he changes laptops).

## Decisions Made (with Arush)

| Decision | Choice |
|----------|--------|
| When explanations appear | First time a command/flag is used, plus an on-demand `explain` command |
| Explanation source | Offline only — curated local dictionary. No AI calls, no internet needed |
| Portability | Project in `2026/Projects/terminal-tutor` (OneDrive, syncs across machines), pushed to a free GitHub repo; one-line curl install on any Mac |
| Shell support | zsh only (macOS default). No bash support |
| Visual style of output | To be chosen by Arush via an interactive HTML playground (browser) during implementation — colors, prefix symbol, layout presented as clickable live previews |

## User Experience

1. **First-time teaching.** Just before a command runs, a compact colored note prints above its output, breaking the typed line down piece by piece (command, subcommand, each flag, notable arguments). Example for `git clone https://github.com/foo/bar`:

   ```
   [tutor] git — version control tool; tracks and downloads code projects
   [tutor]   clone — download a copy of a project from the internet
   [tutor]   https://… — the address of the project to download
   ```

   Once taught, that command/flag combination stays silent. Using a *new flag* with a known command triggers an explanation of just the new flag(s).

2. **On-demand.** `explain <anything>` prints the full breakdown anytime, even for already-learned commands.

3. **Control command** `tutor`:
   - `tutor on` / `tutor off` — pause/resume automatic teaching
   - `tutor reset` — forget all learned commands (teach from scratch)
   - `tutor status` — show on/off state, counts of commands learned/known
   - `tutor uninstall` — full clean removal (see Install/Uninstall)

4. **Pipelines and chains.** `cmd1 | cmd2`, `a && b`, `a; b` — each segment is explained per the same first-time rules. The pipe/`&&`/`;` symbols themselves are explained the first time they appear.

5. **Unknown commands.** One-time note: not in the dictionary, suggest `man <cmd>` or asking Claude. Then permanently silent for that command.

## Architecture

```
2026/Projects/terminal-tutor/     (development copy in OneDrive; pushed to GitHub)
├── terminal-tutor.zsh            # main plugin: preexec hook, explain, tutor commands
├── dictionary/                   # one plain-text file per command
│   ├── git
│   ├── ls
│   └── ...
├── install.sh                    # one-line curl installer target
├── uninstall.sh                  # called by `tutor uninstall`
├── tests/
│   └── run.sh                    # self-contained test script
├── README.md                     # plain-English docs + alternatives section
└── docs/superpowers/specs/       # this spec

~/.terminal-tutor/                (created at install on each machine)
├── app/                          # installed copy of the repo
├── seen                          # memory: what has been taught
└── state                         # on/off flag
```

### Components

1. **Hook (`preexec`)** — zsh's built-in "a command is about to run" event. Reads the typed line, decides what's new, prints explanations. Never modifies or blocks the command. Entire body wrapped in an error guard (`{ ... } 2>/dev/null` pattern + `|| true` semantics) so a plugin bug can never break a command or the shell.

2. **Parser** — pure-zsh function that splits a command line into segments (on `|`, `&&`, `;`), strips `sudo`/`env` prefixes, tokenizes each segment, expands bundled short flags (`-la` → `-l`, `-a`), recognizes `--long` flags, and classifies remaining tokens (subcommand vs. argument). Quoted strings are treated as single argument tokens and never parsed for flags.

3. **Dictionary** — one file per command. Format (tab-separated, `#` comments allowed):

   ```
   summary	<one-line plain-English description of the command>
   sub	clone	<explanation>          # subcommand (for git/brew/npm-style tools)
   flag	-r	<explanation>
   flag	--recursive	<explanation>
   arg	url	<explanation pattern for URL-looking arguments>   # optional
   ```

   Launch coverage ≈ 100 commands: everyday navigation/files (`cd ls pwd mkdir rm cp mv cat less more open touch find which echo head tail`), system (`chmod chown sudo kill ps top df du whoami history clear export source alias env`), text tools (`grep sed awk wc sort uniq xargs tee jq`), networking (`curl wget ssh ping`), dev/package tools (`brew npm npx node pip pip3 pipx uv python python3 conda git gh docker`), editors (`nano vim code`), archives (`tar zip unzip gzip`), AI-era tools (`claude gemini codex ollama`), and zsh builtins. Shell operators (`| && ; > >> <`) can't be filenames, so they live in one special file `dictionary/_operators` with the same line format.

4. **Memory (`~/.terminal-tutor/seen`)** — one line per taught item: `git`, `git clone`, `git -C`, `ls -l`, `op:|`, `unknown:foo`. Lookup via grep; append on teach. Per-machine by design.

5. **`explain` function** — runs the parser + dictionary lookup on its arguments and prints the full breakdown, ignoring the seen-file.

6. **`tutor` function** — subcommand dispatcher per UX section.

7. **Installer (`install.sh`)** — idempotent. Clones (or updates) the repo into `~/.terminal-tutor/app`, creates state files, appends a clearly-marked block to `~/.zshrc`:

   ```
   # >>> terminal-tutor >>>
   source "$HOME/.terminal-tutor/app/terminal-tutor.zsh"
   # <<< terminal-tutor <<<
   ```

   Install one-liner: `curl -fsSL https://raw.githubusercontent.com/<user>/terminal-tutor/main/install.sh | bash`. On the dev machine, `install.sh --local` symlinks to the project folder itself instead of cloning, so edits take effect immediately.

8. **Uninstaller (`uninstall.sh` / `tutor uninstall`)** — removes the marked block from `~/.zshrc` (only the marked block, nothing else) and deletes `~/.terminal-tutor/`. Prints confirmation and tells the user to open a new Terminal window.

## Visual Style (deferred to implementation, user-chosen)

Before finalizing output formatting, build an interactive single-file HTML playground (per Arush's request) showing terminal-mockup previews of style options: prefix symbol (`[tutor]`, `📚`, `›` etc.), color scheme (dim gray, cyan, yellow accents), layout (inline vs. indented breakdown), and verbosity. Arush clicks through options in the browser; the chosen combination becomes the default style constants in `terminal-tutor.zsh`.

## Error Handling

- Hook failures are swallowed silently — the user's command always runs.
- Missing/corrupt `seen` or `state` files are recreated empty on next load.
- Dictionary files with malformed lines: malformed lines are skipped, valid lines still work.
- `install.sh` refuses to double-add the `.zshrc` block (idempotent); `uninstall.sh` is safe to run twice.

## Testing

`tests/run.sh` — a zsh script, runnable locally with no dependencies, that:
- Feeds sample command lines through the parser and asserts expected token classification (flags split, sudo stripped, pipes segmented, quotes respected).
- Asserts dictionary lookups produce expected explanation lines for a sample of commands.
- Asserts seen-file logic: first use teaches, second use is silent, new flag teaches only the flag.
- Asserts installer block add/remove round-trips `.zshrc` unchanged.

## Out of Scope (YAGNI)

- No AI/LLM calls anywhere.
- No bash/fish support.
- No syncing of learned state across machines.
- No auto-updating of the dictionary from the internet.
- No man-page parsing; dictionary is hand-curated.

## README Requirements

Plain-English README covering: what it does (with a screenshot/example), the one-line install, uninstall, the `tutor`/`explain` commands, how to add a command to the dictionary, and an **Alternatives & further learning** section: tldr pages, explainshell.com, Warp terminal, asking Claude Code.
