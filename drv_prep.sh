#!/bin/bash

# Copyright (c) 2026 Yeepee
# SPDX-License-Identifier: MIT
# Source: https://github.com/Yeepee/dvr_prep

# Fixes AAC audio for DaVinci Resolve on Linux by remuxing MP4 (H.264/H.265) 
# into MOV with 24-bit PCM audio without re-encoding video.

RECURSIVE=false
DELETE_ORIGINAL=false
VERBOSE=false
FFMPEG_PID=""
CURRENT_OUTPUT=""
CURRENT_LOG=""

stop_processing() {
    echo ""
    echo "Interrupted. Stopping current conversion..."
    if [ -n "$FFMPEG_PID" ]; then
        kill -INT "$FFMPEG_PID" 2>/dev/null
        for _ in {1..20}; do
            if ! kill -0 "$FFMPEG_PID" 2>/dev/null; then
                break
            fi
            sleep 0.1
        done
        kill -TERM "$FFMPEG_PID" 2>/dev/null
        kill -KILL "$FFMPEG_PID" 2>/dev/null
    fi
    if [ -n "$CURRENT_OUTPUT" ] && [ -e "$CURRENT_OUTPUT" ]; then
        rm -f "$CURRENT_OUTPUT"
        echo " -> Removed incomplete output: $CURRENT_OUTPUT"
    fi
    if [ -n "$CURRENT_LOG" ]; then
        rm -f "$CURRENT_LOG"
    fi
    exit 130
}

trap stop_processing INT TERM

show_help() {
    cat << EOF
Usage: $(basename "$0") [-r] [-d] [-v] [-h] <source> [destination]

Prepares MP4 files (H.264/H.265) for DaVinci Resolve on Linux by converting
unsupported AAC audio into 24-bit PCM audio inside a MOV container.
Video streams are copied bit-for-bit without quality loss.
Original MP4 files are kept by default.

Options:
  -r, --recursive         Enable recursive processing of subdirectories.
  -d, --delete-original   Delete original MP4 files after successful conversion.
  -v, --verbose           Display the complete FFmpeg output.
  -h, --help              Display this help message and exit.

Arguments:
  <source>       MP4 file or directory containing videos.
  [destination]  (Optional) Target directory to store .mov files.
                 If omitted, conversion happens in-place.

Examples:
  $(basename "$0") /my/nas/footage
  $(basename "$0") --recursive /my/nas/footage
  $(basename "$0") --recursive /run/media/sdcard/DCIM ~/Videos/MyProject
EOF
}

# Parse options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -r|--recursive)
            RECURSIVE=true
            shift
            ;;
        -d|--delete-original)
            DELETE_ORIGINAL=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        --)
            shift
            break
            ;;
        -*)
            echo "Error: Unknown option '$1'."
            echo ""
            show_help
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

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
    local temporary_output="${output}.part.mov"
    local temporary_log="${temporary_output}.log"

    # Create target directory if needed
    mkdir -p "$(dirname "$output")"
    rm -f "$temporary_output"
    rm -f "$temporary_log"

    echo "Processing: $input"
    CURRENT_OUTPUT="$temporary_output"
    if [ "$VERBOSE" = true ]; then
        ffmpeg -hide_banner -loglevel info -stats -i "$input" \
            -c:v copy -c:a pcm_s24le "$temporary_output" &
    else
        CURRENT_LOG="$temporary_log"
        ffmpeg -hide_banner -loglevel error -nostats -i "$input" \
            -c:v copy -c:a pcm_s24le "$temporary_output" 2>"$temporary_log" &
    fi
    FFMPEG_PID=$!
    wait "$FFMPEG_PID"
    ffmpeg_status=$?
    FFMPEG_PID=""

    if [ "$ffmpeg_status" -eq 0 ]; then
        mv -f "$temporary_output" "$output"
        CURRENT_OUTPUT=""
        CURRENT_LOG=""
        rm -f "$temporary_log"
        if [ "$DELETE_ORIGINAL" = true ]; then
            rm "$input"
            echo " -> Converted: $output (source deleted)"
        else
            echo " -> Converted: $output (source retained)"
        fi
    else
        if [ "$VERBOSE" = false ] && [ -f "$temporary_log" ]; then
            cat "$temporary_log"
        fi
        rm -f "$temporary_log"
        CURRENT_OUTPUT=""
        CURRENT_LOG=""
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

    while read -r f; do
        if [ -n "$DEST" ]; then
            rel_path="${f#$SRC_CLEAN/}"
            out_file="${DEST%/}/${rel_path%.*}.mov"
        else
            out_file="${f%.*}.mov"
        fi
        convert_file "$f" "$out_file"
    done < <(find "$SRC_CLEAN" "${FIND_OPTS[@]}" -type f -iname "*.mp4")
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
