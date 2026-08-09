#!/bin/bash
# ====================================================================
#  compress_previews.sh
#  SirenTorturers Edition (KFMapVoteST) - map vote preview pipeline,
#  STAGE 2 of 3 (compress)
#
#  Run on the Mac (or any machine with ImageMagick), between
#  Export-PreviewTextures.bat (stage 1, Windows/ucc) and
#  Import-PreviewPackage.bat (stage 3, Windows/ucc) - see those two
#  scripts' own header comments for the full pipeline picture.
#
#  WHAT THIS DOES AND WHY
#  ------------------------
#  Every file staged by Export-PreviewTextures.bat (a mix of .dds,
#  .pcx, .bmp) gets re-encoded to a single, small, DXT1-compressed
#  .dds, capped at 512x256, written to OUTPUT_DIR under the SAME
#  basename (just with a .dds extension) - so Import-PreviewPackage.bat
#  and KFMapVoteSTStagedResults.ini's HeadName references still line up
#  unchanged.
#
#  This exists because a real import (KFMapVoteST_Previews.utx) came
#  back 135MB: most staged textures were either uncompressed PCX
#  (~393KB each for a 512x256 24-bit image) or already-compressed DDS
#  in DXT3/DXT5 (8 bits/pixel - TWICE the size of DXT1's 4 bits/pixel,
#  and KF1 vanilla preview-style textures have no real use for the
#  extra alpha precision DXT3/5 exist for). Forcing everything through
#  ImageMagick to a uniform DXT1 .dds, capped at the original spec's
#  512x256 (see the very first design note for this feature), measured
#  around a 3x-4x total size reduction on real staged output from this
#  project's own map pool.
#
#  THE ddspf.dwSize/dwFlags BUG - WHY DDS INPUTS ARE PATCHED FIRST
#  -------------------------------------------------------------------
#  `ucc batchexport`'s own DDS writer leaves two fields in the DDS
#  header zeroed that the spec requires to be set (confirmed by reading
#  the raw bytes of a real exported file, not assumed):
#    - ddspf.dwSize (offset 76, 4 bytes) - spec requires 32, ucc writes 0
#    - ddspf.dwFlags (offset 80, 4 bytes) - spec requires DDPF_FOURCC
#      (0x4) set so readers know dwFourCC is valid, ucc writes 0
#  Everything else in ucc's header (top-level dwFlags, width, height,
#  mip count, the actual "DXT1"/"DXT5"/etc. fourCC bytes) is correct.
#  ImageMagick's DDS reader is strict and rejects the file outright
#  ("improper image header") without those two fields set - confirmed
#  directly: patching just those 8 bytes on a scratch copy is enough to
#  make ImageMagick read the exact same file it was rejecting a moment
#  before. This is very likely the same underlying non-spec-conformance
#  behind the "Assertion failed: MipmapSize <= Length" crash that made
#  KF-Chthon-SE crash ucc's OWN importer in an earlier version of this
#  pipeline (see GenerateMapPreviewsCommandlet-handoff.md) - re-encoding
#  every texture through ImageMagick's own (correct) DDS writer, as
#  this script does regardless of source format, should fix that
#  category of problem at its root instead of working around it.
#
#  .pcx/.bmp inputs need no such patching - ImageMagick reads those
#  natively without issue - and go straight through the same convert
#  step below.
#
#  HOW TO RUN
#  -----------
#      ./compress_previews.sh [INPUT_DIR] [OUTPUT_DIR]
#
#  Defaults: INPUT_DIR=../../PreviewStaged, OUTPUT_DIR=../../PreviewCompressed
#  (both relative to this script's own location in KFMapVoteST/Tools/,
#  landing on the repo-root PreviewStaged/ - the same folder
#  Export-PreviewTextures.bat's STAGEDDIR default writes to, since that
#  script runs from System/ with STAGEDDIR=..\PreviewStaged). Non-
#  destructive - INPUT_DIR is never modified, only read; safe to re-run.
# ====================================================================
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
INPUT_DIR=${1:-"$SCRIPT_DIR/../../PreviewStaged"}
OUTPUT_DIR=${2:-"$SCRIPT_DIR/../../PreviewCompressed"}
MAXSIZE="512x256"
FAILLOG="$SCRIPT_DIR/PreviewCompressFailures.txt"

if ! command -v magick >/dev/null 2>&1; then
	echo "ERROR: 'magick' (ImageMagick 7+) not found on PATH. Install via 'brew install imagemagick'." >&2
	exit 1
fi

if [ ! -d "$INPUT_DIR" ]; then
	echo "ERROR: INPUT_DIR not found: $INPUT_DIR" >&2
	exit 1
fi

mkdir -p "$OUTPUT_DIR"
: > "$FAILLOG"

shopt -s nullglob nocaseglob

count=0
fail=0

for f in "$INPUT_DIR"/*.dds "$INPUT_DIR"/*.pcx "$INPUT_DIR"/*.bmp; do
	base=$(basename "$f")
	name="${base%.*}"
	ext="${base##*.}"
	ext_lower=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
	out="$OUTPUT_DIR/$name.dds"

	src_arg="$f"
	tmp=""
	if [ "$ext_lower" = "dds" ]; then
		# Patch ddspf.dwSize/dwFlags on a scratch copy - see header
		# comment. mktemp with no extension is fine: the "dds:" format
		# prefix below forces ImageMagick to read it as DDS regardless
		# of filename.
		tmp=$(mktemp)
		cp "$f" "$tmp"
		python3 - "$tmp" <<'PYEOF'
import struct, sys
path = sys.argv[1]
with open(path, 'r+b') as fh:
    fh.seek(76); fh.write(struct.pack('<I', 32))  # ddspf.dwSize
    fh.seek(80); fh.write(struct.pack('<I', 4))   # ddspf.dwFlags = DDPF_FOURCC
PYEOF
		src_arg="dds:$tmp"
	fi

	if magick "$src_arg" -resize "${MAXSIZE}>" -define dds:compression=dxt1 "$out" 2>>"$FAILLOG"; then
		count=$((count + 1))
	else
		echo "FAILED: $f" >>"$FAILLOG"
		fail=$((fail + 1))
	fi

	[ -n "$tmp" ] && rm -f "$tmp"
done

echo
echo "compress_previews.sh: $count compressed to DXT1 in $OUTPUT_DIR, $fail failed."
if [ "$fail" -gt 0 ]; then
	echo "See $FAILLOG for details on the failures."
fi
