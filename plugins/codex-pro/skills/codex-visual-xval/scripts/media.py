#!/usr/bin/env python3
"""Image copies for /codex-pro:codex-visual-xval (#23): upright, and without embedded metadata.

The copies are what both models see, so they must carry nothing the neutral file names were
meant to hide. Re-encoding with sips was measured (2026-10-07) to keep the EXIF block and the
capture time, so metadata is removed here at the byte level, segment by segment:

  JPEG  APP1-APP15 except ICC colour profiles (APP2 "ICC_PROFILE") and Adobe (APP14), and comments
  PNG   eXIf, tEXt, iTXt, zTXt, tIME
  WebP  EXIF and XMP chunks, and the VP8X flags that announce them
  GIF   converted to PNG first, then treated as PNG

A JPEG's EXIF orientation is read before the block is removed and applied to the pixels with
sips, so both models see the image the right way up and in the same coordinates.
"""
import os
import re
import struct
import subprocess

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
PNG_DROP = {b"eXIf", b"tEXt", b"iTXt", b"zTXt", b"tIME"}
WEBP_DROP = {b"EXIF", b"XMP "}
JPEG_KEEP_APP = {0xE0, 0xEE}   # JFIF, Adobe; APP2 is kept only when it is an ICC profile

# EXIF orientation -> sips operations, in order (sips rotates clockwise).
ORIENTATION_STEPS = {
    2: [["-f", "horizontal"]], 3: [["-r", "180"]], 4: [["-f", "vertical"]],
    5: [["-r", "90"], ["-f", "horizontal"]], 6: [["-r", "90"]],
    7: [["-r", "270"], ["-f", "horizontal"]], 8: [["-r", "270"]],
}


class MediaError(Exception):
    pass


def image_size(path: str) -> tuple[int | None, int | None]:
    try:
        out = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", path],
                             capture_output=True, text=True, check=True).stdout
        return int(re.search(r"pixelWidth: (\d+)", out).group(1)), int(re.search(r"pixelHeight: (\d+)", out).group(1))
    except (OSError, subprocess.CalledProcessError, AttributeError):
        return None, None


def _jpeg_segments(data: bytes):
    """(marker, segment bytes including the marker) up to and including SOS; then the rest."""
    if data[:2] != b"\xff\xd8":
        raise MediaError("not a JPEG file")
    pos, out = 2, []
    while pos + 4 <= len(data):
        if data[pos] != 0xFF:
            raise MediaError("malformed JPEG segment")
        marker = data[pos + 1]
        if marker == 0xD8 or 0xD0 <= marker <= 0xD7:
            out.append((marker, data[pos:pos + 2])); pos += 2; continue
        length = struct.unpack(">H", data[pos + 2:pos + 4])[0]
        out.append((marker, data[pos:pos + 2 + length]))
        pos += 2 + length
        if marker == 0xDA:   # start of scan: the rest is image data
            return out, data[pos:]
    raise MediaError("JPEG without image data")


def jpeg_orientation(data: bytes) -> int:
    for marker, seg in _jpeg_segments(data)[0]:
        if marker == 0xE1 and seg[4:10] == b"Exif\x00\x00":
            tiff = seg[10:]
            endian = ">" if tiff[:2] == b"MM" else "<"
            ifd = struct.unpack(endian + "I", tiff[4:8])[0]
            for i in range(struct.unpack(endian + "H", tiff[ifd:ifd + 2])[0]):
                entry = tiff[ifd + 2 + 12 * i: ifd + 14 + 12 * i]
                if struct.unpack(endian + "H", entry[:2])[0] == 0x0112:
                    return struct.unpack(endian + "H", entry[8:10])[0]
    return 1


def strip_jpeg(data: bytes) -> bytes:
    segments, rest = _jpeg_segments(data)
    kept = [seg for marker, seg in segments
            if not ((0xE1 <= marker <= 0xEF and marker not in JPEG_KEEP_APP
                     and not (marker == 0xE2 and seg[4:16] == b"ICC_PROFILE\x00"))
                    or marker == 0xFE)]
    return b"\xff\xd8" + b"".join(seg for seg in kept if seg != b"\xff\xd8") + rest


def strip_png(data: bytes) -> bytes:
    if data[:8] != PNG_SIGNATURE:
        raise MediaError("not a PNG file")
    pos, out = 8, [PNG_SIGNATURE]
    while pos + 8 <= len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        kind = data[pos + 4:pos + 8]
        chunk = data[pos:pos + 12 + length]
        if kind not in PNG_DROP:
            out.append(chunk)
        pos += 12 + length
        if kind == b"IEND":
            break
    return b"".join(out)


def strip_webp(data: bytes) -> bytes:
    if data[:4] != b"RIFF" or data[8:12] != b"WEBP":
        raise MediaError("not a WebP file")
    pos, chunks = 12, []
    while pos + 8 <= len(data):
        kind, size = data[pos:pos + 4], struct.unpack("<I", data[pos + 4:pos + 8])[0]
        body = data[pos + 8:pos + 8 + size]
        if kind == b"VP8X" and body:
            body = bytes([body[0] & ~0x0C]) + body[1:]   # clear the EXIF (0x08) and XMP (0x04) flags
        if kind not in WEBP_DROP:
            chunks.append(kind + struct.pack("<I", size) + body + (b"\x00" if size % 2 else b""))
        pos += 8 + size + (size % 2)
    payload = b"WEBP" + b"".join(chunks)
    return b"RIFF" + struct.pack("<I", len(payload)) + payload


def prepare_copy(src: str, frames_dir: str, stem: str) -> str:
    """Write the run's copy of one image; returns its file name inside frames_dir."""
    ext = os.path.splitext(src)[1].lower() or ".png"
    if ext == ".gif":
        name = f"{stem}.png"
        subprocess.run(["sips", "-s", "format", "png", src, "--out", os.path.join(frames_dir, name)],
                       capture_output=True, check=True)
        src, ext = os.path.join(frames_dir, name), ".png"
    strip = {".jpg": strip_jpeg, ".jpeg": strip_jpeg, ".png": strip_png, ".webp": strip_webp}.get(ext)
    if strip is None:
        raise MediaError(f"unsupported image type {ext}: use PNG, JPEG, WebP or GIF")
    name = f"{stem}{'.jpg' if ext == '.jpeg' else ext}"
    target = os.path.join(frames_dir, name)
    with open(src, "rb") as fh:
        data = fh.read()
    with open(target, "wb") as fh:
        fh.write(data)
    # Turn upright first, strip last: sips writes an EXIF block of its own when it saves
    # (measured 2026-10-07), so anything stripped before a sips step comes back.
    orientation = jpeg_orientation(data) if strip is strip_jpeg else 1
    for step in ORIENTATION_STEPS.get(orientation, []):
        subprocess.run(["sips", *step, target, "--out", target], capture_output=True, check=True)
    with open(target, "rb") as fh:
        cleaned = strip(fh.read())
    with open(target, "wb") as fh:
        fh.write(cleaned)
    return name
