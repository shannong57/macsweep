#!/usr/bin/env bash
# Runs macsweep against a throwaway fake $HOME. Usage: ./test.sh
# shellcheck disable=SC2016  # stub bodies expand when the stub runs
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
export HOME="$root/home dir"     # space on purpose
outside="$root/outside"

fail() { echo "FAIL: $*"; exit 1; }
mk() { mkdir -p "$(dirname "$1")"; head -c "${2:-2048}" /dev/zero > "$1"; }

mk "$HOME/Library/Caches/com.foo/blob" 200000
mk "$HOME/Library/Logs/app.log"
mk "$HOME/.Trash/old file.zip"
mk "$HOME/.npm/_cacache/x"
mk "$HOME/Documents/keep.txt"
mk "$outside/precious.txt"
ln -s "$outside" "$HOME/Library/Caches/link-out"   # must remove the link, not the target
ln -s "$outside" "$HOME/Library/Developer/Xcode/DerivedData" 2>/dev/null \
  || { mkdir -p "$HOME/Library/Developer/Xcode"; ln -s "$outside" "$HOME/Library/Developer/Xcode/DerivedData"; }

ms="$here/macsweep"
# No test may ask a real Xcode to delete simulators.
mkdir -p "$root/bin"
for c in xcode-select xcrun mdfind; do printf '#!/bin/sh\nexit 2\n' > "$root/bin/$c"; chmod +x "$root/bin/$c"; done
export PATH="$root/bin:$PATH"

out=$("$ms" scan); echo "$out" | grep -q "caches" || fail "scan output: $out"
"$ms" clean --dry-run >/dev/null
[ -f "$HOME/Library/Logs/app.log" ] || fail "dry run deleted files"
"$ms" clean bogus 2>/dev/null && fail "accepted unknown category"
"$ms" clean </dev/null &>/dev/null && fail "cleaned without a tty or --yes"

"$ms" clean caches logs --yes >/dev/null
[ -z "$(ls -A "$HOME/Library/Caches")" ] || fail "caches not cleared"
[ -d "$HOME/Library/Caches" ] || fail "caches dir itself removed"
[ -z "$(ls -A "$HOME/Library/Logs")" ] || fail "logs not cleared"
[ -f "$HOME/.Trash/old file.zip" ] || fail "trash touched when not selected"

"$ms" clean --yes >/dev/null
[ -z "$(ls -A "$HOME/.Trash")" ] || fail "trash not cleared"
[ -f "$HOME/Documents/keep.txt" ] || fail "deleted Documents"
[ -f "$outside/precious.txt" ] || fail "followed a symlink out of HOME"

# App caches: only the cache folders inside an app's data go, and never Apple's.
AS="$HOME/Library/Application Support"
mk "$AS/Fake Chat/Partitions/x/Code Cache/blob" 50000; mk "$AS/Fake Chat/Service Worker/CacheStorage/blob"
mk "$AS/Fake Chat/Local Storage/keep"; mk "$AS/Fake Chat/Cookies"; mk "$AS/com.apple.thing/Cache/keep"
ln -s "$outside" "$AS/Fake Chat/GPUCache"
"$ms" scan | grep -q "appcaches" || fail "scan misses appcaches"
"$ms" clean caches --yes >/dev/null; [ -f "$AS/Fake Chat/Partitions/x/Code Cache/blob" ] || fail "caches took an app cache"
out=$("$ms" clean appcaches --dry-run)
echo "$out" | grep -q "Fake Chat (2 cache folders)" || fail "app caches not grouped by app: $out"
echo "$out" | grep -q "Code Cache" && fail "grouped preview still lists folders: $out"
"$ms" clean appcaches -n --verbose | grep -q "Partitions/x/Code Cache" || fail "--verbose doesn't list folders"
"$ms" clean appcaches --yes >/dev/null
[ ! -e "$AS/Fake Chat/Partitions/x/Code Cache/blob" ] && [ ! -e "$AS/Fake Chat/Service Worker/CacheStorage/blob" ] || fail "app caches not cleared"
[ -d "$AS/Fake Chat/Partitions/x/Code Cache" ] || fail "app cache folder itself removed"
[ -f "$AS/Fake Chat/Local Storage/keep" ] && [ -f "$AS/Fake Chat/Cookies" ] || fail "appcaches took app data"
[ -f "$AS/com.apple.thing/Cache/keep" ] || fail "appcaches took an Apple cache"
[ -f "$outside/precious.txt" ] || fail "appcaches followed a symlink out of HOME"
rm -rf "$AS/Fake Chat" "$AS/com.apple.thing"

mk "$HOME/big.bin" 3000000
"$ms" big --min 1 | grep -q "big.bin" || fail "big didn't find big.bin"
"$ms" big --min x 2>/dev/null && fail "accepted bad --min"
HOME=/ "$ms" scan 2>/dev/null && fail "ran with HOME=/"

# Menu: stdin stands in for the keyboard.
# shellcheck disable=SC2059  # the argument is the scripted keystrokes
menu() { printf "$1" | "$ms" menu; }
mk "$HOME/Library/Caches/a"; mk "$HOME/Library/Logs/b"
kept() { [ -f "$HOME/Library/Caches/a" ] && [ -f "$HOME/Library/Logs/b" ] || fail "$1"; }

menu "q\n" | grep -q "Clean up junk" || fail "menu not shown"
menu "q\n" | grep -q "  1. Clean up junk" || fail "menu numbers not 1. 2. 3."
menu "5.\nb\nq\n" | grep -q "Flush the DNS cache" || fail "choice with a dot not accepted"
menu "q\n" | grep -q $'\033' && fail "escape codes in captured output"
menu "1\n   \nb\nq\n" >/dev/null; kept "blank selection cleaned something"
menu "1\n9\n0\nx\n1 9\nb\nq\n" >/dev/null; kept "bad selection cleaned something"
menu "1\n1\nn\nb\nq\n" >/dev/null; kept "declining cleaned something"
menu "1\n1\n" >/dev/null; kept "end of input cleaned something"
menu "x\nq\n" | grep -q "Not a valid choice" || fail "bad main choice not rejected"

menu "1\n1\ny\nb\nq\n" >/dev/null
[ ! -e "$HOME/Library/Caches/a" ] || fail "menu did not clean caches"
[ -f "$HOME/Library/Logs/b" ] || fail "menu cleaned logs when only caches picked"
menu "1\na\ny\nq\n" >/dev/null
[ ! -e "$HOME/Library/Logs/b" ] || fail "menu all did not clean logs"
[ -f "$HOME/Documents/keep.txt" ] || fail "menu deleted Documents"

menu "2\n1\n\n1\n\nq\n" | grep -q "big.bin" || fail "menu large files missed big.bin"
menu "2\n1\n~\n1\n\nq\n" | grep -q "big.bin" || fail "menu large files did not expand ~"
menu "2\n1\n/no/such/dir\nq\n" | grep -q "Not a folder" || fail "bad folder not rejected"
menu "2\n1\n\nabc\nq\n" | grep -q "whole number" || fail "bad size not rejected"
"$ms" </dev/null | grep -q TOTAL || fail "no terminal should still scan"

