# macsweep

Clean up and look after your Mac from a simple terminal menu: clear junk, find large files, uninstall apps, check for updates, manage startup items and run maintenance tasks. One Bash script, no dependencies.

Run `macsweep` and pick from the menu. There are no commands to remember.

```
$ macsweep

  macsweep — Mac cleanup            Disk: 182.0G free of 994.0G

  1  Clean up junk          (caches, logs, Trash, Xcode, dev caches)
  2  Find large files
  3  Applications           (uninstall, updates)
  4  Startup items
  5  Maintenance
  6  Security check
  7  Browser cleanup        (cookies, site by site)
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

With Homebrew:

```sh
brew tap shannong57/macsweep https://github.com/shannong57/macsweep
brew install shannong57/macsweep/macsweep
```

Or without it:

```sh
curl -fsSL https://raw.githubusercontent.com/shannong57/macsweep/main/macsweep -o /usr/local/bin/macsweep
chmod +x /usr/local/bin/macsweep
```

Or clone the repo and put `macsweep` anywhere on your `PATH`.

## What's in the menu

- **Clean up junk:** pick which categories to clear.
- **Find large files:** list the 20 largest files in a folder. Report only.
- **Applications:** uninstall an app and its leftover files, or see what's outdated across Homebrew, the App Store (needs the free `mas` tool) and macOS. Updates are report only, and apps that update themselves, like Chrome or Zoom, aren't covered.
- **Startup items:** see what launches in the background and who signed it. `!` marks programs that are unsigned, damaged or missing. Login items stay in System Settings.
- **Maintenance:** flush DNS, rebuild Spotlight, remove Time Machine local snapshots, fix duplicate "Open With" entries, and check the startup disk.
- **Security check:** see whether Gatekeeper, System Integrity Protection, FileVault and the firewall are on, and flag configuration profiles, unsigned apps and suspect startup items. You can turn off a flagged startup item and move it to the Trash. This is not a malware scan: it checks settings and signatures only.
- **Browser cleanup:** remove cookies site by site in Chrome, Edge, Brave, Arc, Vivaldi and Firefox, and keep a list of sites to always keep, such as your bank and email. The browser must be closed. Removed cookies sign you out of those sites and can't be restored. Passwords, history and bookmarks are never touched. Safari isn't supported: use Safari > Settings > Privacy > Manage Website Data.

## Commands for scripts

Everything in the menu that can run unattended also has a direct command.

| Command | What it does |
|---|---|
| `macsweep` | Open the menu. Without a terminal, it runs `scan` instead |
| `macsweep scan` | Show reclaimable space per category |
| `macsweep clean [CATEGORY...]` | Delete junk, asking first. `--dry-run` previews, `--yes` skips the prompt |
| `macsweep big [PATH] [--min MB]` | List the 20 largest files (report only, never deletes) |
| `macsweep uninstall APP [--yes]` | Move an app and its leftovers to the Trash |
| `macsweep security` | Report on security settings, app signatures and startup items |
| `macsweep updates` | List what's outdated (report only) |
| `macsweep startup` | List startup items |
| `macsweep startup enable\|disable LABEL` | Turn one of the startup agents on or off |

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
- Uninstalling moves files to the Trash, so Finder's Put Back can restore them. It refuses running apps and Apple's own apps, like Pages, except Xcode. Xcode from the App Store belongs to the system, so Finder may ask for an admin password. Its simulators and archived builds in `~/Library/Developer` stay in place, and the uninstaller shows their size. Leftovers are matched on the app's exact ID and name only.
- Files outside your home folder are never removed by the uninstaller. It prints the `sudo` command so you can decide.
- System-wide startup daemons are never changed for you. You get the `sudo` command instead.
- Turning a startup item off can be reversed from the same menu. Removing Time Machine snapshots can't be undone, so the menu says so first.

macOS protects some folders, `~/.Trash` included. To clean them, give your terminal **Full Disk Access** in System Settings → Privacy & Security.

## Tests

```sh
./test.sh
```

The tests run against a temporary fake home folder with stand-ins for the macOS tools, so they touch nothing real. They work on macOS or Linux.

## License

MIT. Not affiliated with MacPaw or CleanMyMac.
