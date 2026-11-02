#!/bin/sh
# Each argument is one required group; names in a group are alternatives.
if command -v apk >/dev/null 2>&1; then
    pm=apk
elif command -v opkg >/dev/null 2>&1; then
    pm=opkg
else
    echo 'No supported package manager (apk/opkg) found.' >&2
    exit 127
fi
[ "$#" -gt 0 ] || exit 2
for group in "$@"; do
    [ -n "$group" ] || exit 2
    for package in $group; do
        case "$package" in *[!a-zA-Z0-9_.+-]*) echo 'Invalid package name.' >&2; exit 2;; esac
    done
done
installed() {
    if [ "$pm" = apk ]; then apk info -e "$1" >/dev/null 2>&1
    else opkg status "$1" 2>/dev/null | grep -q '^Status:.* installed'; fi
}
available() {
    if [ "$pm" = apk ]; then apk search -x "$1" 2>/dev/null | grep -q .
    else opkg list "$1" 2>/dev/null | awk -v p="$1" '$1 == p {found=1} END {exit !found}'; fi
}
# Do not refresh feeds or change anything when all requirements are installed.
missing=0
for group in "$@"; do
    found=0
    for package in $group; do installed "$package" && { found=1; break; }; done
    [ "$found" = 1 ] || missing=1
done
[ "$missing" = 1 ] || { echo 'All required packages are already installed.'; exit 0; }
"$pm" update || exit $?
selected=''
for group in "$@"; do
    found=''
    for package in $group; do installed "$package" && { found="$package"; break; }; done
    [ -n "$found" ] && continue
    for package in $group; do available "$package" && { found="$package"; break; }; done
    if [ -z "$found" ]; then
        echo "No package from [$group] is available in the configured $pm feeds. Check firmware/architecture and feed configuration." >&2
        exit 4
    fi
    selected="$selected $found"
done
if [ -n "$selected" ]; then
    if [ "$pm" = apk ]; then apk add $selected || exit $?
    else opkg install $selected || exit $?; fi
fi
for group in "$@"; do
    found=0
    for package in $group; do installed "$package" && { found=1; break; }; done
    if [ "$found" != 1 ]; then echo "Package installation could not be verified: $group" >&2; exit 5; fi
done
echo 'Required packages installed and verified.'
