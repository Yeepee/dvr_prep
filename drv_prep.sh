#!/bin/bash

# Fixes AAC audio for DaVinci Resolve on Linux by remuxing MP4 (H.264/H.265) 
# into MOV with 24-bit PCM audio without re-encoding video.

RECURSIVE=false

show_help() {
    cat << EOF
Usage: $(basename "$0") [-r] [-h] <source> [destination]

Prepares MP4 files (H.264/H.265) for DaVinci Resolve on Linux by converting
unsupported AAC audio into 24-bit PCM audio inside a MOV container.
Video streams are copied bit-for-bit without quality loss.
Original MP4 files are deleted only if conversion succeeds.

Options:
  -r    Enable recursive processing of subdirectories.
  -h    Display this help message and exit.

Arguments:
  <source>       MP4 file or directory containing videos.
  [destination]  (Optional) Target directory to store .mov files.
                 If omitted, conversion happens in-place.

Examples:
  $(basename "$0") /my/nas/footage
  $(basename "$0") -r /my/nas/footage
  $(basename "$0") -r /run/media/sdcard/DCIM ~/Videos/MyProject
EOF
}

# Parse options (-r, -h)
while getopts "rh" opt; do
    case $opt in
        r) RECURSIVE=true ;;
        h) show_help; exit 0 ;;
        *) show_help; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

SRC="$1"
DEST="$2"

# Check source availability
if [ -z "$SRC" ]; then
    echo "Error: No source path specified."
    echo ""
    show_help
    exit 1
fi

if [ ! -e "$SRC" ]; then
    echo "Error: Source path '$SRC' does not exist."
    exit 1
fi

convert_file() {
    local input="$1"
    local output="$2"

    # Create target directory if needed
    mkdir -p "$(dirname "$output")"

    echo "Processing: $input"
    if ffmpeg -hide_banner -loglevel error -stats -i "$input" -c:v copy -c:a pcm_s24le "$output"; then
        rm "$input"
        echo " -> Converted: $output (source deleted)"
    else
        echo " -> ERROR converting $input (source retained)"
    fi
}

# Process directory
if [ -d "$SRC" ]; then
    echo "=== Processing directory: $SRC (Recursive: $RECURSIVE) ==="
    SRC_CLEAN="${SRC%/}"

    FIND_OPTS=()
    if [ "$RECURSIVE" = false ]; then
        FIND_OPTS+=("-maxdepth" "1")
    fi

    find "$SRC_CLEAN" "${FIND_OPTS[@]}" -type f -iname "*.mp4" | while read -r f; do
        if [ -n "$DEST" ]; then
            rel_path="${f#$SRC_CLEAN/}"
            out_file="${DEST%/}/${rel_path%.*}.mov"
        else
            out_file="${f%.*}.mov"
        fi
        convert_file "$f" "$out_file"
    done
    echo "=== Processing completed ==="

# Process single file
elif [ -f "$SRC" ]; then
    if [[ "$SRC" =~ \.(mp4|MP4)$ ]]; then
        filename=$(basename "$SRC")
        if [ -n "$DEST" ]; then
            out_file="${DEST%/}/${filename%.*}.mov"
        else
            out_file="${SRC%.*}.mov"
        fi
        convert_file "$SRC" "$out_file"
        echo "=== Processing completed ==="
    else
        echo "Error: File must be in .mp4 format"
        exit 1
    fi
fi
