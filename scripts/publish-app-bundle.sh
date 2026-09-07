#!/usr/bin/env bash
set -euo pipefail
# Caller owns the publication lock and validates staging before this boundary.
# Both directories are on the destination filesystem. On replacement, the old
# bundle moves into staging and is removed by the caller's cleanup trap.
python3 - "$1" "$2" <<'PY'
import ctypes
import os
import sys

source, destination = sys.argv[1:]
if not os.path.lexists(destination):
    os.rename(source, destination)
else:
    libc = ctypes.CDLL(None, use_errno=True)
    swap = libc.renameatx_np
    swap.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
    swap.restype = ctypes.c_int
    if swap(-2, os.fsencode(source), -2, os.fsencode(destination), 2) != 0:
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error))
PY
