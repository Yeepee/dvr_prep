# drv_prep

Bash script that prepares `.mp4` video files for **DaVinci Resolve on Linux**.
It replaces AAC audio with 24-bit PCM audio in a `.mov` container, without
re-encoding the video. The video is therefore copied without quality loss.

## Requirements

- Linux
- Bash
- [FFmpeg](https://ffmpeg.org/)

Check that FFmpeg is available:

```bash
ffmpeg -version
```

## Installation

Clone the repository and make the script executable:

```bash
git clone https://github.com/Yeepee/dvr_prep.git
cd dvr_prep
chmod +x drv_prep.sh
```

Optionally, create a symbolic link in `~/.local/bin` for easier execution:

```bash
mkdir -p ~/.local/bin && ln -s "$(pwd)/drv_prep.sh" ~/.local/bin/dvr_prep
```

Alternatively, install the latest version directly into `~/.local/bin`

```bash
mkdir -p ~/.local/bin && curl -fsSL https://raw.githubusercontent.com/Yeepee/dvr_prep/main/drv_prep.sh -o ~/.local/bin/dvr_prep && chmod +x ~/.local/bin/dvr_prep
```

Make sure `~/.local/bin` is included in your `PATH` to run `dvr_prep` from
any directory.

## Usage

```text
./drv_prep.sh [-r] [-d] [-v] [-h] <source> [destination]
```

- `<source>`: an `.mp4` file or a directory containing videos.
- `[destination]`: optional destination directory. If omitted, conversion takes
  place next to the source file.
- `-r`, `--recursive`: also process subdirectories.
- `-d`, `--delete-original`: delete the original `.mp4` file after successful
  conversion. By default, the original file is kept.
- `-v`, `--verbose`: display the complete FFmpeg output. By default, only
  essential messages, a progress bar, and an estimated time remaining are
  displayed. The progress bar is limited to 80 characters and ends with the
  percentage; the ETA is displayed below it. In verbose mode, no progress bar
  or ETA is added.
- `-h`, `--help`: display the help message.

### Examples

Convert the `.mp4` files in a directory:

```bash
./drv_prep.sh /path/to/footage
```

Convert recursively:

```bash
./drv_prep.sh --recursive /run/media/sdcard/DCIM
```

Convert to another directory:

```bash
./drv_prep.sh --recursive /run/media/sdcard/DCIM ~/Videos/MyProject
```

Display the complete FFmpeg output:

```bash
./drv_prep.sh --verbose /path/to/footage
```

The video is copied with `-c:v copy` and the audio is converted to `pcm_s24le`.
The original `.mp4` file is kept by default. Use `-d` or `--delete-original` to
delete it after a successful conversion. If an error occurs, the source file is
always kept.

Press `Ctrl+C` to stop the entire process, including the conversion currently
handled by FFmpeg. The source file is kept when processing is interrupted.
The output is written to a temporary file and moved into place only after a
successful conversion, so an interrupted conversion does not leave a partial
`.mov` file.

## License

This project is licensed under the [MIT License](LICENSE).
