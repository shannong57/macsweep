# macsweep

Free up disk space on macOS from the command line. One Bash script, no dependencies, no sudo.

```
$ macsweep
  caches        4.2G
  logs        310.5M
  trash         1.1G
  xcode         8.7G
  devcaches     2.3G
  TOTAL        16.6G

$ macsweep clean caches xcode
$ macsweep big ~/Downloads --min 200
```

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/shannong57/macsweep/main/macsweep -o /usr/local/bin/macsweep
chmod +x /usr/local/bin/macsweep
```

Or clone the repo and put `macsweep` anywhere on your `PATH`.

## Commands

| Command | What it does |
|---|---|
| `macsweep` / `macsweep scan` | Show reclaimable space per category |
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