# Everything below runs against stubs: no real app, Trash or system setting is touched.
export MACSWEEP_ROOT="$root/sys"
calls="$root/calls"; : > "$calls"; export calls
mkdir -p "$root/bin" "$root/trashed" "$MACSWEEP_ROOT/usr/bin"; export trashed="$root/trashed"
stub() { printf '#!/usr/bin/env bash\necho "%s $*" >> "$calls"\n%s\n' "$1" "${2:-}" > "$root/bin/$1"; chmod +x "$root/bin/$1"; }
stub plutil '[ "$1" = -remove ] && exit 0; f="${@: -1}"; v=$(sed -n "s/^$2=//p" "$f" 2>/dev/null); [ -n "$v" ] && printf "%s\n" "$v"'
# Includes the real process list, so a check that matches itself gets caught on a Mac.
stub ps 'echo "${PS_OUT:-}"; /bin/ps -axo command= 2>/dev/null || true'
cat > "$MACSWEEP_ROOT/usr/bin/trash" <<'S'
#!/usr/bin/env bash
shift
for f in "$@"; do case "$f" in *Stuck*|*Xcode.app) exit 1 ;; esac; mv "$f" "$trashed/$(basename "$f")-$RANDOM"; done
S
chmod +x "$MACSWEEP_ROOT/usr/bin/trash"
stub osascript 'case "$2" in *Stuck*) exit 1 ;; esac; mv "$2" "$trashed/$(basename "$2")-$RANDOM"'
export PATH="$root/bin:$PATH"

app() {  # app DIR NAME ID SIZE
  mkdir -p "$1/$2.app/Contents"
  printf 'CFBundleIdentifier=%s\nCFBundleShortVersionString=1.2.3\n' "$3" > "$1/$2.app/Contents/Info.plist"
  head -c "$4" /dev/zero > "$1/$2.app/Contents/pad"
}
A="$MACSWEEP_ROOT/Applications"; L="$HOME/Library"
app "$A" "Fake App" com.fake.app 900000
app "$A" Thing com.apple.Thing 800000
app "$HOME/Applications" Evil ../.. 20000
app "$A" Stuck com.fake.stuck 5000
mk "$L/Application Support/Fake App/data"
mk "$L/Application Support/com.fake.app/data"
mk "$L/Caches/com.fake.app/data"
mk "$L/Preferences/com.fake.app.plist"
mk "$L/Containers/com.fake.app/data"
mk "$L/Saved Application State/com.fake.app.savedState/data"
mk "$L/Caches/com.fake.app2/keep"
mk "$L/Caches/com.fake.stuck/keep"
mk "$MACSWEEP_ROOT/Library/LaunchDaemons/com.fake.app.plist"
# What a full uninstall also has to find: helpers, team-ID and group names, the maker's folder, crash reports.
full="Caches/com.fake.app.helper/x
Preferences/ByHost/com.fake.app.ABC123.plist
Group Containers/ABCDE12345.com.fake.app/x
Group Containers/group.com.fake.app/x
Application Scripts/com.fake.app/x
Cookies/com.fake.app.binarycookies
LaunchAgents/com.fake.app.agent.plist
Caches/Fake App/x
Application Support/Fake/App/x
Logs/DiagnosticReports/Fake App-2026-01-02-030405.ips"
mk "$MACSWEEP_ROOT/Library/PrivilegedHelperTools/com.fake.app.helper"
mk "$MACSWEEP_ROOT/Library/LaunchDaemons/com.fake.app2.plist"
stub sudo '"$@"'; stub launchctl; stub tccutil; stub killall
stub pkgutil '[ "$1" = --pkgs ] && printf "com.fake.app.pkg\ncom.fake.app2.pkg\ncom.fake.app.beta.pkg\ncom.solo.driver\n"; exit 0'
stub defaults '[ "$1" = export ] && printf "persistent-apps=2\npersistent-apps.1.tile-data.bundle-identifier=com.fake.app\n" > "$3"; exit 0'

out=$(menu "3\n1\nb\nb\nq\n")
echo "$out" | grep -q "Fake App" || fail "uninstall list missing app: $out"
echo "$out" | grep -q "Thing" && fail "uninstall list shows Apple app"
"$ms" uninstall Thing --yes 2>/dev/null && fail "uninstalled an Apple app"
[ -d "$A/Thing.app" ] || fail "Apple app removed"
"$ms" uninstall "Fake App" </dev/null &>/dev/null && fail "uninstalled without a tty or --yes"
"$ms" uninstall Nope --yes 2>/dev/null && fail "accepted unknown app"
out=$("$ms" uninstall "Fake App" --dry-run </dev/null)
echo "$out" | grep -q "nothing removed" || fail "uninstall dry run: $out"
[ "$(echo "$out" | grep -c "Caches/com.fake.app$")" = 1 ] || fail "uninstall dry run lists an item twice: $out"
[ -d "$A/Fake App.app" ] && [ -f "$L/Caches/com.fake.app/data" ] || fail "uninstall dry run removed something"
grep -q "^sudo\|^tccutil\|^launchctl\|^killall\|^osascript" "$calls" && fail "uninstall dry run ran a command: $(cat "$calls")"
menu "3\n1\n99\n0\nabc\nb\nb\nq\n" >/dev/null
menu "3\n1\n1\nn\nb\nb\nq\n" >/dev/null
[ -d "$A/Fake App.app" ] || fail "uninstalled after declining"
PS_OUT="1 $A/Fake App.app/Contents/MacOS/Fake" "$ms" uninstall "fake app" --yes | grep -q "is running" || fail "running app not refused"
[ -d "$A/Fake App.app" ] || fail "removed a running app"
sleep 60 & pid=$!
out=$(PS_OUT="$pid $A/Fake App.app/Contents/MacOS/Fake" menu "3\n1\n1\nn\nb\nb\nq\n")
echo "$out" | grep -q "Force quit it" || fail "no force quit offer: $out"
kill -0 "$pid" 2>/dev/null || fail "force quit without a yes"
[ -d "$A/Fake App.app" ] || fail "removed a running app after declining"
cp -R "$A/Fake App.app" "$root/fake-copy.app"
out=$(PS_OUT="$pid $A/Fake App.app/Contents/MacOS/Fake" menu "3\n1\n1\ny\nb\nb\nq\n")
{ wait "$pid"; } 2>/dev/null && fail "force quit did not kill the app"
[ ! -e "$A/Fake App.app" ] || fail "not uninstalled after force quit: $out"
mv "$root/fake-copy.app" "$A/Fake App.app"

"$ms" uninstall Evil --yes >/dev/null
[ ! -e "$HOME/Applications/Evil.app" ] || fail "evil app not removed"
[ -f "$HOME/Documents/keep.txt" ] && [ -d "$L/Caches" ] || fail "app ID climbed out of Library"

