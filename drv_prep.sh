#!/bin/bash

# Copyright (c) 2026 Yeepee
# SPDX-License-Identifier: MIT
# Source: https://github.com/Yeepee/dvr_prep

# Fixes AAC audio for DaVinci Resolve on Linux by remuxing video files into MOV
# with 24-bit PCM audio without re-encoding video.

RECURSIVE=false
DELETE_ORIGINAL=false
VERBOSE=false
FFMPEG_PID=""
CURRENT_OUTPUT=""
CURRENT_LOG=""
CURRENT_PROGRESS=""

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
    if [ -n "$CURRENT_PROGRESS" ]; then
        rm -f "$CURRENT_PROGRESS"
    fi
    exit 130
}

trap stop_processing INT TERM

show_help() {
    cat << EOF
Usage: $(basename "$0") [-r] [-d] [-v] [-h] <source> [source ...] [destination]

Prepares video files for DaVinci Resolve on Linux by converting AAC audio
into 24-bit PCM audio inside a MOV container. Files without AAC audio are skipped.
Video streams are copied bit-for-bit without quality loss.
Original files are kept by default.

Options:
  -r, --recursive         Enable recursive processing of subdirectories.
  -d, --delete-original   Delete original files after successful conversion.
  -v, --verbose           Display the complete FFmpeg output instead of progress.
  -h, --help              Display this help message and exit.

Arguments:
  <source>       Video file or directory containing video files. Multiple
                 sources, including shell-expanded file patterns, are allowed.
  [destination]  (Optional) Target directory to store .mov files.
                 If omitted, conversion happens next to each source file.

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

SOURCES=("$@")
SOURCE_COUNT=${#SOURCES[@]}
DEST=""

if [ "$SOURCE_COUNT" -eq 0 ]; then
    echo "Error: No source path specified."
    echo ""
    show_help
    exit 1
fi

if [ "$SOURCE_COUNT" -gt 1 ]; then
    last_argument="${SOURCES[$((SOURCE_COUNT - 1))]}"
    use_last_as_destination=false
    if [ -d "$last_argument" ] || [ ! -e "$last_argument" ]; then
        if [ "$SOURCE_COUNT" -eq 2 ] || [ ! -e "$last_argument" ]; then
            use_last_as_destination=true
        else
            use_last_as_destination=true
            for ((i = 0; i < SOURCE_COUNT - 1; i++)); do
                if [ ! -f "${SOURCES[$i]}" ]; then
                    use_last_as_destination=false
                    break
                fi
            done
        fi
    fi
    if [ "$use_last_as_destination" = true ]; then
        DEST="$last_argument"
        SOURCE_COUNT=$((SOURCE_COUNT - 1))
    fi
fi

for ((i = 0; i < SOURCE_COUNT; i++)); do
    if [ ! -e "${SOURCES[$i]}" ]; then
        echo "Error: Source path '${SOURCES[$i]}' does not exist."
        exit 1
    fi
    if [ ! -d "${SOURCES[$i]}" ] && [ ! -f "${SOURCES[$i]}" ]; then
        echo "Error: Source path '${SOURCES[$i]}' is not a regular file or directory."
        exit 1
    fi
done

draw_progress() {
    local current_us="$1"
    local duration_us="$2"
    local elapsed_seconds="$3"
    local columns="${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}"
    local line_width=$((columns < 80 ? columns : 80))
    local bar_width=$((line_width - 8))
    local percentage=0
    local remaining_seconds=0
    local filled
    local empty
    local filled_bar
    local empty_bar
    local eta

    [ "$bar_width" -lt 1 ] && bar_width=1
    if [[ "$duration_us" =~ ^[0-9]+$ ]] && [ "$duration_us" -gt 0 ] &&
        [[ "$current_us" =~ ^[0-9]+$ ]]; then
        percentage=$((current_us * 100 / duration_us))
        [ "$percentage" -gt 100 ] && percentage=100
    fi
    if [[ "$current_us" =~ ^[0-9]+$ ]] && [ "$current_us" -gt 0 ] &&
        [[ "$duration_us" =~ ^[0-9]+$ ]] &&
        [[ "$elapsed_seconds" =~ ^[0-9]+$ ]] && [ "$elapsed_seconds" -gt 0 ]; then
        remaining_seconds=$((elapsed_seconds * (duration_us - current_us) / current_us))
        [ "$remaining_seconds" -lt 0 ] && remaining_seconds=0
    fi
    eta=$(printf '%02d:%02d' $((remaining_seconds / 60)) $((remaining_seconds % 60)))
    filled=$((bar_width * percentage / 100))
    empty=$((bar_width - filled))
    filled_bar=$(printf '%*s' "$filled" '' | tr ' ' '=')
    empty_bar=$(printf '%*s' "$empty" '')
    if [ "$PROGRESS_DRAWN" = true ]; then
        printf '\033[1A'
    fi
    printf '\r[%s%s] %3d%%\n\rETA: %s' "$filled_bar" "$empty_bar" "$percentage" "$eta"
    PROGRESS_DRAWN=true
}

convert_file() {
    local input="$1"
    local output="$2"
    local output_dir
    local existing_parent
    local parent
    local temporary_output="${output}.part.mov"
    local temporary_log="${temporary_output}.log"
    local temporary_progress="${temporary_output}.progress"
    local duration_us=0
    local current_us=0
    local start_time=0
    local elapsed_seconds=0
    local video_streams
    local audio_codecs
    PROGRESS_DRAWN=false

    output_dir=$(dirname "$output")
    existing_parent="$output_dir"
    while [ ! -e "$existing_parent" ]; do
        parent=$(dirname "$existing_parent")
        if [ "$parent" = "$existing_parent" ]; then
            break
        fi
        existing_parent="$parent"
    done
    if [ -e "$existing_parent" ] && [ ! -d "$existing_parent" ]; then
        echo " -> ERROR output path is inside a file: $existing_parent (source retained)"
        return 1
    fi
    if ! mkdir -p "$output_dir"; then
        echo " -> ERROR creating output directory: $output_dir (source retained)"
        return 1
    fi
    rm -f "$temporary_output"
    rm -f "$temporary_log"
    rm -f "$temporary_progress"

    echo "Processing: $input"
    video_streams=$(ffprobe -v error -select_streams v:0 \
        -show_entries stream=codec_type -of csv=p=0 "$input" 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo " -> ERROR probing $input (source retained)"
        return 1
    fi
    if [ -z "$video_streams" ]; then
        echo " -> Skipping non-video file: $input"
        return 0
    fi

    audio_codecs=$(ffprobe -v error -select_streams a \
        -show_entries stream=codec_name -of csv=p=0 "$input" 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo " -> ERROR probing audio in $input (source retained)"
        return 1
    fi
    if ! printf '%s\n' "$audio_codecs" | grep -Fxq "aac"; then
        echo " -> Skipping $input (no AAC audio)"
        return 0
    fi

    if [ -e "$input" ] && [ -e "$output" ] && [ "$input" -ef "$output" ]; then
        output="${output%.*}_pcm.mov"
        temporary_output="${output}.part.mov"
        temporary_log="${temporary_output}.log"
        temporary_progress="${temporary_output}.progress"
    fi

    CURRENT_OUTPUT="$temporary_output"
    if [ "$VERBOSE" = true ]; then
        ffmpeg -hide_banner -loglevel info -stats -i "$input" \
            -c:v copy -c:a pcm_s24le "$temporary_output" &
    else
        CURRENT_LOG="$temporary_log"
        CURRENT_PROGRESS="$temporary_progress"
        duration_us=$(ffprobe -v error -show_entries format=duration \
            -of default=noprint_wrappers=1:nokey=1 "$input" 2>/dev/null |
            awk '{ printf "%.0f", $1 * 1000000 }')
        [[ "$duration_us" =~ ^[0-9]+$ ]] || duration_us=0
        ffmpeg -hide_banner -loglevel error -nostats \
            -progress "$temporary_progress" -i "$input" \
            -c:v copy -c:a pcm_s24le "$temporary_output" 2>"$temporary_log" &
    fi
    FFMPEG_PID=$!
    if [ "$VERBOSE" = false ]; then
        start_time=$(date +%s)
        while kill -0 "$FFMPEG_PID" 2>/dev/null; do
            current_us=$(awk -F= '/^out_time_ms=/{ value=$2 } END {
                if (value ~ /^[0-9]+$/) print value
            }' "$temporary_progress" 2>/dev/null)
            [[ "$current_us" =~ ^[0-9]+$ ]] || current_us=0
            elapsed_seconds=$(( $(date +%s) - start_time ))
            draw_progress "$current_us" "$duration_us" "$elapsed_seconds"
            sleep 0.2
        done
    fi
    wait "$FFMPEG_PID"
    ffmpeg_status=$?
    FFMPEG_PID=""

    if [ "$ffmpeg_status" -eq 0 ]; then
        if [ "$VERBOSE" = false ]; then
            elapsed_seconds=$(( $(date +%s) - start_time ))
            draw_progress "$duration_us" "$duration_us" "$elapsed_seconds"
            echo
        fi
        mv -f "$temporary_output" "$output"
        CURRENT_OUTPUT=""
        CURRENT_LOG=""
        CURRENT_PROGRESS=""
        rm -f "$temporary_log"
        rm -f "$temporary_progress"
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
        CURRENT_PROGRESS=""
        rm -f "$temporary_progress"
        echo " -> ERROR converting $input (source retained)"
    fi
}

# Process each source path
for ((source_index = 0; source_index < SOURCE_COUNT; source_index++)); do
    SRC="${SOURCES[$source_index]}"

    if [ -d "$SRC" ]; then
        echo "=== Processing directory: $SRC (Recursive: $RECURSIVE) ==="
        SRC_CLEAN="${SRC%/}"
        FILES=()

        FIND_OPTS=()
        if [ "$RECURSIVE" = false ]; then
            FIND_OPTS+=("-maxdepth" "1")
        fi

        while IFS= read -r -d '' f; do
            FILES+=("$f")
        done < <(find "$SRC_CLEAN" "${FIND_OPTS[@]}" -type f -print0 | sort -z)

        for f in "${FILES[@]}"; do
            if [ ! -f "$f" ]; then
                echo "Skipping missing source: $f"
                continue
            fi
            if [ -n "$DEST" ]; then
                rel_path="${f#$SRC_CLEAN/}"
                out_file="${DEST%/}/${rel_path%.*}.mov"
            else
                out_file="${f%.*}.mov"
            fi
            convert_file "$f" "$out_file"
        done
        echo "=== Processing completed ==="

    elif [ -f "$SRC" ]; then
        filename=$(basename "$SRC")
        if [ -n "$DEST" ]; then
            out_file="${DEST%/}/${filename%.*}.mov"
        else
            out_file="${SRC%.*}.mov"
        fi
        convert_file "$SRC" "$out_file"
    else
        echo "Error: Source path '$SRC' is not a file or directory."
    fi
done

echo "=== Processing completed ==="
