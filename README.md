# macsweep

Free up disk space on macOS from the command line. One Bash script, no dependencies, no sudo.

Run `macsweep` and pick from the menu. There are no commands to remember.

```
$ macsweep

  macsweep — Mac cleanup            Disk: 182.0G free of 994.0G

  1  Clean up junk          (caches, logs, Trash, Xcode, dev caches)
  2  Find large files
  q  Quit

Choose: 1

  Clean up junk — scanning...
  1  Caches           7.3G
  2  Logs            91.3M
  3  Trash            1.1G
  4  Xcode            0.0K
  5  Dev caches      12.8G
  a  All     b  Back

Clean which? (numbers, a for all, b to go back): 1 2
```

Every list works the same way: type a number, confirm, and you return to that menu. `b` goes back and `q` quits from anywhere.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/shannong57/macsweep/main/macsweep -o /usr/local/bin/macsweep
chmod +x /usr/local/bin/macsweep
```

Or clone the repo and put `macsweep` anywhere on your `PATH`.

## Commands for scripts

Everything in the menu that can run unattended also has a direct command.

| Command | What it does |
|---|---|
| `macsweep` | Open the menu. Without a terminal, it runs `scan` instead |
| `macsweep scan` | Show reclaimable space per category |
| `macsweep clean [CATEGORY...]` | Delete junk, asking first. `--dry-run` previews, `--yes` skips the prompt |
| `macsweep big [PATH] [--min MB]` | List the 20 largest files (report only, never deletes) |

| Category | Cleared |
|---|---|
| `caches` | `~/Library/Caches` |
| `logs` | `~/Library/Logs` |
| `trash` | `~/.Trash` |
| `xcode` | `~/Library/Developer/Xcode/DerivedData`, `~/Library/Developer/CoreSimulator/Caches` |
| `devcaches` | `~/.npm/_cacache`, `~/.gradle/caches`, `~/.cache` |

## Safety

- Only clears the *contents* of the folders above. The folders themselves stay.
- Refuses any target that is a symlink or resolves outside your home folder. Symlinks inside a target are removed, but the files they point to are not.
- Asks before deleting. Without a terminal it refuses unless you pass `--yes`.
- Apps rebuild their caches, so the first launch afterwards may be slower.

macOS protects some folders, `~/.Trash` included. To clean them, give your terminal **Full Disk Access** in System Settings → Privacy & Security.

## Tests

```sh
./test.sh
```

The tests run against a temporary fake home folder and work on macOS or Linux.

## License

MIT. Not affiliated with MacPaw or CleanMyMac.