out=$("$ms" uninstall Stuck --yes || true); echo "$out" | grep -q "Couldn't move" || fail "trash failure hidden: $out"
[ -d "$L/Caches/com.fake.stuck" ] || fail "removed leftovers when the app could not be moved"

app "$A" "Fake Beta" com.fake.app.beta 1000
(IFS=$'\n'; for p in $full; do mk "$L/$p"; done)
mk "$L/Caches/com.fake.app.beta/keep"                # Fake Beta is a separate, installed app
mk "$L/Application Support/Other/Fake App/keep"     # another app's folder about this one
mk "$L/Logs/DiagnosticReports/Fake App Helper-2026-01-02-030405.ips"
# The force-quit uninstall above already took these once.
mk "$L/Application Support/Fake App/data"; mk "$L/Caches/com.fake.app/data"; mk "$L/Preferences/com.fake.app.plist"
mk "$MACSWEEP_ROOT/Library/LaunchDaemons/com.fake.app.plist"
mk "$MACSWEEP_ROOT/Library/PrivilegedHelperTools/com.fake.app.helper"
: > "$calls"
out=$(menu "3\n1\n1\ny\nb\nb\nq\n")
[ ! -e "$A/Fake App.app" ] || fail "menu did not uninstall"
(IFS=$'\n'; for p in $full; do [ ! -e "$L/$p" ] || fail "leftover kept: $p ($out)"; done)
for p in "Caches/com.fake.app.beta/keep" "Application Support/Other/Fake App/keep" "Logs/DiagnosticReports/Fake App Helper-2026-01-02-030405.ips"; do
  [ -f "$L/$p" ] || fail "took a file that isn't the app's: $p"
done
rm -rf "$A/Fake Beta.app"
for p in "Application Support/Fake App" "Application Support/com.fake.app" Caches/com.fake.app \
         Preferences/com.fake.app.plist Containers/com.fake.app "Saved Application State/com.fake.app.savedState"; do
  [ ! -e "$L/$p" ] || fail "leftover kept: $p"
done
[ -f "$L/Caches/com.fake.app2/keep" ] || fail "took another app's files"
[ ! -e "$MACSWEEP_ROOT/Library/LaunchDaemons/com.fake.app.plist" ] || fail "system-wide file kept: $out"
[ ! -e "$MACSWEEP_ROOT/Library/PrivilegedHelperTools/com.fake.app.helper" ] || fail "system-wide helper kept: $out"
[ -f "$MACSWEEP_ROOT/Library/LaunchDaemons/com.fake.app2.plist" ] || fail "took another app's system file"
echo "$out" | grep -q "deleted for good" || fail "no warning that system files skip the Trash: $out"
for c in "sudo launchctl bootout system/com.fake.app" "launchctl bootout gui/.*/com.fake.app.agent" "tccutil reset All com.fake.app" \
         "sudo pkgutil --forget com.fake.app.pkg" "plutil -remove persistent-apps.1 " "defaults import com.apple.dock" "killall Dock"; do
  grep -q -- "$c" "$calls" || fail "full uninstall skipped: $c ($(cat "$calls"))"
done
grep -q -- "--forget com.fake.app2.pkg\|--forget com.fake.app.beta.pkg" "$calls" && fail "forgot another app's package"
echo "$out" | grep -q "Moved" || fail "no result message"
log="$L/Application Support/macsweep/removed.log"
for c in "uninstall Fake App 1.2.3 (com.fake.app)" "trash    .*Caches/com.fake.app$" "deleted  .*LaunchDaemons/com.fake.app.plist" "forgot   com.fake.app.pkg"; do
  grep -q "$c" "$log" || fail "uninstall not logged: $c ($(cat "$log"))"
done
grep -q "com.fake.app2" "$log" && fail "logged a file that stayed"

# Solo Tool is its maker's only app, so everything under com.solo goes with it. Fake App above was not:
# Stuck shares com.fake, which is why com.fake.app2 survived. Similar names are offered, never taken unasked.
app "$A" "Solo Tool" com.solo.tool 9000
mk "$L/Caches/com.solo.updater/x"; mk "$L/Preferences/com.solo.other.plist"; mk "$L/Group Containers/ABCDE12345.com.solo.shared/x"
mk "$MACSWEEP_ROOT/Library/LaunchAgents/com.solo.loginscreen.plist"
mk "$L/Application Support/SoloSDK/x"; mk "$L/Caches/Solo Tool Cache/x"; mk "$L/Caches/Solomon/keep"
mk "$L/Caches/com.fake.stuck.solotool/keep"          # has the name in it, but is an installed app's
: > "$calls"
out=$(menu "3\n1\n1\ny\n1\nb\nb\nq\n")
[ ! -e "$A/Solo Tool.app" ] || fail "Solo Tool not uninstalled: $out"
for p in "$L/Caches/com.solo.updater" "$L/Preferences/com.solo.other.plist" "$L/Group Containers/ABCDE12345.com.solo.shared" \
         "$MACSWEEP_ROOT/Library/LaunchAgents/com.solo.loginscreen.plist"; do
  [ ! -e "$p" ] || fail "maker's file kept though no other app of theirs is installed: $p ($out)"
done
echo "$out" | grep -q "last app installed from its maker" || fail "maker sweep not announced: $out"
grep -q -- "--forget com.solo.driver" "$calls" || fail "maker's package record kept"
echo "$out" | grep -q "may also belong to Solo Tool" || fail "similar names not offered: $out"
echo "$out" | grep -q "com.fake.stuck.solotool" && fail "offered an installed app's file: $out"
[ ! -e "$L/Application Support/SoloSDK" ] || fail "picked item not removed: $out"
[ -d "$L/Caches/Solo Tool Cache" ] || fail "removed a similar-named item that was not picked"
[ -f "$L/Caches/Solomon/keep" ] && [ -f "$L/Caches/com.fake.stuck.solotool/keep" ] || fail "took an unrelated file"
app "$A" "Solo Tool" com.solo.tool 9000
out=$("$ms" uninstall "Solo Tool" --yes)
echo "$out" | grep -q "left in place" && [ -d "$L/Caches/Solo Tool Cache" ] || fail "--yes removed a similar-named item: $out"
rm -rf "$L/Caches/Solo Tool Cache" "$L/Caches/Solomon" "$L/Caches/com.fake.stuck.solotool"

# Xcode is the one Apple app that can go. The trash stub refuses it, like a root-owned app, so Finder takes over.
app "$A" Xcode com.apple.dt.Xcode 5000
mk "$L/Preferences/com.apple.dt.Xcode.plist"
mk "$L/Developer/Xcode/Archives/keep"
: > "$calls"
out=$("$ms" uninstall xcode --yes)
[ ! -e "$A/Xcode.app" ] || fail "Xcode not removed: $out"
grep -q "osascript" "$calls" || fail "Finder not tried after trash refused"
[ ! -e "$L/Preferences/com.apple.dt.Xcode.plist" ] || fail "Xcode leftover kept"
[ -f "$L/Developer/Xcode/Archives/keep" ] || fail "removed archived builds"
echo "$out" | grep -q "Library/Developer" || fail "Developer folder not mentioned: $out"

