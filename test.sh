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
menu "9\nq\n" | grep -q "Not a valid choice" || fail "bad main choice not rejected"

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

snum() { "$ms" security | awk -v l="$1" 'index($0, l) { print $1; exit }'; }
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
pnum() { menu "7\nb\nq\n" | awk -v l="$1" 'index($0, l) { print $1; exit }'; }
snum() { menu "7\n$(pnum Work)\nb\nb\nq\n" | awk -v l="  $1 " 'index($0, l) { print $1; exit }'; }

out=$(menu "7\nb\nq\n")
echo "$out" | grep "Chrome" | grep "Work" | grep -q " 6 cookies" || fail "Chrome profile not listed: $out"
echo "$out" | grep "Firefox" | grep -q "default-release" || fail "Firefox profile not listed: $out"
echo "$out" | grep -q "Manage Website Data" || fail "no Safari pointer: $out"
out=$(menu "7\n$(pnum Work)\nb\nb\nq\n")
echo "$out" | grep "google.com" | grep -v evil | grep -q " 2 " || fail "subdomains not grouped: $out"
echo "$out" | grep -q "bank.co.uk" || fail "country domain grouped wrongly: $out"

out=$(PS_OUT="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" menu "7\n$(pnum Work)\nb\nb\nq\n")
echo "$out" | grep -q "Quit Google Chrome first" || fail "changed cookies while browser open: $out"
menu "7\n$(pnum Edge)\nb\nq\n" | grep -q "doesn't recognise" || fail "unknown format not refused"
[ "$(sqlite3 "$AS/Microsoft Edge/Default/Cookies" "SELECT count(*) FROM other")" = 1 ] || fail "touched unknown format"

menu "7\n$(pnum Work)\n99\nx\nk 99\nb\nb\nq\n" >/dev/null
[ "$(ck)" = 6 ] || fail "bad choice removed cookies"
menu "7\n$(pnum Work)\n$(snum tracker.com)\nn\nb\nb\nq\n" >/dev/null
[ "$(ck)" = 6 ] || fail "removed cookies after declining"
out=$(menu "7\n$(pnum Work)\n$(snum tracker.com)\ny\nb\nb\nq\n")
echo "$out" | grep -q "signed out" || fail "no sign-out warning: $out"
[ "$(ck)" = 5 ] || fail "selected site not removed: $(ck)"

menu "7\n$(pnum Work)\nk $(snum google.com)\nb\nb\nq\n" >/dev/null
grep -qx "google.com" "$AS/macsweep/keep-sites" || fail "keep list not saved"
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
"$ms" clean backups --yes | grep -q "only copy" || fail "no backup warning"
[ ! -e "$B/abc" ] || fail "backups not cleared when named"

app "$A" "Install macOS Test" com.apple.InstallAssistant.macOSTest 1000
"$ms" uninstall "Install macOS Test" --yes >/dev/null
[ ! -e "$A/Install macOS Test.app" ] || fail "macOS installer not removable"

stub sudo '"$@"'
stub brew '[ "$1" = cleanup ] && [ "${2:-}" = -n ] && echo "==> This operation would free approximately 9MB of disk space."; exit 0'
stub xcode-select 'echo /Applications/Xcode.app/Contents/Developer'
stub xcrun ''
stub docker ''
: > "$calls"
menu "5\n6\nn\n7\nn\n8\nn\nb\nq\n" | grep -q "free approximately 9MB" || fail "Homebrew estimate not shown"
grep -qE "brew cleanup$|simctl delete|docker system" "$calls" && fail "cleanup ran after declining"
menu "5\n6\ny\n7\ny\n8\ny\nb\nq\n" >/dev/null
grep -qx "brew cleanup" "$calls" || fail "brew cleanup not run"
grep -q "xcrun simctl delete unavailable" "$calls" || fail "simulators not cleaned"
grep -q "docker system prune -f" "$calls" || fail "docker not cleaned"
stub xcode-select 'exit 2'
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

echo "all tests passed"
