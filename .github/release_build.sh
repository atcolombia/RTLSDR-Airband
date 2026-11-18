#!/bin/bash
# Builds a portable rtl_airband release binary inside a debian:<codename>
# container. Used by .github/workflows/release_binaries.yml.
#
# Usage: release_build.sh <version> <debian-major> <arch-name> <flavor>
#   e.g. release_build.sh v0.0.5 12 linux-arm64 plain
# flavor "plain" builds RTL-SDR only, so it runs on receivers without
# libSoapySDR; "soapy" also enables SoapySDR (Airspy receivers) and gets a
# "-soapy" suffix.
#
# Must run from the repository root (mounted at /src). Outputs go to
# build-release/dist/ (ignored by git through the build*/ pattern so the
# git describe version is never marked -dirty).
set -euo pipefail

VERSION="$1"
DEBIAN_MAJOR="$2"
ARCH_NAME="$3"
FLAVOR="${4:-plain}"
case "${FLAVOR}" in
  plain) SOAPYSDR=OFF; SUFFIX="" ;;
  soapy) SOAPYSDR=ON; SUFFIX="-soapy" ;;
  *) echo "::error::unknown flavor ${FLAVOR}"; exit 1 ;;
esac

BUILD_DIR="build-release"
DIST_DIR="${BUILD_DIR}/dist"
ASSET="rtl_airband-${VERSION}-debian${DEBIAN_MAJOR}-${ARCH_NAME}${SUFFIX}"

echo "::group::Container info"
uname -a
cat /etc/os-release
dpkg --print-architecture
echo "::endgroup::"

echo "::group::Install packages"
export DEBIAN_FRONTEND=noninteractive
# Debian 11 reached end of life: its security pool is no longer served by
# deb.debian.org, so take every bullseye suite from archive.debian.org.
# (read os-release in a subshell: it defines VERSION and would clobber ours)
# shellcheck source=/dev/null
CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME}")"
if [ "${CODENAME}" = "bullseye" ]; then
  for f in /etc/apt/sources.list /etc/apt/sources.list.d/*; do
    [ -f "$f" ] || continue
    sed -i -E 's#https?://(deb|security)\.debian\.org/#http://archive.debian.org/#g' "$f"
  done
  cat /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null || true
  echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99archive
fi
apt-get update -y
apt-get install -y --no-install-recommends \
  build-essential cmake pkg-config ca-certificates \
  libmp3lame-dev libshout3-dev libconfig++-dev libfftw3-dev \
  librtlsdr-dev libsoapysdr-dev libcurl4-openssl-dev git
echo "::endgroup::"

# The workspace is owned by the runner user, not root.
git config --global --add safe.directory "$(pwd)"
echo "git describe: $(git describe --tags --abbrev --dirty --always)"

echo "::group::Configure"
cmake -B "${BUILD_DIR}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DPLATFORM=generic \
  -DMIRISDR=OFF \
  -DPULSEAUDIO=OFF \
  -DNFM=OFF \
  -DSOAPYSDR="${SOAPYSDR}" \
  -DRTLSDR=ON \
  -DBUILD_UNITTESTS=TRUE
echo "::endgroup::"

echo "::group::Build"
cmake --build "${BUILD_DIR}" -j"$(nproc)"
echo "::endgroup::"

echo "::group::Unit tests"
"${BUILD_DIR}/src/unittests"
echo "::endgroup::"

mkdir -p "${DIST_DIR}"
cp "${BUILD_DIR}/src/rtl_airband" "${DIST_DIR}/${ASSET}"
strip "${DIST_DIR}/${ASSET}"
chmod 0755 "${DIST_DIR}/${ASSET}"

VERSION_OUTPUT="$("${DIST_DIR}/${ASSET}" -v 2>&1 | head -n 1)"
echo "rtl_airband -v: ${VERSION_OUTPUT}"
if [[ "${VERSION_OUTPUT}" != *"${VERSION}"* ]]; then
  echo "::error::rtl_airband -v output '${VERSION_OUTPUT}' does not contain '${VERSION}'"
  exit 1
fi

LDD_OUTPUT="$(ldd "${DIST_DIR}/${ASSET}")"
echo "::group::ldd"
echo "${LDD_OUTPUT}"
echo "::endgroup::"
if grep -q "not found" <<<"${LDD_OUTPUT}"; then
  echo "::error::unresolved shared libraries"
  exit 1
fi

# Raw metadata for the manifest; the workflow turns it into JSON on the host.
printf '%s\n' "${VERSION_OUTPUT}" > "${DIST_DIR}/${ASSET}.version.txt"
printf '%s\n' "${LDD_OUTPUT}" > "${DIST_DIR}/${ASSET}.ldd.txt"