# Leftovers of apps that are already gone. Stuck (com.fake.stuck) is still installed.
mk "$L/Caches/com.gone.app/data"
mk "$L/Preferences/com.gone.app.plist"
mk "$L/HTTPStorages/com.gone.app.binarycookies"
mk "$L/Caches/com.fake.helper/keep"
mk "$L/Containers/ABCDE12345.com.fake.browser-helper/keep"
mk "$L/Preferences/com.apple.finder.plist"
mk "$L/Preferences/group.com.gone.shared.plist"
mk "$L/Caches/Some Folder/keep"
mk "$L/Caches/com.gone.WidgetMaker/x"
mk "$L/Application Support/Widget_Maker/x"            # named after the gone app above
mk "$L/Caches/com.gone.thing/x"
mk "$L/Application Support/Thing/keep"               # also the name of an installed app
mk "$HOME/bin/tool"
mkdir -p "$L/LaunchAgents"
echo "ProgramArguments.0=$HOME/bin/tool" > "$L/LaunchAgents/com.gone.tool.plist"
echo "ProgramArguments.0=$HOME/bin/missing" > "$L/LaunchAgents/com.gone.dead.plist"
mk "$A/Gone Vendor/readme"
mkdir -p "$A/Vendor Links"; ln -s "$A/Stuck.app" "$A/Vendor Links/Stuck"
mk "$A/Half.app/Contents/Resources/x"
mk "$A/Phone.app/Wrapper/Phone.app/Info.plist"
mkdir -p "$HOME/Applications/Chrome Apps.localized"
gone="$A/Gone Vendor
$A/Half.app
$L/Application Support/Widget_Maker
$L/Caches/com.gone.WidgetMaker
$L/Caches/com.gone.thing
$L/Caches/com.gone.app
$L/HTTPStorages/com.gone.app.binarycookies
$L/LaunchAgents/com.gone.dead.plist
$L/Preferences/com.gone.app.plist"
IFS=$'\n'   # $gone holds paths with spaces
kept_left() {
  for p in "$L/Caches/com.fake.helper/keep" "$L/Containers/ABCDE12345.com.fake.browser-helper/keep" "$L/Preferences/com.apple.finder.plist" "$L/Preferences/group.com.gone.shared.plist" \
           "$L/Caches/Some Folder/keep" "$L/Application Support/Thing/keep" "$L/LaunchAgents/com.gone.tool.plist" "$A/Vendor Links/Stuck" "$A/Phone.app/Wrapper/Phone.app/Info.plist" \
           "$HOME/Applications/Chrome Apps.localized"; do
    [ -e "$p" ] || [ -L "$p" ] || fail "$1: $p"
  done
}
out=$("$ms" leftovers </dev/null 2>&1 || true)
for p in $gone; do echo "$out" | grep -qF "$p" || fail "leftover not listed: $p ($out)"; done
[ "$(echo "$out" | grep -c '^ *[0-9]*\. ')" = 9 ] || fail "listed something it should keep: $out"
for p in $gone; do [ -e "$p" ] || fail "moved without a tty or --yes: $p"; done
mk "$L/Caches/com.gonestuck.Stuck/x"
out=$("$ms" leftovers --yes || true)
echo "$out" | grep -q "Full Disk Access" || fail "no permission hint after a failed move: $out"
[ ! -e "$A/Half.app" ] && [ ! -e "$L/Caches/com.gone.app" ] || fail "leftovers not moved: $out"
rm -rf "$L/Caches/com.gonestuck.Stuck"; kept_left "leftovers --yes took a kept file"
for p in $gone; do mk "$p/x"; done
menu "3\n3\n99\nb\nb\nq\n" >/dev/null; menu "3\n3\n1\nn\nb\nb\nq\n" >/dev/null
for p in $gone; do [ -e "$p" ] || fail "menu moved after declining: $p"; done
menu "3\n3\n1\ny\nb\nb\nq\n" >/dev/null
[ ! -e "$A/Gone Vendor" ] && [ -e "$A/Half.app" ] || fail "menu moved the wrong item"
out=$(menu "3\n3\na\ny\n\nb\nq\n")
for p in $gone; do [ ! -e "$p" ] || fail "menu left $p"; done
echo "$out" | grep -q "No leftovers of removed apps found" || fail "list not refreshed: $out"
kept_left "menu took a kept file"
IFS=$' \t\n'
[ -d "$A/Thing.app" ] || fail "other Apple app removed"

# Leftovers also covers the folders uninstall does, /Library and installer records. In /Library only
# ID-named items count, and a maker with a working background job is still installed.
SL="$MACSWEEP_ROOT/Library"
mk "$L/Group Containers/ABCDE12345.com.gone.app/x"; mk "$L/Application Scripts/com.gone.app/x"
mk "$L/Group Containers/ABCDE12345.groups.com.apple.thing/keep"
mk "$SL/PrivilegedHelperTools/com.gone.app.helper"; mk "$SL/Application Support/Gone App/keep"
mk "$SL/Preferences/com.driver.thing.plist"; mk "$SL/Application Support/regid.1986-12.com.fake/keep"
mk "$L/Caches/com.stuck.Updater/keep"                # maker named like the installed app Stuck (com.fake.stuck)
printf 'Label=com.driver.daemon\nProgram=%s\n' "$HOME/bin/tool" > "$SL/LaunchDaemons/com.driver.daemon.plist"
stub pkgutil 'case "$1" in
  --pkgs) printf "com.gone.pkg\ncom.fake.live.pkg\ncom.apple.pkg.X\ncom.empty.pkg\ncom.fake.updated.pkg\n" ;;
  --pkg-info) echo "location: Applications" ;;
  --only-files) case "$3" in com.gone.pkg|com.fake.updated.pkg) echo "Gone.app/x" ;; com.fake.live.pkg) echo "Stuck.app/Contents/Info.plist" ;; esac ;;
esac; exit 0'
: > "$calls"
out=$("$ms" leftovers --yes)
for p in "$L/Group Containers/ABCDE12345.com.gone.app" "$L/Application Scripts/com.gone.app" "$SL/PrivilegedHelperTools/com.gone.app.helper"; do
  [ ! -e "$p" ] || fail "leftover kept: $p ($out)"
done
for p in "$L/Group Containers/ABCDE12345.groups.com.apple.thing/keep" "$SL/Application Support/Gone App/keep" \
         "$SL/Preferences/com.driver.thing.plist" "$SL/LaunchDaemons/com.driver.daemon.plist" "$SL/LaunchDaemons/com.fake.app2.plist" \
         "$SL/Application Support/regid.1986-12.com.fake/keep" "$L/Caches/com.stuck.Updater/keep"; do
  [ -f "$p" ] || fail "leftovers took a file it should keep: $p ($out)"
