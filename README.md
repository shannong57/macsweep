# macsweep

Clean up and look after your Mac from a simple terminal menu: clear junk, find large files, uninstall apps, check for updates, manage startup items and run maintenance tasks. One Bash script, no dependencies.

Run `macsweep` and pick from the menu. There are no commands to remember.

```
$ macsweep

  macsweep — Mac cleanup            Disk: 182.0G free of 994.0G

  1. Clean up junk          (caches, logs, Trash, Xcode, dev and app caches)
  2. Large and duplicate files
  3. Applications           (uninstall, leftovers, updates)
  4. Startup items
  5. Maintenance
  6. Security check
  7. Browser cleanup        (cookies, site by site)
  8. Performance check
  9. Tweaks                 (hidden settings)
  q  Quit

Choose: 1

  Clean up junk — scanning...
  1. Caches           7.3G
  2. Logs            91.3M
  3. Trash            1.1G
  4. Xcode            0.0K
  5. Dev caches      12.8G
  a  All     b  Back

Clean which? (numbers, a for all, b to go back): 1 2
```

Every list works the same way: type a number, confirm, and you return to that menu. `b` goes back and `q` quits from anywhere.

## Install

With Homebrew:

```sh
brew install shannong57/tap/macsweep
```

Installed it with the older two-step tap? Switch with `brew uninstall macsweep && brew untap shannong57/macsweep`, then run the line above.

Or without it:

```sh
curl -fsSL https://raw.githubusercontent.com/shannong57/macsweep/main/macsweep -o /usr/local/bin/macsweep
chmod +x /usr/local/bin/macsweep
```

Or clone the repo and put `macsweep` anywhere on your `PATH`.

## What's in the menu

- **Clean up junk:** pick which categories to clear.
- **Large and duplicate files:** list the 20 largest files in a folder, or find files with identical contents and pick which copy to keep. The other copies go to the Trash. Matches are checked byte for byte. `~/Library`, the Trash, cloud-only files, and the insides of apps, photo libraries and other packages are skipped.
- **Applications:** uninstall an app along with everything it left behind, clean up after apps that are already gone, or see what's outdated across Homebrew, the App Store (needs the free `mas` tool) and macOS. Updates are report only, and apps that update themselves, like Chrome or Zoom, aren't covered.
- **Startup items:** see what launches in the background and who signed it. `!` marks programs that are unsigned, damaged or missing. Login items stay in System Settings.
- **Maintenance:** flush DNS, rebuild Spotlight, remove Time Machine local snapshots, fix duplicate "Open With" entries, check the startup disk, and clean up Homebrew, unavailable Xcode simulators and Docker.
- **Security check:** see whether Gatekeeper, System Integrity Protection, FileVault and the firewall are on, and flag configuration profiles, unsigned apps and suspect startup items. You can turn off a flagged startup item and move it to the Trash. This is not a malware scan: it checks settings and signatures only.
- **Browser cleanup:** remove cookies site by site in Chrome, Edge, Brave, Arc, Vivaldi and Firefox, and keep a list of sites to always keep, such as your bank and email. The browser must be closed. Removed cookies sign you out of those sites and can't be restored. Passwords, history and bookmarks are never touched. Safari isn't supported: use Safari > Settings > Privacy > Manage Website Data.
- **Performance check:** the apps using the most CPU and memory right now, plus memory pressure, swap, overheating, free disk space, time since the last restart and battery health. Report only.
- **Tweaks:** turn hidden macOS settings on or off: no `.DS_Store` files on network drives, an instant Dock, fewer animations, hidden files and the path bar in Finder, and faster Time Machine backups until the next restart. Each shows whether it's on, and turning it off puts back Apple's default. Turning off Gatekeeper or System Integrity Protection is left out on purpose.

## Commands for scripts

Everything in the menu that can run unattended also has a direct command.

| Command | What it does |
|---|---|
| `macsweep` | Open the menu. Without a terminal, it runs `scan` instead |
| `macsweep scan` | Show reclaimable space per category |
| `macsweep clean [CATEGORY...]` | Delete junk, asking first. `--dry-run` previews, `--yes` skips the prompt. App caches show as one line per app; `--verbose` lists every folder |
| `macsweep big [PATH] [--min MB]` | List the 20 largest files (report only, never deletes) |
| `macsweep dupes [PATH] [--min MB]` | List files with identical contents (report only, never deletes) |
| `macsweep uninstall APP [--yes]` | Remove an app and everything it left behind. `--dry-run` shows what would go and removes nothing |
| `macsweep leftovers [--yes]` | Remove what already-removed apps left behind |
| `macsweep security` | Report on security settings, app signatures and startup items |
| `macsweep performance` | Report what's using CPU, memory and disk right now |
| `macsweep updates` | List what's outdated (report only) |
| `macsweep startup` | List startup items |
| `macsweep startup enable\|disable LABEL` | Turn one of the startup agents on or off |

