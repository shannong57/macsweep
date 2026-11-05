#!/usr/bin/env bash
# Runs macsweep against a throwaway fake $HOME. Usage: ./test.sh
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

echo "all tests passed"