done
echo "$out" | grep -q "installer record com.gone.pkg" || fail "dead installer record not listed: $out"
grep -q -- "--forget com.gone.pkg" "$calls" || fail "dead installer record kept: $out"
grep -q -- "--forget com.fake.live.pkg\|--forget com.apple\|--forget com.empty\|--forget com.fake.updated" "$calls" && fail "forgot a live installer record"
echo "$out" | grep -q "removed for good" || fail "no warning that /Library items skip the Trash: $out"
grep -q "deleted  .*com.gone.app.helper" "$log" || fail "leftovers not logged: $(cat "$log")"
grep -q "forgot   com.gone.pkg" "$log" || fail "forgotten record not logged: $(cat "$log")"
rm -r "$SL/LaunchDaemons/com.driver.daemon.plist" "$SL/Preferences/com.driver.thing.plist" "$L/Caches/com.stuck.Updater"

stub brew '[ "$1" = outdated ] && echo "git (2.1) < 2.2"'
stub softwareupdate 'printf "Software Update found:\n* Label: macOS 99.1\n\tTitle: macOS\n"'
out=$(menu "3\n2\n\nb\nq\n")
echo "$out" | grep -q "git (2.1)" || fail "brew update missing: $out"
echo "$out" | grep -q "macOS 99.1" || fail "macOS update missing: $out"
echo "$out" | grep -q "mas" || fail "no hint for missing mas: $out"
grep -q "brew upgrade" "$calls" && fail "updates installed something"

# Startup items
stub launchctl '[ "$1" = print-disabled ] && case "$2" in gui/*) echo "  \"com.fake.off\" => disabled" ;; esac; exit 0'
stub codesign 'case "$*" in *nosig*) exit 1 ;; *-dv*) echo "Authority=Developer ID Application: Fake Inc. (ABC123)" >&2 ;; esac; exit 0'
agent() {  # agent DIR LABEL PROGRAM
  mkdir -p "$1"; printf 'Label=%s\nProgram=%s\n' "$2" "$3" > "$1/$2.plist"
}
good="$root/bin/good"; : > "$good"; nosig="$root/bin/nosig"; : > "$nosig"
UA="$L/LaunchAgents"
agent "$UA" com.fake.agent "$good"
agent "$UA" com.fake.off "$good"
agent "$UA" com.fake.unsigned "$nosig"
agent "$UA" com.fake.zgone /no/such/program
agent "$UA" 'com.fake.x;rm' "$good"
rm "$MACSWEEP_ROOT/Library/LaunchDaemons/com.fake.app2.plist"
agent "$MACSWEEP_ROOT/Library/LaunchDaemons" com.fake.daemon "$good"

out=$(menu "4\nb\nq\n")
echo "$out" | grep "com.fake.agent" | grep -q "Fake Inc." || fail "signer not shown: $out"
echo "$out" | grep "com.fake.off" | grep -q "off" || fail "disabled state not shown: $out"
echo "$out" | grep "com.fake.unsigned" | grep -q "! not signed" || fail "unsigned not flagged: $out"
echo "$out" | grep "com.fake.zgone" | grep -q "! program missing" || fail "missing not flagged: $out"
echo "$out" | grep -q "Login Items" || fail "login items pointer missing: $out"

num() { "$ms" startup | awk -v l="$1" 'index($0, l) { print $1 + 0; exit }'; }
: > "$calls"
menu "4\n$(num com.fake.agent)\nn\nb\nq\n" >/dev/null
grep -q "launchctl disable" "$calls" && fail "changed an item after declining"
menu "4\n99\nabc\nb\nq\n" >/dev/null
grep -q "launchctl disable" "$calls" && fail "bad choice changed an item"
menu "4\n$(num com.fake.agent)\ny\nb\nq\n" >/dev/null
grep -q "launchctl disable gui/$(id -u)/com.fake.agent" "$calls" || fail "item not disabled"
grep -q "launchctl bootout gui/$(id -u)/com.fake.agent" "$calls" || fail "item not stopped"
menu "4\n$(num com.fake.off)\ny\nb\nq\n" >/dev/null
grep -q "launchctl enable gui/$(id -u)/com.fake.off" "$calls" || fail "item not enabled"

: > "$calls"
out=$(menu "4\n$(num com.fake.daemon)\nb\nq\n")
echo "$out" | grep -q "sudo launchctl disable system/com.fake.daemon" || fail "daemon command not shown: $out"
grep -q "launchctl disable" "$calls" && fail "changed a system item"
out=$(menu "4\n$(num 'com.fake.x;rm')\nb\nq\n")
echo "$out" | grep -q "unusual" || fail "odd label not refused: $out"
grep -q "launchctl disable" "$calls" && fail "acted on an odd label"
"$ms" startup disable com.fake.nope 2>/dev/null && fail "accepted unknown item"
"$ms" startup bogus 2>/dev/null && fail "accepted unknown startup action"
"$ms" startup disable com.fake.agent >/dev/null
grep -q "launchctl disable gui/$(id -u)/com.fake.agent" "$calls" || fail "direct disable failed"

# Maintenance
stub sudo
stub diskutil
stub tmutil 'echo "Snapshot dates for disk /:"; for d in ${SNAPS:-}; do echo "$d"; done'
ls="$MACSWEEP_ROOT/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support"
mkdir -p "$ls"; printf '#!/usr/bin/env bash\necho "lsregister $*" >> "$calls"\n' > "$ls/lsregister"; chmod +x "$ls/lsregister"

: > "$calls"
menu "5\n1\nn\n2\nn\n4\nn\n5\nn\n9\nb\nq\n" >/dev/null
[ ! -s "$calls" ] || fail "maintenance ran after declining: $(cat "$calls")"
menu "5\n1\ny\nb\nq\n" >/dev/null
grep -q "sudo dscacheutil -flushcache" "$calls" || fail "DNS not flushed"
grep -q "sudo killall -HUP mDNSResponder" "$calls" || fail "mDNSResponder not restarted"
menu "5\n2\ny\nb\nq\n" >/dev/null
grep -q "sudo mdutil -E /" "$calls" || fail "Spotlight not rebuilt"
menu "5\n4\ny\nb\nq\n" >/dev/null
grep -q "lsregister -r -f -apps local,system,user" "$calls" || fail "Open With not rebuilt"
menu "5\n5\ny\nb\nq\n" >/dev/null
grep -q "diskutil verifyVolume /" "$calls" || fail "disk not checked"

menu "5\n3\nb\nq\n" | grep -q "No local snapshots" || fail "empty snapshot list not reported"
export SNAPS=$'2026-11-01-055050\n2026-11-01-070958'
: > "$calls"
menu "5\n3\nn\nb\nq\n" | grep -q "2 local snapshots" || fail "snapshot count not shown"
grep -q deletelocalsnapshots "$calls" && fail "removed snapshots after declining"
menu "5\n3\ny\nb\nq\n" >/dev/null
[ "$(grep -c "sudo tmutil deletelocalsnapshots" "$calls")" = 2 ] || fail "snapshots not removed"
unset SNAPS
stub sudo 'exit 1'
menu "5\n1\ny\nb\nq\n" | grep -q "didn't work" || fail "failed task reported as done"

