#!/usr/bin/env python3
import ctypes, sys

try:
    lib = ctypes.CDLL("/lib/x86_64-linux-gnu/libdiscid.so.0")
except OSError as e:
    print(f"ERROR: could not load libdiscid: {e}", file=sys.stderr)
    sys.exit(1)

lib.discid_new.restype = ctypes.c_void_p
lib.discid_read.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
lib.discid_read.restype = ctypes.c_int
lib.discid_get_id.argtypes = [ctypes.c_void_p]
lib.discid_get_id.restype = ctypes.c_char_p
lib.discid_free.argtypes = [ctypes.c_void_p]

device = sys.argv[1] if len(sys.argv) > 1 else b"/dev/cdrom"
if isinstance(device, str):
    device = device.encode()

disc = lib.discid_new()
try:
    if lib.discid_read(disc, device) == 0:
        print("ERROR: could not read disc", file=sys.stderr)
        sys.exit(1)
    print(lib.discid_get_id(disc).decode())
finally:
    lib.discid_free(disc)
