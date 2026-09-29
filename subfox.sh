#!/usr/bin/env bash
# subfox - list series episodes and rename matching .srt subtitles to them.
#
# Usage:
#   subfox -s DIR [-o FILE]                      list episode names (no extension)
#   subfox -r DIR [-f LIST] -suf SUFFIX [opts]   rename .srt files in DIR
#
# Options:
#   -s DIR        scan DIR for video files, print names without extension
#   -o FILE       (with -s) write the list to FILE instead of stdout
#   -r DIR        directory containing the .srt files to rename
#   -f FILE       item list made by -s (default: build it from DIR itself)
#   -suf SUFFIX   suffix added before .srt, e.g. en.1 -> name.en.1.srt
#   -n            dry run, only show what would happen
#   --force       overwrite existing target files
#   --no-title    match by season/episode only, ignore the title
#   -h            help

set -u
shopt -s nocasematch

VIDEO_EXT_RE='^(mkv|mp4|avi|mov|wmv|m4v|ts|flv|webm|mpg|mpeg)$'

usage() { sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; }
die()   { echo "subfox: $*" >&2; exit 1; }

# ---------- helpers ----------

# Normalise text: lowercase, keep only a-z0-9
norm() { local s="${1,,}"; echo "${s//[^a-z0-9]/}"; }

# Sets globals KEY (e.g. S01E12) and TITLE (normalised text before the tag).
# Returns 1 if no season/episode tag is found.
extract_key() {
  local n="${1,,}" pre s e
  KEY=""; TITLE=""
  if   [[ $n =~ (^|[^a-z0-9])s([0-9]{1,2})[^a-z0-9]*e([0-9]{1,3})([^0-9]|$) ]]; then
    s=${BASH_REMATCH[2]}; e=${BASH_REMATCH[3]}
  elif [[ $n =~ (^|[^a-z0-9])season[^a-z0-9]*([0-9]{1,2})[^a-z0-9]*episode[^a-z0-9]*([0-9]{1,3})([^0-9]|$) ]]; then
    s=${BASH_REMATCH[2]}; e=${BASH_REMATCH[3]}
  elif [[ $n =~ (^|[^a-z0-9])([0-9]{1,2})x([0-9]{2,3})([^a-z0-9]|$) ]]; then
    s=${BASH_REMATCH[2]}; e=${BASH_REMATCH[3]}
  else
    return 1
  fi
  pre="${n%%"${BASH_REMATCH[0]}"*}"
  KEY=$(printf 'S%02dE%02d' "$((10#$s))" "$((10#$e))")
  TITLE=$(norm "$pre")
  return 0
}

# Print video basenames (no extension), one per line, sorted
list_items() {
  local dir=$1 f ext
  while IFS= read -r -d '' f; do
    f=${f##*/}; ext=${f##*.}
    [[ $ext =~ $VIDEO_EXT_RE ]] && echo "${f%.*}"
  done < <(find "$dir" -maxdepth 1 -type f -print0 | sort -z)
}

# ---------- argument parsing ----------

SCAN_DIR=""; OUT_FILE=""; REN_DIR=""; LIST_FILE=""; SUFFIX=""
DRY=0; FORCE=0; CHECK_TITLE=1

while (($#)); do
  case $1 in
    -s)                 SCAN_DIR=${2:-}; shift 2 ;;
    -o)                 OUT_FILE=${2:-}; shift 2 ;;
    -r)                 REN_DIR=${2:-};  shift 2 ;;
    -f)                 LIST_FILE=${2:-}; shift 2 ;;
    -suf|--suf|--suffix) SUFFIX=${2:-};  shift 2 ;;
    -n|--dry-run)       DRY=1;  shift ;;
    --force)            FORCE=1; shift ;;
    --no-title)         CHECK_TITLE=0; shift ;;
    -h|--help)          usage; exit 0 ;;
    *)                  die "unknown option: $1 (try -h)" ;;
  esac
