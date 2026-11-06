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
menu "1\n   \nb\nq\n" >/dev/null; kept "blank selection cleaned something"
menu "1\n9\n0\nx\n1 9\nb\nq\n" >/dev/null; kept "bad selection cleaned something"
menu "1\n1\nn\nb\nq\n" >/dev/null; kept "declining cleaned something"
menu "1\n1\n" >/dev/null; kept "end of input cleaned something"
menu "7\nq\n" | grep -q "Not a valid choice" || fail "bad main choice not rejected"

menu "1\n1\ny\nb\nq\n" >/dev/null
[ ! -e "$HOME/Library/Caches/a" ] || fail "menu did not clean caches"
[ -f "$HOME/Library/Logs/b" ] || fail "menu cleaned logs when only caches picked"
menu "1\na\ny\nq\n" >/dev/null
[ ! -e "$HOME/Library/Logs/b" ] || fail "menu all did not clean logs"
[ -f "$HOME/Documents/keep.txt" ] || fail "menu deleted Documents"

menu "2\n\n1\n\nq\n" | grep -q "big.bin" || fail "menu large files missed big.bin"
menu "2\n~\n1\n\nq\n" | grep -q "big.bin" || fail "menu large files did not expand ~"
menu "2\n/no/such/dir\nq\n" | grep -q "Not a folder" || fail "bad folder not rejected"
menu "2\n\nabc\nq\n" | grep -q "whole number" || fail "bad size not rejected"
"$ms" </dev/null | grep -q TOTAL || fail "no terminal should still scan"

# Everything below runs against stubs: no real app, Trash or system setting is touched.
export MACSWEEP_ROOT="$root/sys"
calls="$root/calls"; : > "$calls"; export calls
mkdir -p "$root/bin" "$root/trashed" "$MACSWEEP_ROOT/usr/bin"; export trashed="$root/trashed"
stub() { printf '#!/usr/bin/env bash\necho "%s $*" >> "$calls"\n%s\n' "$1" "${2:-}" > "$root/bin/$1"; chmod +x "$root/bin/$1"; }
stub plutil 'f="${@: -1}"; v=$(sed -n "s/^$2=//p" "$f" 2>/dev/null); [ -n "$v" ] && printf "%s\n" "$v"'
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

out=$(menu "3\n1\nb\nb\nq\n")
echo "$out" | grep -q "Fake App" || fail "uninstall list missing app: $out"
echo "$out" | grep -q "Thing" && fail "uninstall list shows Apple app"
"$ms" uninstall Thing --yes 2>/dev/null && fail "uninstalled an Apple app"
[ -d "$A/Thing.app" ] || fail "Apple app removed"
"$ms" uninstall "Fake App" </dev/null &>/dev/null && fail "uninstalled without a tty or --yes"
"$ms" uninstall Nope --yes 2>/dev/null && fail "accepted unknown app"
menu "3\n1\n99\n0\nabc\nb\nb\nq\n" >/dev/null
menu "3\n1\n1\nn\nb\nb\nq\n" >/dev/null
[ -d "$A/Fake App.app" ] || fail "uninstalled after declining"
PS_OUT="/x $A/Fake App.app/Contents/MacOS/Fake" "$ms" uninstall "fake app" --yes | grep -q "is running" || fail "running app not refused"
[ -d "$A/Fake App.app" ] || fail "removed a running app"

"$ms" uninstall Evil --yes >/dev/null
[ ! -e "$HOME/Applications/Evil.app" ] || fail "evil app not removed"
[ -f "$HOME/Documents/keep.txt" ] && [ -d "$L/Caches" ] || fail "app ID climbed out of Library"

out=$("$ms" uninstall Stuck --yes || true); echo "$out" | grep -q "Couldn't move" || fail "trash failure hidden: $out"
[ -d "$L/Caches/com.fake.stuck" ] || fail "removed leftovers when the app could not be moved"

out=$(menu "3\n1\n1\ny\nb\nb\nq\n")
[ ! -e "$A/Fake App.app" ] || fail "menu did not uninstall"
for p in "Application Support/Fake App" "Application Support/com.fake.app" Caches/com.fake.app \
         Preferences/com.fake.app.plist Containers/com.fake.app "Saved Application State/com.fake.app.savedState"; do
  [ ! -e "$L/$p" ] || fail "leftover kept: $p"
done
[ -f "$L/Caches/com.fake.app2/keep" ] || fail "took another app's files"
[ -f "$MACSWEEP_ROOT/Library/LaunchDaemons/com.fake.app.plist" ] || fail "touched a system file"
echo "$out" | grep -q "sudo rm -rf" || fail "system leftover not listed"
echo "$out" | grep -q "Moved" || fail "no result message"

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
[ -d "$A/Thing.app" ] || fail "other Apple app removed"

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
rm "$MACSWEEP_ROOT/Library/LaunchDaemons/com.fake.app.plist"
agent "$MACSWEEP_ROOT/Library/LaunchDaemons" com.fake.daemon "$good"

out=$(menu "4\nb\nq\n")
echo "$out" | grep "com.fake.agent" | grep -q "Fake Inc." || fail "signer not shown: $out"
echo "$out" | grep "com.fake.off" | grep -q "off" || fail "disabled state not shown: $out"
echo "$out" | grep "com.fake.unsigned" | grep -q "! not signed" || fail "unsigned not flagged: $out"
echo "$out" | grep "com.fake.zgone" | grep -q "! program missing" || fail "missing not flagged: $out"
echo "$out" | grep -q "Login Items" || fail "login items pointer missing: $out"

num() { "$ms" startup | awk -v l="$1" 'index($0, l) { print $1; exit }'; }
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

echo "all tests passed"