# Security check
stub spctl 'echo "assessments disabled"'
stub csrutil 'echo "System Integrity Protection status: enabled."'
stub fdesetup 'echo "FileVault is On."'
stub profiles 'echo "There are no configuration profiles installed for user x"'
fw="$MACSWEEP_ROOT/usr/libexec/ApplicationFirewall/socketfilterfw"
mkdir -p "$(dirname "$fw")"; printf '#!/usr/bin/env bash\necho "Firewall is disabled. (State = 0)"\n' > "$fw"; chmod +x "$fw"
app "$A" nosig com.fake.nosig 1000
agent "$MACSWEEP_ROOT/Library/LaunchDaemons" com.fake.baddaemon /no/such/program
agent "$UA" com.fake.real "$nosig"

out=$("$ms" security)
echo "$out" | grep -q "!   Gatekeeper is off" || fail "Gatekeeper off not flagged: $out"
echo "$out" | grep -q "ok  FileVault is on" || fail "FileVault on not shown: $out"
echo "$out" | grep -q "!   Firewall is off" || fail "disabled firewall read as on: $out"
echo "$out" | grep -q "ok  None installed" || fail "profiles not read: $out"
echo "$out" | grep "nosig.app" | grep -q "! not signed" || fail "unsigned app not flagged: $out"
echo "$out" | grep -q "Stuck.app" && fail "signed app flagged: $out"
echo "$out" | grep -q "com.fake.unsigned" || fail "flagged startup item missing: $out"
echo "$out" | grep -q "com.fake.agent" && fail "good startup item flagged: $out"
echo "$out" | grep -q "not a malware scan" || fail "no malware scan disclaimer"
echo "$out" | grep -qi "no malware\|clean bill\|you are safe" && fail "report claims safety: $out"

stub profiles 'echo "There are 2 user configuration profiles installed for x"'
"$ms" security | grep -q "!   Profiles are installed" || fail "profiles not flagged"
stub profiles 'exit 1'
"$ms" security | grep -q "?   Couldn" || fail "failed profile check read as fine"
stub spctl 'exit 1'
"$ms" security | grep -q "?   Gatekeeper" || fail "failed Gatekeeper check read as fine"

snum() { "$ms" security | awk -v l="$1" 'index($0, l) { print $1 + 0; exit }'; }
: > "$calls"
menu "6\n99\n0\nabc\nb\nq\n" >/dev/null
[ -f "$UA/com.fake.unsigned.plist" ] || fail "bad choice removed an item"
menu "6\n$(snum com.fake.unsigned)\nn\nb\nq\n" >/dev/null
[ -f "$UA/com.fake.unsigned.plist" ] || fail "removed an item after declining"
grep -q "launchctl disable" "$calls" && fail "changed an item after declining"
out=$(menu "6\n$(snum com.fake.real)\ny\nb\nq\n")
[ ! -e "$UA/com.fake.real.plist" ] || fail "item not moved to Trash: $out"
grep -q "launchctl disable gui/$(id -u)/com.fake.real" "$calls" || fail "item not turned off"
[ -f "$nosig" ] || fail "removed the program itself"
echo "$out" | grep -q "still at $nosig" || fail "program location not shown: $out"
out=$(menu "6\n$(snum com.fake.baddaemon)\nb\nq\n")
[ -f "$MACSWEEP_ROOT/Library/LaunchDaemons/com.fake.baddaemon.plist" ] || fail "touched a system-wide item"
echo "$out" | grep -q "sudo rm" || fail "no sudo command for system-wide item: $out"

# Browser cleanup. Only the fake process list here: a real open Chrome would block these tests.
stub ps 'echo "${PS_OUT:-}"'
AS="$HOME/Library/Application Support"
CH="$AS/Google/Chrome"; mkdir -p "$CH/Default"
sqlite3 "$CH/Default/Cookies" "CREATE TABLE cookies(host_key TEXT, name TEXT);
  INSERT INTO cookies VALUES ('.google.com','a'),('accounts.google.com','b'),('.bank.co.uk','c'),
  ('tracker.com','d'),('.evilgoogle.com','e'),('x''y.com','f');"
printf 'profile.info_cache.Default.name=Work\n' > "$CH/Local State"
mkdir -p "$AS/Microsoft Edge/Default"; sqlite3 "$AS/Microsoft Edge/Default/Cookies" "CREATE TABLE other(x TEXT); INSERT INTO other VALUES ('a');"
FF="$AS/Firefox/Profiles/abc.default-release"; mkdir -p "$FF"
sqlite3 "$FF/cookies.sqlite" "CREATE TABLE moz_cookies(host TEXT, name TEXT); INSERT INTO moz_cookies VALUES ('.news.com','a'),('.shop.com','b');"
ck() { sqlite3 "$CH/Default/Cookies" "SELECT count(*) FROM cookies"; }
pnum() { menu "7\nb\nq\n" | awk -v l="$1" 'index($0, l) { print $1 + 0; exit }'; }
snum() { menu "7\n$(pnum Work)\nb\nb\nq\n" | awk -v l=". $1 " 'index($0, l) { print $1 + 0; exit }'; }

out=$(menu "7\nb\nq\n")
echo "$out" | grep "Chrome" | grep "Work" | grep -q " 6 cookies" || fail "Chrome profile not listed: $out"
echo "$out" | grep "Firefox" | grep -q "default-release" || fail "Firefox profile not listed: $out"
echo "$out" | grep -q "Manage Website Data" || fail "no Safari pointer: $out"
out=$(menu "7\n$(pnum Work)\nb\nb\nq\n")
echo "$out" | grep "google.com" | grep -v evil | grep -q " 2 " || fail "subdomains not grouped: $out"
echo "$out" | grep -q "bank.co.uk" || fail "country domain grouped wrongly: $out"

out=$(PS_OUT="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" menu "7\n$(pnum Work)\nb\nb\nq\n")
echo "$out" | grep -q "Force quit Google Chrome" || fail "no force quit offer for browser: $out"
echo "$out" | grep -q "cookies by site" && fail "changed cookies while browser open: $out"
menu "7\n$(pnum Edge)\nb\nq\n" | grep -q "doesn't recognise" || fail "unknown format not refused"
[ "$(sqlite3 "$AS/Microsoft Edge/Default/Cookies" "SELECT count(*) FROM other")" = 1 ] || fail "touched unknown format"

