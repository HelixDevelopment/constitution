#!/usr/bin/env bash
# usage: locprobe.sh STRING  (run under the locale to measure); prints which regex forms match STRING
s="$1"; o=""
[[ $s =~ ^[0-9]$ ]] && o+="r1" || o+="r0"
[[ $s =~ ^[[:digit:]]$ ]] && o+=" d1" || o+=" d0"
[[ $s =~ ^[A-Z]$ ]] && o+=" A1" || o+=" A0"
[[ $s =~ ^[[:upper:]]$ ]] && o+=" U1" || o+=" U0"
echo "$o"
