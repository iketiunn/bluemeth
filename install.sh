#!/bin/sh
set -eu

version="v1.0.2"

case "${1-}" in
  "")
    ;;
  main)
    version="main"
    ;;
  *)
    echo "usage: install.sh [main]" >&2
    exit 1
    ;;
esac

if [ "$#" -gt 1 ]; then
  echo "usage: install.sh [main]" >&2
  exit 1
fi

install_dir="${HOME}/.local/bin"
install_path="${install_dir}/bluemeth"
url="https://raw.githubusercontent.com/iketiunn/bluemeth/${version}/bin/bluemeth"
tmp_file="$(mktemp "${TMPDIR:-/tmp}/bluemeth.XXXXXX")"

cleanup() {
  rm -f "$tmp_file"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$install_dir"
curl -fsSL "$url" -o "$tmp_file"
chmod +x "$tmp_file"
"$tmp_file" -h >/dev/null
mv "$tmp_file" "$install_path"
trap - EXIT HUP INT TERM

echo "installed: $install_path"
echo "make sure $install_dir is in your PATH"
