# YT Lang Downloader

Download YouTube videos in any dubbed language. YouTube now offers multi-language audio dubs on many videos — this tool lets you pick one and download the video with that audio track.

## Features

- Detects all available dubbed audio tracks for a YouTube video
- Downloads video + selected language audio, merged into a single MP4
- Native macOS SwiftUI app with progress indicators
- CLI with interactive language picker and batch mode
- Python backend that's easy to extend

## Requirements

- macOS 13+
- Python 3.10+
- [yt-dlp](https://github.com/yt-dlp/yt-dlp) (nightly build required for multi-audio support)
- [ffmpeg](https://ffmpeg.org/)
- [rich](https://github.com/Textualize/rich) (for CLI UI)

### Install dependencies

```bash
brew install yt-dlp ffmpeg
pip3 install --pre -U "yt-dlp[default]"  # nightly needed for SABR/multi-audio
pip3 install rich
```

## Usage

### macOS App

Build and install the native app:

```bash
cd YTLangApp
swift build -c release

# Create .app bundle
APP="$HOME/Applications/YT Lang Downloader.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/YTLangApp "$APP/Contents/MacOS/"
cp ../ytlang.py "$APP/Contents/Resources/"
cp ../Info.plist "$APP/Contents/"
```

Then launch **YT Lang Downloader** from your Applications folder.

### CLI

```bash
# Interactive — prompts for language and quality
python3 ytlang.py "https://www.youtube.com/watch?v=VIDEO_ID"

# Direct
python3 ytlang.py "https://www.youtube.com/watch?v=VIDEO_ID" --lang de --quality 1080p -o ~/Downloads

# List available languages
python3 ytlang.py "https://www.youtube.com/watch?v=VIDEO_ID" --list-langs

# Batch mode
python3 ytlang.py --batch urls.txt --lang ja --quality 720p -o ~/Downloads
```

### As a Python library

```python
from ytlang import fetch_video_info, download

info = fetch_video_info("https://www.youtube.com/watch?v=VIDEO_ID")
for lang in info.languages:
    print(f"{lang.code}: {lang.name}")

path = download(
    url="https://www.youtube.com/watch?v=VIDEO_ID",
    language="de",
    quality="1080p",
    output_dir="./output",
)
```

## How it works

YouTube's multi-language audio tracks are served via SABR (Server ABR) streaming through the web player client. The stable release of yt-dlp doesn't support SABR yet, so the nightly build is required. The tool:

1. Scrapes the YouTube page to discover available audio track languages
2. Uses yt-dlp with `--extractor-args "youtube:player_client=default,web"` to access the multi-audio DASH/HLS streams
3. Downloads the best video stream + selected language audio stream
4. Merges them into a single MP4 via ffmpeg

## Project structure

```
ytlang.py                  # Python backend — core logic, CLI, importable functions
YTLangApp/
  Package.swift
  YTLangApp/
    App.swift              # SwiftUI app entry
    ContentView.swift      # UI layout and view model
    YTLangBackend.swift    # Swift ↔ Python bridge (calls ytlang.py via Process)
```
