#!/bin/sh
# Installs m1, the command-line tool of m1cro.cloud, from the registry its
# releases are published to:
#
#   curl -fsSL https://m1cro.cloud/install.sh | sh
#
# M1_VERSION picks a version (the latest by default), M1_INSTALL_DIR the
# folder (~/.local/bin by default); M1_OS and M1_ARCH take the build of
# another system. m1 is under the PolyForm Noncommercial License 1.0.0:
# https://m1cro.cloud/LICENSE.md
set -eu

registry="${M1_REGISTRY:-https://ghcr.io}"
repository="${M1_REPOSITORY:-lastfrake/m1-cli}"
dir="${M1_INSTALL_DIR:-$HOME/.local/bin}"

fail() {
  echo "m1: $*" >&2
  exit 1
}

command -v curl > /dev/null || fail "curl is needed"
if command -v sha256sum > /dev/null; then
  sha() { sha256sum "$1" | cut -d' ' -f1; }
elif command -v shasum > /dev/null; then
  sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
else
  fail "sha256sum or shasum is needed"
fi

os="${M1_OS:-$(uname -s)}"
case "$os" in
  Linux | linux) os=linux ;;
  Darwin | darwin) os=darwin ;;
  *) fail "no build for $os; on Windows, use install.ps1" ;;
esac
arch="${M1_ARCH:-$(uname -m)}"
case "$arch" in
  x86_64 | amd64) arch=amd64 ;;
  aarch64 | arm64) arch=arm64 ;;
  *) fail "no build for $arch" ;;
esac
file="m1-$os-$arch"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# The registry lets anyone pull, with a token it gives without a login.
token=""
get() {
  if [ -n "$token" ]; then
    curl -fsSL -H "Authorization: Bearer $token" "$@"
  else
    curl -fsSL "$@"
  fi
}
challenge="$(curl -sS -o /dev/null -D - "$registry/v2/" | tr -d '\r' | sed -n 's/^[Ww][Ww][Ww]-[Aa]uthenticate: *[Bb]earer *//p')"
if [ -n "$challenge" ]; then
  realm="$(echo "$challenge" | sed -n 's/.*realm="\([^"]*\)".*/\1/p')"
  service="$(echo "$challenge" | sed -n 's/.*service="\([^"]*\)".*/\1/p')"
  token="$(curl -fsSL "$realm?service=$service&scope=repository:$repository:pull" | sed -n 's/.*"token": *"\([^"]*\)".*/\1/p')" ||
    fail "the registry gave no token to pull $repository"
  [ -n "$token" ] || fail "the registry gave no token to pull $repository"
fi

version="${M1_VERSION:-}"
if [ -z "$version" ]; then
  tags="$(get "$registry/v2/$repository/tags/list")" || fail "could not list the versions of m1"
  # The highest release, X.Y.Z alone.
  version="$(echo "$tags" | tr ',[]' '\n\n\n' | sed -n 's/^ *"\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)" *}* *$/\1/p' |
    sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1)"
  [ -n "$version" ] || fail "no version of m1 is published"
fi

get -H "Accept: application/vnd.oci.image.manifest.v1+json" -o "$tmp/manifest" "$registry/v2/$repository/manifests/$version" ||
  fail "no m1 $version in $registry/$repository"
# The layer whose title is the file of this system.
digest="$(tr -d '\n\r\t ' < "$tmp/manifest" | awk '{ gsub(/\},\{/, "}\n{"); print }' | grep "\"org.opencontainers.image.title\":\"$file\"" |
  sed -n 's/.*"digest":"\(sha256:[0-9a-f]\{64\}\)".*/\1/p' | head -n 1)"
[ -n "$digest" ] || fail "m1 $version has no build $file"

get -o "$tmp/m1" "$registry/v2/$repository/blobs/$digest" || fail "could not download $file of m1 $version"
[ "sha256:$(sha "$tmp/m1")" = "$digest" ] || fail "$file of m1 $version does not match its digest $digest; nothing is installed"

mkdir -p "$dir"
chmod +x "$tmp/m1"
mv "$tmp/m1" "$dir/m1"
echo "m1 $version is installed as $dir/m1"
case ":$PATH:" in
  *":$dir:"*) ;;
  *) echo "Add $dir to PATH to run it as m1." ;;
esac
echo "m1 is under the PolyForm Noncommercial License 1.0.0: https://m1cro.cloud/LICENSE.md"
