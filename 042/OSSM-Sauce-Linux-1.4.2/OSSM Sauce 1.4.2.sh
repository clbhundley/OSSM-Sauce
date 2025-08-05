#!/bin/sh
echo -ne '\033c\033]0;OSSM Sauce\a'
base_path="$(dirname "$(realpath "$0")")"
"$base_path/OSSM Sauce 1.4.2.x86_64" "$@"