menu "7\n$(pnum Work)\n99\nx\nk 99\nb\nb\nq\n" >/dev/null
[ "$(ck)" = 6 ] || fail "bad choice removed cookies"
menu "7\n$(pnum Work)\n$(snum tracker.com)\nn\nb\nb\nq\n" >/dev/null
[ "$(ck)" = 6 ] || fail "removed cookies after declining"
out=$(menu "7\n$(pnum Work)\n$(snum tracker.com)\ny\nb\nb\nq\n" 2>&1)
echo "$out" | grep -q "\\$ sqlite3 .*DELETE FROM cookies" || fail "cookie command not shown: $out"
echo "$out" | grep -q "signed out" || fail "no sign-out warning: $out"
echo "$out" | grep -q "Remove 1 cookie from 1 site:" || fail "wrong plural: $out"
[ "$(ck)" = 5 ] || fail "selected site not removed: $(ck)"

menu "7\n$(pnum Work)\nk $(snum google.com)\nb\nb\nq\n" >/dev/null
grep -qx "google.com" "$AS/macsweep/keep-sites" || fail "keep list not saved"
echo "nosuch.example" >> "$AS/macsweep/keep-sites"   # two lines: macOS awk once choked on this
menu "7\n$(pnum Work)\na\ny\nb\nb\nq\n" >/dev/null
[ "$(sqlite3 "$CH/Default/Cookies" "SELECT count(*) FROM cookies WHERE host_key LIKE '%google.com' AND host_key NOT LIKE '%evil%'")" = 2 ] || fail "kept site removed"
[ "$(sqlite3 "$CH/Default/Cookies" "SELECT count(*) FROM cookies WHERE host_key LIKE '%evil%' OR host_key LIKE '%bank%'")" = 0 ] || fail "all-except-kept missed sites"
[ "$(sqlite3 "$CH/Default/Cookies" "SELECT count(*) FROM cookies WHERE host_key = 'x''y.com'")" = 1 ] || fail "odd host name reached SQL"
menu "7\n$(pnum Work)\nu $(snum google.com)\nb\nb\nq\n" >/dev/null
grep -qx "google.com" "$AS/macsweep/keep-sites" && fail "site not removed from keep list"

menu "7\n$(pnum default-release)\n1\ny\nb\nb\nq\n" >/dev/null
[ "$(sqlite3 "$FF/cookies.sqlite" "SELECT count(*) FROM moz_cookies")" = 1 ] || fail "Firefox cookie not removed"

# Junk categories and cleanup tasks
mk "$HOME/Library/Developer/Xcode/iOS DeviceSupport/17.0/x"
B="$HOME/Library/Application Support/MobileSync/Backup"; mk "$B/abc/Info.plist"
"$ms" scan | grep -q "backups.*not in TOTAL" || fail "backups not shown apart in scan"
"$ms" clean --yes >/dev/null
[ -f "$B/abc/Info.plist" ] || fail "clean all deleted iPhone backups"
[ ! -e "$HOME/Library/Developer/Xcode/iOS DeviceSupport/17.0" ] || fail "device support not cleared"
menu "1\na\ny\nb\nq\n" >/dev/null
[ -f "$B/abc/Info.plist" ] || fail "menu all deleted iPhone backups"
out=$("$ms" clean backups --yes); echo "$out" | grep -q "only copy" || fail "no backup warning"
echo "$out" | grep -q "\$ find .*MobileSync" || fail "clean didn't show its command"
[ ! -e "$B/abc" ] || fail "backups not cleared when named"

app "$A" "Install macOS Test" com.apple.InstallAssistant.macOSTest 1000
"$ms" uninstall "Install macOS Test" --yes >/dev/null
[ ! -e "$A/Install macOS Test.app" ] || fail "macOS installer not removable"

stub sudo '"$@"'
stub brew '[ "$1" = cleanup ] && [ "${2:-}" = -n ] && echo "==> This operation would free approximately 9MB of disk space."; exit 0'
stub xcode-select 'echo "$MACSWEEP_ROOT/XcodeDev"'; mk "$MACSWEEP_ROOT/XcodeDev/usr/bin/simctl"; chmod +x "$MACSWEEP_ROOT/XcodeDev/usr/bin/simctl"
stub xcrun ''
stub docker ''
: > "$calls"
menu "5\n6\nn\n7\nn\n8\nn\nb\nq\n" | grep -q "free approximately 9MB" || fail "Homebrew estimate not shown"
grep -qE "brew cleanup$|simctl delete|docker system" "$calls" && fail "cleanup ran after declining"
menu "5\n6\ny\n7\ny\n8\ny\nb\nq\n" >/dev/null
grep -qx "brew cleanup" "$calls" || fail "brew cleanup not run"
grep -q "xcrun simctl delete unavailable" "$calls" || fail "simulators not cleaned"
grep -q "docker system prune -f" "$calls" || fail "docker not cleaned"
# With Xcode, clean asks it to delete the simulators it can't run. With none, they all go.
SIM="$HOME/Library/Developer/CoreSimulator/Devices"; mk "$SIM/ABC/data"
: > "$calls"
"$ms" clean xcode --dry-run | grep -q "simctl delete unavailable" || fail "simulator cleanup not previewed"
grep -q "simctl delete" "$calls" && fail "dry run deleted simulators"
"$ms" clean xcode --yes >/dev/null
grep -q "xcrun simctl delete unavailable" "$calls" && [ -f "$SIM/ABC/data" ] || fail "clean xcode should leave simulators to Xcode"
stub xcode-select 'exit 2'
"$ms" clean xcode --yes >/dev/null
[ ! -e "$SIM/ABC" ] && [ -d "$SIM" ] || fail "simulators kept though no Xcode is installed"
mk "$SIM/ABC/data"; app "$A" Xcode-beta com.apple.dt.Xcode 10
"$ms" clean xcode --yes >/dev/null; [ -f "$SIM/ABC/data" ] || fail "simulators cleared though an Xcode is installed"
rm -rf "$A/Xcode-beta.app" "$SIM"
: > "$calls"
menu "5\n7\nb\nq\n" | grep -q "Xcode isn't installed" || fail "missing Xcode not reported"
grep -q xcrun "$calls" && fail "ran xcrun without Xcode"

# Performance check
stub sysctl 'case "$2" in
  kern.memorystatus_vm_pressure_level) echo 2 ;;
  vm.swapusage) echo "total = 4096.00M  used = 2048.50M  free = 2047.50M  (encrypted)" ;;
  kern.boottime) echo "{ sec = $(( $(date +%s) - 20 * 86400 )), usec = 0 } Mon Nov  2 08:13:22 2026" ;;
esac'
stub pmset 'echo "CPU_Speed_Limit = 70"'
export PS_OUT=" 50.0 /Applications/Foo Bar.app/Contents/MacOS/Foo Bar
 30.0 /Applications/Foo Bar.app/Contents/Frameworks/Helper (Renderer).app/Contents/MacOS/Helper (Renderer)
 10.0 /usr/sbin/bard"
