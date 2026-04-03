#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -lt 2 ]]; then
  echo "usage: ghostty-libtool-all-members.sh <output> <archive> [<archive> ...]" >&2
  exit 2
fi

output_path="$1"
shift

working_dir="$(pwd)"
scratch_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$scratch_dir"
}
trap cleanup EXIT

archive_index=0
while [[ "$#" -gt 0 ]]; do
  archive_path="$1"
  shift

  if [[ "$archive_path" != /* ]]; then
    archive_path="$working_dir/${archive_path#./}"
  fi

  archive_dir="$scratch_dir/$archive_index"
  mkdir -p "$archive_dir"
  (
    cd "$archive_dir"
    /usr/bin/ar -x "$archive_path"
  )
  chmod -R u+rwX "$archive_dir"
  archive_index=$((archive_index + 1))
done

find "$scratch_dir" -type f -name '*.o' | LC_ALL=C sort >"$scratch_dir/filelist.txt"
/usr/bin/libtool -static -filelist "$scratch_dir/filelist.txt" -o "$output_path"
