#!/usr/bin/env bash

MOD_SPELLREGULATOR_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/" && pwd )"

source "$MOD_SPELLREGULATOR_ROOT/conf/conf.sh.dist"

if [ -f "$MOD_SPELLREGULATOR_ROOT/conf/conf.sh" ]; then
    source "$MOD_SPELLREGULATOR_ROOT/conf/conf.sh"
fi 