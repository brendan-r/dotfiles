#!/bin/bash
if [[ $- == *i* ]] && [ -t 1 ] && [ "${TERM:-dumb}" != dumb ] && command -v clear >/dev/null 2>&1; then
    clear
fi