| Category | Cleared |
|---|---|
| `caches` | `~/Library/Caches` |
| `logs` | `~/Library/Logs` |
| `trash` | `~/.Trash` |
| `xcode` | `~/Library/Developer/Xcode/DerivedData`, `~/Library/Developer/CoreSimulator/Caches`, and the `DeviceSupport` folders in `~/Library/Developer/Xcode`. Xcode rebuilds these when needed. It also asks Xcode to delete the simulators it can no longer run (`xcrun simctl delete unavailable`). If no Xcode is installed at all, every simulator in `~/Library/Developer/CoreSimulator/Devices` is cleared, since nothing can run them |
| `devcaches` | `~/.npm/_cacache`, `~/.gradle/caches`, `~/.cache` |
| `appcaches` | Cache folders that Chrome, Slack, Notion and other Chromium or Electron apps keep in `~/Library/Application Support` (`Cache`, `Code Cache`, `GPUCache`, `CacheStorage` and similar). Logins, history and settings stay. The apps rebuild these, so they start slower once afterwards |
| `backups` | `~/Library/Application Support/MobileSync/Backup`: iPhone and iPad backups. Only cleaned when you pick it, never by "clean all". They may be the only copy of a device and are deleted, not moved to the Trash |

## Safety

- Only clears the *contents* of the folders above. The folders themselves stay.
- Refuses any target that is a symlink or resolves outside your home folder. Symlinks inside a target are removed, but the files they point to are not.
- Asks before deleting. Without a terminal it refuses unless you pass `--yes`.
- Apps rebuild their caches, so the first launch afterwards may be slower.
- Uninstalling moves the app and its files in your home folder to the Trash, so Finder's Put Back can restore them until you empty it. If the app is running, it offers to force quit it first (unsaved work in it is lost; with `--yes` it refuses instead). It refuses Apple's own apps, like Pages, except Xcode and old macOS installers. Xcode from the App Store belongs to the system, so Finder may ask for an admin password. Its simulators and archived builds in `~/Library/Developer` stay in place, and the uninstaller shows their size. Its files are matched on the app's ID (alone, or with a helper name, team ID or file ending around it) and on its exact name. Files named after another installed app are never taken, even when its ID starts the same way. When the app is the last one installed from its maker, everything under the maker's part of the ID goes too (`com.dropbox.*` along with `com.dropbox.client`); the uninstaller says so before you confirm. Afterwards it lists items that only have a similar name and lets you pick which of those to remove. None are removed unless you pick them, and with `--yes` they are only listed.
- Leftovers of removed apps are files in `~/Library` and `/Library` named after an app ID whose maker (the `com.example` part) has no app installed, plus folders in Applications that no longer hold a working app, plus installer records whose files are all gone. Apple's files, shared-group files and launch agents whose program still exists are never listed, and neither is anything whose maker's name is part of an installed app's name or ID (`com.dropbox.*` while Dropbox is installed). In `/Library`, a maker with a background job whose program still exists counts as installed, so drivers and VPNs without an app are left alone. Items in your home folder go to the Trash. Items in `/Library` and installer records need your admin password and are removed for good; the list says so before you confirm. A folder named only by the app's name is listed when it matches the name in such an ID (`CleanMyMac_5_HealthMonitor` for `com.macpaw.CleanMyMac5.HealthMonitor`) and no installed app has that name. Leftovers from a maker that still has another app installed aren't found.
- The uninstaller also removes what the app put outside your home folder: its startup jobs, helper tools and files in `/Library`. These are listed before you confirm, need your admin password, and are deleted for good instead of going to the Trash. It then clears the app's privacy permissions, its installer records and its Dock icon.
- Uninstall and leftovers write what they removed to `~/Library/Application Support/macsweep/removed.log`: one line per item, marked `trash`, `deleted` or `forgot` (an installer record). For files that skip the Trash it is the only record.
- A few traces can't be removed this way: passwords the app saved in your keychain, its App Store purchase record, and data it kept in a folder whose name has nothing of the app's or maker's name in it.
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

## Releasing

1. Bump `VERSION` in `macsweep` in a PR and merge it.
2. Tag the merge commit and push the tag: `git tag -a v1.2.3 -m "macsweep 1.2.3" && git push origin v1.2.3`.
3. The `release` workflow checks the tag matches `VERSION` and publishes a GitHub Release.
4. Within a day, [homebrew-tap](https://github.com/shannong57/homebrew-tap) opens a tested PR that points the formula at the new release. Start its `bump` workflow from the Actions tab to skip the wait.
