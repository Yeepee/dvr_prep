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

## Usage

```text
./drv_prep.sh [-r] [-h] <source> [destination]
```

- `<source>`: an `.mp4` file or a directory containing videos.
- `[destination]`: optional destination directory. If omitted, conversion takes
  place next to the source file.
- `-r`: also process subdirectories.
- `-h`: display the help message.

### Examples

Convert the `.mp4` files in a directory:

```bash
./drv_prep.sh /path/to/footage
```

Convert recursively:

```bash
./drv_prep.sh -r /run/media/sdcard/DCIM
```

Convert to another directory:

```bash
./drv_prep.sh -r /run/media/sdcard/DCIM ~/Videos/MyProject
```

The video is copied with `-c:v copy` and the audio is converted to `pcm_s24le`.
The original `.mp4` file is deleted only if conversion succeeds; if an error
occurs, it is kept.

## License

No license has been defined for this project yet.
