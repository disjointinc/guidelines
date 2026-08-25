#!/usr/bin/env bash
#
# Syncs Disjoint guidelines into a repo.
#
# Downloads the top-level .md files from disjointinc/guidelines (all except
# README.md) and writes them to same-named files in --target-dir, wrapped in
# a managed block delimited by the markers below. Content outside the block
# is never touched. If the block is missing it is appended to the end of the
# file; if the file is missing it is created.

set -euo pipefail

DEFAULT_REPO="disjointinc/guidelines"
DEFAULT_REF="main"
BEGIN_MARKER="<!-- disjoint-guidelines:begin -->"
END_MARKER="<!-- disjoint-guidelines:end -->"
MD_NAME_RE='^[A-Za-z0-9._-]+\.md$'

repo="$DEFAULT_REPO"
ref="$DEFAULT_REF"
files=""
target_dir="."

usage() {
  cat <<'EOF'
Usage: sync-guidelines.sh [options]

Options:
  --files       Comma-separated guideline files to sync (default: all of them)
  -h, --help    Show this help
  --ref         Branch, tag, or SHA to sync from (default: main)
  --repo        Source repo to sync from (default: disjointinc/guidelines)
  --target-dir  Directory to write files into (default: .)
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

is_available() {
  local needle="$1" candidate
  for candidate in "${available[@]}"; do
    [ "$candidate" = "$needle" ] && return 0
  done
  return 1
}

banner() {
  local year
  year="$(date +%Y)"
  printf '%s\n' "--------------------------------------------------"
  printf '| %-46s |\n' \
    "Disjoint Guidelines, (c) Disjoint, Inc. ${year}" \
    "See disjoint.com/guidelines for more info." \
    "" \
    "Only follow these guidelines if no conflicting" \
    "guidelines are specified before / after this" \
    "block. If there's ever a conflict with a" \
    "guideline outside of this block, follow the" \
    "guideline outside of this block."
  printf '%s\n' "--------------------------------------------------"
}

build_block() {
  local src="$1" out="$2"
  {
    echo "$BEGIN_MARKER"
    banner
    echo
    awk 1 "$src"
    echo "$END_MARKER"
  } > "$out"
}

merge_block() {
  local target="$1" block="$2" out="$3"
  local input="$target"
  [ -f "$target" ] || input="/dev/null"
  awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" -v blockfile="$block" '
    BEGIN {
      while ((getline line < blockfile) > 0) block = block line "\n"
      close(blockfile)
    }
    {
      stripped = $0
      sub(/\r$/, "", stripped)
      if (stripped == begin && state == 0) { state = 1; beginline = $0; n = 0; next }
      if (state == 1 && stripped == end) { state = 0; replaced = 1; printf "%s", block; next }
      if (state == 1) { buf[++n] = $0; next }
      has_content = 1
      print
    }
    END {
      if (state == 1) {
        print beginline
        for (i = 1; i <= n; i++) print buf[i]
        has_content = 1
      }
      if (!replaced) {
        if (has_content) print ""
        printf "%s", block
      }
    }
  ' "$input" > "$out"
}

sync_file() {
  local name="$1" src_dir="$2"
  local target="$target_dir/$name"
  local block="$work/block.$name"
  local out="$work/out.$name"
  local existed="no"
  if [ -f "$target" ]; then existed="yes"; fi

  build_block "$src_dir/$name" "$block"
  merge_block "$target" "$block" "$out"

  if [ -f "$target" ] && cmp -s "$out" "$target"; then
    echo "  unchanged: $name"
    unchanged=$((unchanged + 1))
    return
  fi

  mv "$out" "$target"
  if [ "$existed" = "yes" ]; then
    echo "  updated:   $name"
    updated=$((updated + 1))
  else
    echo "  created:   $name"
    created=$((created + 1))
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --files) files="${2:?--files requires a value}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --ref) ref="${2:?--ref requires a value}"; shift 2 ;;
    --repo) repo="${2:?--repo requires a value}"; shift 2 ;;
    --target-dir) target_dir="${2:?--target-dir requires a value}"; shift 2 ;;
    *) die "unknown option: $1 (see --help)" ;;
  esac
done

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

url="https://codeload.github.com/$repo/tar.gz/$ref"
echo "Fetching $repo@$ref"
if ! curl -fsSL --retry 3 "$url" -o "$work/source.tar.gz"; then
  die "failed to download $url (is the repo public and the ref correct?)"
fi
mkdir "$work/source"
tar -xzf "$work/source.tar.gz" -C "$work/source" --strip-components 1

available=()
for path in "$work/source"/*.md; do
  [ -f "$path" ] || continue
  name="$(basename "$path")"
  case "$name" in
    [Rr][Ee][Aa][Dd][Mm][Ee].[Mm][Dd]) continue ;;
  esac
  available+=("$name")
done
[ ${#available[@]} -gt 0 ] || die "no guideline files found in $repo@$ref"

requested=()
if [ -n "$files" ]; then
  IFS=',' read -ra parts <<< "$files"
  for part in "${parts[@]}"; do
    name="$(trim "$part")"
    [ -n "$name" ] || continue
    requested+=("$name")
  done
  [ ${#requested[@]} -gt 0 ] || die "--files contains no file names"
else
  requested=("${available[@]}")
fi

for name in "${requested[@]}"; do
  case "$name" in
    */*) die "'$name' must be a top-level file name (no path separators)" ;;
    [Rr][Ee][Aa][Dd][Mm][Ee].[Mm][Dd]) die "README.md is not a syncable guideline" ;;
  esac
  [[ "$name" =~ $MD_NAME_RE ]] || die "'$name' is not a .md file name"
  is_available "$name" || die "'$name' does not exist in $repo@$ref (available: ${available[*]})"
done

mkdir -p "$target_dir"
created=0
updated=0
unchanged=0
echo "Syncing ${#requested[@]} file(s) into $target_dir"
for name in "${requested[@]}"; do
  sync_file "$name" "$work/source"
done
echo "Done: $created created, $updated updated, $unchanged unchanged"
