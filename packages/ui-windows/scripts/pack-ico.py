"""Packs PNG frames into one .ico: pack-ico.py out.ico frame.png..."""
import struct
import sys

out, frames = sys.argv[1], sys.argv[2:]
images = []
for path in frames:
    data = open(path, "rb").read()
    width, height = struct.unpack(">II", data[16:24])
    images.append((width, height, data))
images.sort(key=lambda image: image[0])
header = struct.pack("<HHH", 0, 1, len(images))
offset = 6 + 16 * len(images)
entries, blobs = b"", b""
for width, height, data in images:
    entries += struct.pack("<BBBBHHII", width % 256, height % 256, 0, 0, 1, 32, len(data), offset)
    offset += len(data)
    blobs += data
open(out, "wb").write(header + entries + blobs)
