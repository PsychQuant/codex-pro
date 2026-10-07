#!/usr/bin/env python3
"""Image copies for /codex-pro:codex-visual-xval (#23): upright, and without embedded metadata.

The copies are what both models see, so they must carry nothing the neutral file names were
meant to hide. Re-encoding with sips was measured (2026-10-07) to keep the EXIF block and the
capture time, so metadata is removed here at the byte level. Only the blocks a decoder needs to
show the image are kept (an allowlist: a list of what to drop missed C2PA content credentials,
which can hold EXIF and GPS, #23 verify round 3, L14), and each copy ends where its format says
the image ends, because a second image or a motion-photo video appended there carries its own
EXIF and GPS (round 2, R7; round 3, T2):

  JPEG  frame, Huffman, quantisation, restart and scan segments, JFIF APP0 without its thumbnail,
        ICC colour profiles (APP2 "ICC_PROFILE") and Adobe's APP14 (by its signature), also between
        progressive scans; the copy ends at the end-of-image marker, which may follow any number of
        0xFF fill bytes, and a JPEG without one is refused, since its end cannot be found
  PNG   the chunks in PNG_KEEP; the copy ends at IEND
  WebP  the chunks in WEBP_KEEP, without the VP8X flags for EXIF and XMP, and inside each animation
        frame (ANMF) only its image chunks; the copy ends at the length given in the RIFF header
  GIF   converted to PNG first, then treated as PNG

The format is read from the file header, not the extension. An EXIF orientation (JPEG APP1, PNG
eXIf, WebP EXIF) is read before the metadata is removed and applied to the pixels with sips, so
both models see the image the right way up and in the same coordinates.
"""
import os
import re
import struct
import subprocess

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
PNG_KEEP = {b"IHDR", b"PLTE", b"IDAT", b"IEND", b"tRNS", b"cHRM", b"gAMA", b"iCCP", b"sBIT", b"sRGB",
            b"cICP", b"mDCV", b"cLLI", b"pHYs", b"bKGD", b"acTL", b"fcTL", b"fdAT"}
WEBP_KEEP = {b"VP8 ", b"VP8L", b"VP8X", b"ALPH", b"ANIM", b"ANMF", b"ICCP"}
# SOF0-15 (C8 is reserved), DHT, DAC, DQT, DNL, DRI, SOS
JPEG_KEEP = {m for m in range(0xC0, 0xD0) if m != 0xC8} | {0xDA, 0xDB, 0xDC, 0xDD}

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
        while pos + 2 < len(data) and data[pos + 1] == 0xFF:   # fill bytes before a marker
            pos += 1
        marker = data[pos + 1]
        if marker == 0xD8 or 0xD0 <= marker <= 0xD7:
            out.append((marker, data[pos:pos + 2])); pos += 2; continue
        length = struct.unpack(">H", data[pos + 2:pos + 4])[0]
        out.append((marker, data[pos:pos + 2 + length]))
        pos += 2 + length
        if marker == 0xDA:   # start of scan: the rest is image data
            return out, data[pos:]
    raise MediaError("JPEG without image data")


def kind_of(data: bytes) -> str:
    """The image format from its header (#23 verify round 2, S14)."""
    if data[:3] == b"\xff\xd8\xff":
        return "jpeg"
    if data[:8] == PNG_SIGNATURE:
        return "png"
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "webp"
    if data[:6] in (b"GIF87a", b"GIF89a"):
        return "gif"
    raise MediaError("not a PNG, JPEG, WebP or GIF file (judged by its header)")


def tiff_orientation(tiff: bytes) -> int:
    if tiff[:6] == b"Exif\x00\x00":
        tiff = tiff[6:]
    try:
        endian = ">" if tiff[:2] == b"MM" else "<"
        ifd = struct.unpack(endian + "I", tiff[4:8])[0]
        for i in range(struct.unpack(endian + "H", tiff[ifd:ifd + 2])[0]):
            entry = tiff[ifd + 2 + 12 * i: ifd + 14 + 12 * i]
            if struct.unpack(endian + "H", entry[:2])[0] == 0x0112:
                return struct.unpack(endian + "H", entry[8:10])[0]
    except struct.error:
        pass
    return 1


def orientation(data: bytes) -> int:
    kind = kind_of(data)
    if kind == "jpeg":
        for marker, seg in _jpeg_segments(data)[0]:
            if marker == 0xE1 and seg[4:10] == b"Exif\x00\x00":
                return tiff_orientation(seg[10:])
    elif kind == "png":
        pos = 8
        while pos + 8 <= len(data):
            length, chunk = struct.unpack(">I", data[pos:pos + 4])[0], data[pos + 4:pos + 8]
            if chunk == b"eXIf":
                return tiff_orientation(data[pos + 8:pos + 8 + length])
            if chunk == b"IEND":
                break
            pos += 12 + length
    elif kind == "webp":
        pos = 12
        while pos + 8 <= len(data):
            chunk, size = data[pos:pos + 4], struct.unpack("<I", data[pos + 4:pos + 8])[0]
            if chunk == b"EXIF":
                return tiff_orientation(data[pos + 8:pos + 8 + size])
            pos += 8 + size + (size % 2)
    return 1


def _drop(marker: int, seg: bytes) -> bool:
    keep = (marker in JPEG_KEEP
            or (marker == 0xEE and seg[4:9] == b"Adobe")   # by its signature (#23 verify round 4, M5)
            or (marker == 0xE0 and seg[4:9] == b"JFIF\x00")
            or (marker == 0xE2 and seg[4:16] == b"ICC_PROFILE\x00"))
    return not keep