done

# ---------- mode 1: list ----------

if [[ -n $SCAN_DIR ]]; then
  [[ -d $SCAN_DIR ]] || die "not a directory: $SCAN_DIR"
  if [[ -n $OUT_FILE ]]; then
    list_items "$SCAN_DIR" > "$OUT_FILE"
    echo "subfox: wrote $(wc -l < "$OUT_FILE") items to $OUT_FILE" >&2
  else
    list_items "$SCAN_DIR"
  fi
  [[ -z $REN_DIR ]] && exit 0
fi

# ---------- mode 2: rename ----------

[[ -n $REN_DIR ]] || { usage; exit 1; }
[[ -d $REN_DIR ]] || die "not a directory: $REN_DIR"
[[ -n $SUFFIX ]]  || die "-suf is required for renaming"
SUFFIX=${SUFFIX#.}

# Load items (from -f, or straight from the directory)
if [[ -n $LIST_FILE ]]; then
  [[ -f $LIST_FILE ]] || die "list file not found: $LIST_FILE"
  ITEMS=$(cat "$LIST_FILE")
else
  ITEMS=$(list_items "$REN_DIR")
fi

declare -A ITEM_BY_KEY ITEM_TITLE TARGET_USED
while IFS= read -r item; do
  item=${item%$'\r'}; item=${item##*/}
  [[ -z $item ]] && continue
  if ! extract_key "$item"; then
    echo "skip item (no season/episode tag): $item" >&2; continue
  fi
  if [[ -n ${ITEM_BY_KEY[$KEY]:-} ]]; then
    echo "warning: duplicate episode $KEY in list, keeping '${ITEM_BY_KEY[$KEY]}'" >&2
    continue
  fi
  ITEM_BY_KEY[$KEY]=$item
  ITEM_TITLE[$KEY]=$TITLE
done <<< "$ITEMS"

((${#ITEM_BY_KEY[@]})) || die "no usable items in list"

renamed=0; skipped=0; unmatched=0

while IFS= read -r -d '' path; do
  file=${path##*/}
  base=${file%.*}

  if ! extract_key "$base"; then
    echo "no episode tag:   $file"; ((unmatched++)); continue
  fi

  item=${ITEM_BY_KEY[$KEY]:-}
  if [[ -z $item ]]; then
    echo "no such episode:  $file ($KEY not in list)"; ((unmatched++)); continue
  fi

  # title sanity check (lenient: one contains the other; empty subtitle title passes)
  if ((CHECK_TITLE)) && [[ -n $TITLE && -n ${ITEM_TITLE[$KEY]} ]]; then
    if [[ $TITLE != *"${ITEM_TITLE[$KEY]}"* && ${ITEM_TITLE[$KEY]} != *"$TITLE"* ]]; then
      echo "title mismatch:   $file (expected series like '$item')"; ((unmatched++)); continue
    fi
  fi

  target="$item.$SUFFIX.srt"

  if [[ $file == "$target" ]]; then
    echo "already named:    $file"; ((skipped++)); continue
  fi
  if [[ -n ${TARGET_USED[$target]:-} ]]; then
    echo "duplicate for $KEY: $file (already used '${TARGET_USED[$target]}')"; ((skipped++)); continue
  fi
  if [[ -e $REN_DIR/$target && $FORCE -eq 0 ]]; then
    echo "target exists:    $file -> $target (use --force)"; ((skipped++)); continue
  fi

  TARGET_USED[$target]=$file
  if ((DRY)); then
    echo "[dry] $file -> $target"
  else
    mv -f -- "$path" "$REN_DIR/$target" && echo "renamed: $file -> $target"
  fi
  ((renamed++))
done < <(find "$REN_DIR" -maxdepth 1 -type f -iname '*.srt' -print0 | sort -z)

echo "done: $renamed renamed, $skipped skipped, $unmatched unmatched" >&2
