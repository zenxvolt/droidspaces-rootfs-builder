#!/bin/bash
# Droidspaces RootFS build engine (x86_64). Builds one template.
#
#   ./build.sh -i <Name> [-v <version>] [-a <arch>] [-f <format>]
#   ./build.sh -i Ubuntu-24.04-Minimal -v v20260101-000000 -f zst
#   ./build.sh -a aarch64 -i Debian-13-Minimal
#
# <Name> is templates/<arch>/<Name>.Dockerfile.
# -a <arch> is optional and defaults to x86_64; it must be a key in archs.json.
# -f <format> is optional and defaults to xz. Accepted: gz, xz, zst
#    (tar.gz, tar.xz and tar.zst are accepted too).
# Output: <Name>-Droidspaces-rootfs-<arch>-<YYYYMMDD>-<version>.tar.<format>
set -euo pipefail
cd "$(dirname "$0")"

VERSION="dev"
ARCH="x86_64"
FORMAT="xz"
USAGE="Usage: $0 -i <Name> [-v <version>] [-a <arch>] [-f gz|xz|zst]"
while getopts "a:f:i:v:" opt; do
  case $opt in
    a) ARCH="$OPTARG" ;;
    f) FORMAT="$OPTARG" ;;
    i) NAME="${OPTARG%.Dockerfile}" ;;
    v) VERSION="$OPTARG" ;;
    *) echo "$USAGE" >&2; exit 1 ;;
  esac
done
[ -n "${NAME:-}" ] || { echo "$USAGE" >&2; exit 1; }

DOCKERFILE="templates/$ARCH/$NAME.Dockerfile"
[ -f "$DOCKERFILE" ] || { echo "Error: $DOCKERFILE not found" >&2; exit 1; }

PLATFORM=$(jq -er --arg a "$ARCH" '.[$a].platform' archs.json) \
  || { echo "Error: arch '$ARCH' not in archs.json" >&2; exit 1; }

# Normalise the format: ".tar.zst" / "tar.zst" / "zst" -> "zst".
FORMAT="${FORMAT#.}"
FORMAT="${FORMAT#tar.}"

# Each branch sets SUFFIX (what the compressor appends to the .tar) and COMPRESS
# (the command run on the .tar; it must replace the input file).
case "$FORMAT" in
  gz)
    SUFFIX=".gz"
    if command -v pigz >/dev/null 2>&1; then COMPRESS=(pigz -9 -f); else COMPRESS=(gzip -9 -f); fi
    ;;
  xz)
    SUFFIX=".xz"
    COMPRESS=(xz -T0 -9 -f)
    ;;
  zst)
    SUFFIX=".zst"
    COMPRESS=(zstd -T0 -19 -f --rm -q)
    ;;
  *)
    echo "Error: unsupported format '$FORMAT' (use gz, xz or zst)" >&2
    exit 1
    ;;
esac
command -v "${COMPRESS[0]}" >/dev/null 2>&1 \
  || { echo "Error: '${COMPRESS[0]}' is not installed" >&2; exit 1; }

FINAL_NAME="${NAME}-Droidspaces-rootfs-${ARCH}-$(date +%Y%m%d)-${VERSION}.tar${SUFFIX}"
TEMP_TAR="custom-${ARCH}-${NAME}-rootfs.tar"

echo "========================================================="
echo " Template : $DOCKERFILE"
echo " Platform : $PLATFORM"
echo " Version  : $VERSION"
echo " Format   : tar${SUFFIX}"
echo "========================================================="

# Register QEMU handlers only when the host cannot run the target natively
# (for example, building on an ARM machine). On an x86_64 host this is skipped.
if ! docker run --rm --platform "$PLATFORM" alpine:3.23 true >/dev/null 2>&1; then
  echo "Host cannot run $PLATFORM natively; installing binfmt/QEMU..."
  docker run --privileged --rm tonistiigi/binfmt --install all >/dev/null
fi

if ! docker buildx inspect droidspaces-builder >/dev/null 2>&1; then
  docker buildx create --name droidspaces-builder --driver docker-container --use
else
  docker buildx use droidspaces-builder
fi
docker buildx inspect --bootstrap >/dev/null

docker buildx build \
  --platform "$PLATFORM" \
  --target export \
  --output "type=tar,dest=$TEMP_TAR" \
  -f "$DOCKERFILE" \
  .

echo "Compressing (${COMPRESS[*]})..."
"${COMPRESS[@]}" "$TEMP_TAR"
mv "${TEMP_TAR}${SUFFIX}" "$FINAL_NAME"

echo "========================================================="
echo " Done: $FINAL_NAME"
echo "========================================================="