def _keep(marker: int, seg: bytes) -> bytes:
    """A kept segment as written to the copy: a JFIF APP0 loses its thumbnail, which can show the
    uncropped original (round 4, M5)."""
    if marker == 0xE0 and seg[4:9] == b"JFIF\x00" and len(seg) > 18:
        return b"\xff\xe0" + struct.pack(">H", 16) + seg[4:16] + b"\x00\x00"
    return seg


def _scan_data(rest: bytes) -> bytes:
    """The image data after the first SOS, up to and including EOI, without APPn or COM segments
    between progressive scans. Inside entropy-coded data a 0xFF is followed by 0x00 (stuffing) or
    RST0-7, so any other marker byte starts a segment or ends the image. Any number of 0xFF fill
    bytes may precede a marker (ITU-T T.81 B.1.1.2); they are skipped, or `FF FF D9` would hide the
    end of the image and keep what was appended after it (#23 verify round 3, T2)."""
    out, pos = bytearray(), 0
    while pos < len(rest):
        byte = rest[pos]
        if byte != 0xFF or pos + 1 >= len(rest):
            out.append(byte); pos += 1; continue
        while pos + 2 < len(rest) and rest[pos + 1] == 0xFF:
            pos += 1
        marker = rest[pos + 1]
        if marker == 0x00 or 0xD0 <= marker <= 0xD7:
            out += rest[pos:pos + 2]; pos += 2; continue
        if marker == 0xD9:
            return bytes(out + b"\xff\xd9")   # end of image: anything appended after it is dropped
        length = struct.unpack(">H", rest[pos + 2:pos + 4])[0]
        seg = rest[pos:pos + 2 + length]
        if not _drop(marker, seg):
            out += _keep(marker, seg)
        pos += 2 + length
    # No end-of-image marker: what follows the image cannot be told apart from it (round 4, M5).
    raise MediaError("JPEG without an end-of-image marker")


def strip_jpeg(data: bytes) -> bytes:
    segments, rest = _jpeg_segments(data)
    kept = [_keep(marker, seg) for marker, seg in segments if not _drop(marker, seg)]
    return b"\xff\xd8" + b"".join(seg for seg in kept if seg != b"\xff\xd8") + _scan_data(rest)


def strip_png(data: bytes) -> bytes:
    if data[:8] != PNG_SIGNATURE:
        raise MediaError("not a PNG file")
    pos, out = 8, [PNG_SIGNATURE]
    while pos + 8 <= len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        kind = data[pos + 4:pos + 8]
        chunk = data[pos:pos + 12 + length]
        if kind in PNG_KEEP:
            out.append(chunk)
        pos += 12 + length
        if kind == b"IEND":
            break
    return b"".join(out)


def strip_webp(data: bytes) -> bytes:
    if data[:4] != b"RIFF" or data[8:12] != b"WEBP":
        raise MediaError("not a WebP file")
    # The image ends where the RIFF header says; a second file appended after it is dropped.
    end = min(len(data), 8 + struct.unpack("<I", data[4:8])[0])
    pos, chunks = 12, []
    while pos + 8 <= end:
        kind, size = data[pos:pos + 4], struct.unpack("<I", data[pos + 4:pos + 8])[0]
        body = data[pos + 8:min(pos + 8 + size, end)]
        if kind == b"VP8X" and body:
            body = bytes([body[0] & ~0x0C]) + body[1:]   # clear the EXIF (0x08) and XMP (0x04) flags
        if kind == b"ANMF" and len(body) >= 16:   # a frame keeps its header and image chunks (round 4, M5)
            body = body[:16] + _webp_frame_chunks(body[16:])
            size = len(body)
        if kind in WEBP_KEEP:
            chunks.append(kind + struct.pack("<I", size) + body + (b"\x00" if size % 2 else b""))
        pos += 8 + size + (size % 2)
    payload = b"WEBP" + b"".join(chunks)
    return b"RIFF" + struct.pack("<I", len(payload)) + payload


def _webp_frame_chunks(data: bytes) -> bytes:
    out, pos = [], 0
    while pos + 8 <= len(data):
        kind, size = data[pos:pos + 4], struct.unpack("<I", data[pos + 4:pos + 8])[0]
        if kind in (b"ALPH", b"VP8 ", b"VP8L"):
            out.append(data[pos:pos + 8 + size] + (b"\x00" if size % 2 else b""))
        pos += 8 + size + (size % 2)
    return b"".join(out)


def strip_file(path: str, kind: str) -> None:
    strip = {"jpeg": strip_jpeg, "png": strip_png, "webp": strip_webp}[kind]
    with open(path, "rb") as fh:
        cleaned = strip(fh.read())
    with open(path, "wb") as fh:
        fh.write(cleaned)


def prepare_copy(src: str, frames_dir: str, stem: str) -> str:
    """Write the run's copy of one image; returns its file name inside frames_dir."""
    with open(src, "rb") as fh:
        data = fh.read()
    kind = kind_of(data)
    turn = orientation(data)
    if kind == "gif" or (kind == "webp" and turn != 1):
        # GIF, and a WebP that has to be turned, become PNG: sips writes PNG reliably.
        target = os.path.join(frames_dir, f"{stem}.png")
        subprocess.run(["sips", "-s", "format", "png", src, "--out", target], capture_output=True, check=True)
        kind = "png"
    else:
        target = os.path.join(frames_dir, f"{stem}.{'jpg' if kind == 'jpeg' else kind}")
        with open(target, "wb") as fh:
            fh.write(data)
    # Turn upright first, strip last: sips writes an EXIF block of its own when it saves
    # (measured 2026-10-07), so anything stripped before a sips step comes back.
    for step in ORIENTATION_STEPS.get(turn, []):
        subprocess.run(["sips", *step, target, "--out", target], capture_output=True, check=True)
    strip_file(target, kind)
    return os.path.basename(target)