out=$("$ms" performance)
echo "$out" | grep -q "80.0%  Foo Bar" || fail "helpers not grouped under their app: $out"
echo "$out" | grep -q "Helper" && fail "helper listed on its own: $out"
echo "$out" | grep -q "10.0%  bard" || fail "plain process missing: $out"
echo "$out" | grep -q "!   Memory pressure is high" || fail "pressure not flagged: $out"
echo "$out" | grep -q "!   Using 2.0G of swap" || fail "swap not flagged: $out"
echo "$out" | grep -q "!   Running hot" || fail "heat not flagged: $out"
echo "$out" | grep -q "20 days ago" || fail "uptime not shown: $out"
echo "$out" | grep -q "disk free\|free. macOS" || fail "disk not shown: $out"
stub sysctl 'exit 1'; stub pmset 'exit 1'
out=$("$ms" performance)
echo "$out" | grep -q "?   Couldn't read memory pressure" || fail "unreadable pressure shown as fine: $out"
echo "$out" | grep -q "?   Couldn't read the temperature" || fail "unreadable heat shown as fine: $out"
menu "8\n\nq\n" | grep -q "Using the most memory" || fail "menu performance missing"
unset PS_OUT

# Tweaks
store="$root/defaults"; : > "$store"; export store
stub defaults 'case "$1" in
  read) v=$(grep -F "$2 $3=" "$store" | tail -n 1 | cut -d= -f2-); [ -n "$v" ] || exit 1
        case "$v" in true) v=1 ;; false) v=0 ;; esac; echo "$v" ;;
  write) grep -vF "$2 $3=" "$store" > "$store.new"; mv "$store.new" "$store"; echo "$2 $3=$5" >> "$store" ;;
  delete) grep -qF "$2 $3=" "$store" || exit 1; grep -vF "$2 $3=" "$store" > "$store.new"; mv "$store.new" "$store" ;;
esac'
stub killall ''
stub sysctl '[ "$1" = -n ] && echo "${THROTTLE:-1}"; exit 0'
tnum() { menu "9\nb\nq\n" | awk -v l="$1" 'index($0, l) { print $1 + 0; exit }'; }
echo "com.apple.finder ShowPathbar=true" >> "$store"
out=$(menu "9\nb\nq\n")
echo "$out" | grep "path bar" | grep -q " on " || fail "existing setting not shown as on: $out"
echo "$out" | grep "hidden files" | grep -q " off " || fail "unset tweak not shown as off: $out"
echo "$out" | grep -q "Gatekeeper" || fail "security note missing"
: > "$calls"
menu "9\n$(tnum "hidden files")\nn\nb\nq\n" >/dev/null
grep -q "defaults write" "$calls" && fail "changed a setting after declining"
out=$(menu "9\n$(tnum "hidden files")\ny\nb\nq\n")
grep -q "defaults write com.apple.finder AppleShowAllFiles -bool true" "$calls" || fail "tweak not written"
echo "$out" | grep -q "  \\$ defaults write com.apple.finder AppleShowAllFiles -bool true" || fail "tweak command not shown: $out"
grep -q "killall Finder" "$calls" || fail "Finder not restarted"
menu "9\n$(tnum "Dock appears")\ny\nb\nq\n" >/dev/null
grep -q "defaults write com.apple.dock autohide-delay -float 0" "$calls" || fail "float tweak not written"
menu "9\n$(tnum "Dock appears")\nb\nq\n" | grep "Dock appears" | grep -q " on " || fail "float tweak not read back as on"
menu "9\n$(tnum "hidden files")\ny\nb\nq\n" >/dev/null
grep -q "defaults delete com.apple.finder AppleShowAllFiles" "$calls" || fail "default not restored"
grep -qF "AppleShowAllFiles=" "$store" && fail "tweak still set after restoring"
menu "9\n99\nx\n0\nb\nq\n" | grep -q "Not a valid choice" || fail "bad tweak choice not rejected"
menu "9\n$(tnum "Time Machine")\ny\nb\nq\n" >/dev/null
grep -q "sudo sysctl debug.lowpri_throttle_enabled=0" "$calls" || fail "Time Machine not sped up"
THROTTLE=0 menu "9\n$(tnum "Time Machine")\ny\nb\nq\n" >/dev/null
grep -q "sudo sysctl debug.lowpri_throttle_enabled=1" "$calls" || fail "Time Machine not put back"

# Duplicate files and battery
D="$HOME/Dupes"; mkdir -p "$D/Pics.photoslibrary" "$L/Caches"
head -c 1500000 /dev/zero > "$D/a.bin"; cp "$D/a.bin" "$D/b copy.bin"; ln "$D/a.bin" "$D/hardlink.bin"
{ printf x; head -c 1499999 /dev/zero; } > "$D/same-size-different.bin"
cp "$D/a.bin" "$D/Pics.photoslibrary/inside.bin"; cp "$D/a.bin" "$L/Caches/lib-copy.bin"
out=$("$ms" dupes "$D" --min 1)
echo "$out" | grep -q "2 copies of" || fail "duplicates not grouped: $out"
echo "$out" | grep -q "b copy.bin" || fail "copy missing: $out"
echo "$out" | grep -q "hardlink.bin" && fail "hard link counted as a copy: $out"
echo "$out" | grep -q "different" && fail "different contents matched: $out"
echo "$out" | grep -q "photoslibrary" && fail "looked inside a library: $out"
"$ms" dupes --min 1 | grep -q "lib-copy" && fail "looked inside ~/Library"
"$ms" dupes "$D" --min x 2>/dev/null && fail "accepted bad --min"
stub cksum 'echo "1 0"'   # every file "collides", so only the byte check can tell them apart
"$ms" dupes "$D" --min 1 | grep -q "different" && fail "trusted a checksum match without comparing bytes"
rm "$root/bin/cksum"
menu "2\n2\n$D\n1\n1\n1\nn\nb\nb\nq\n" >/dev/null
[ -f "$D/b copy.bin" ] || fail "removed a copy after declining"
out=$(menu "2\n2\n$D\n1\n1\n2\ny\nb\nb\nq\n")
[ ! -e "$D/a.bin" ] && [ -f "$D/b copy.bin" ] || fail "kept the wrong copy: $out"
[ -f "$D/hardlink.bin" ] || fail "removed the hard link"
echo "$out" | grep -q "Moved 1 to the Trash" || fail "no result: $out"
echo "$out" | grep -q "No duplicate files" || fail "group not cleared after cleanup: $out"

stub sysctl 'exit 1'; stub pmset 'exit 1'
stub system_profiler 'printf "Power:\n    Battery Information:\n          Cycle Count: 900\n          Condition: Service Recommended\n          Maximum Capacity: 72%%\n"'
"$ms" performance | grep -q "!   Battery: Service Recommended, 72%" || fail "worn battery not flagged"
stub system_profiler 'printf "Power:\n    Battery Information:\n          Cycle Count: 53\n          Condition: Normal\n          Maximum Capacity: 95%%\n"'
"$ms" performance | grep -q "ok  Battery is normal: 95%" || fail "good battery not shown"
stub system_profiler 'printf "Power:\n    AC Charger Information:\n"'
"$ms" performance | grep -q "Battery" && fail "battery shown on a Mac without one"

echo "all tests passed"
