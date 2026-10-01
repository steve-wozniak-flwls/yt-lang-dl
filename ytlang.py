#!/usr/bin/env python3
"""
ytlang — Download YouTube videos in any dubbed language.

Usage:
    python ytlang.py <url> [--lang CODE] [--quality QUALITY] [--output DIR]
    python ytlang.py <url>                      # interactive language/quality picker
    python ytlang.py --batch urls.txt --lang de  # batch mode

Requires: yt-dlp, ffprobe (from ffmpeg)
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path

from rich.console import Console
from rich.panel import Panel
from rich.progress import (
    BarColumn,
    DownloadColumn,
    Progress,
    SpinnerColumn,
    TextColumn,
    TimeRemainingColumn,
    TransferSpeedColumn,
)
from rich.prompt import Prompt
from rich.table import Table

console = Console()

# ---------------------------------------------------------------------------
# Data
# ---------------------------------------------------------------------------

@dataclass
class AudioTrack:
    code: str
    name: str
    is_default: bool = False

@dataclass
class VideoInfo:
    video_id: str
    title: str
    duration: int
    thumbnail: str
    languages: list[AudioTrack] = field(default_factory=list)


# ---------------------------------------------------------------------------
# Core functions — import these if you want to extend the tool
# ---------------------------------------------------------------------------

def extract_video_id(url: str) -> str:
    """Pull the 11-char video ID out of any common YouTube URL form."""
    m = re.search(r'(?:v=|youtu\.be/|/shorts/)([a-zA-Z0-9_-]{11})', url)
    if not m:
        raise ValueError(f"Could not find a YouTube video ID in: {url}")
    return m.group(1)


def fetch_video_info(url: str) -> VideoInfo:
    """Fetch title, duration, thumbnail, and available audio languages."""
    video_id = extract_video_id(url)

    req = urllib.request.Request(
        f"https://www.youtube.com/watch?v={video_id}",
        headers={
            "User-Agent": (
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
            ),
            "Accept-Language": "en-US,en;q=0.9",
        },
    )

    with urllib.request.urlopen(req, timeout=15) as resp:
        html = resp.read().decode("utf-8")

    match = re.search(r'ytInitialPlayerResponse\s*=\s*(\{.*?\});', html)
    if not match:
        raise RuntimeError("Could not parse YouTube player response")

    player = json.loads(match.group(1))
    details = player.get("videoDetails", {})
    streaming = player.get("streamingData", {})

    tracks: dict[str, AudioTrack] = {}
    for fmt in streaming.get("adaptiveFormats", []):
        at = fmt.get("audioTrack")
        if at:
            code = at["id"].split(".")[0]
            if code not in tracks:
                tracks[code] = AudioTrack(
                    code=code,
                    name=at.get("displayName", code),
                    is_default=at.get("audioIsDefault", False),
                )

    if not tracks:
        tracks["en"] = AudioTrack(code="en", name="English (Original)", is_default=True)

    return VideoInfo(
        video_id=video_id,
        title=details.get("title", "Unknown"),
        duration=int(details.get("lengthSeconds", 0)),
        thumbnail=details.get("thumbnail", {}).get("thumbnails", [{}])[-1].get("url", ""),
        languages=sorted(tracks.values(), key=lambda t: (not t.is_default, t.name)),
    )


def download(
    url: str,
    language: str = "en",
    quality: str = "1080p",
    output_dir: str | Path = ".",
    title: str | None = None,
    on_progress: callable | None = None,
) -> Path:
    """
    Download a YouTube video with the given dubbed audio language.

    Args:
        url:         YouTube URL
        language:    ISO language code (e.g. 'de', 'ja', 'pt')
        quality:     '1080p', '720p', '480p', or '360p'
        output_dir:  directory to save the file in
        title:       optional title for the filename (auto-fetched if None)
        on_progress: callback(percent: float) called during download

    Returns:
        Path to the downloaded file.
    """
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    if title is None:
        info = fetch_video_info(url)
        title = info.title

    safe_title = re.sub(r'[^\w\s-]', '', title).strip()[:80]
    height = quality.replace("p", "")
    filename = f"{safe_title} [{language.upper()} {quality}].mp4"
    output_path = output_dir / filename

    if output_path.exists():
        output_path.unlink()

    cmd = [
        "yt-dlp",
        "--extractor-args", "youtube:player_client=default,web",
        "--newline",
        "-f", f"bv*[height<={height}]+ba[language={language}]/b[language={language}]/bv*[height<={height}]+ba/b",
        "--merge-output-format", "mp4",
        "-o", str(output_path),
        url,
    ]

    proc = subprocess.Popen(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
    )

    last_error = None
    for line in proc.stdout:
        line = line.strip()
        pct = re.search(r'\[download\]\s+([\d.]+)%', line)
        if pct and on_progress:
            on_progress(float(pct.group(1)))
        if "ERROR" in line:
            last_error = line

    proc.wait()

    if not output_path.exists():
        raise RuntimeError(last_error or "Download failed — no output file produced.")

    return output_path


# ---------------------------------------------------------------------------
# Terminal UI helpers
# ---------------------------------------------------------------------------

def format_duration(secs: int) -> str:
    m, s = divmod(secs, 60)
    h, m = divmod(m, 60)
    if h:
        return f"{h}:{m:02d}:{s:02d}"
    return f"{m}:{s:02d}"


def print_video_info(info: VideoInfo) -> None:
    table = Table.grid(padding=(0, 2))
    table.add_row("[bold]Title[/]", info.title)
    table.add_row("[bold]Duration[/]", format_duration(info.duration))
    table.add_row("[bold]Languages[/]", f"{len(info.languages)} available")
    console.print(Panel(table, title="[bold]Video Info[/]", border_style="blue"))


def pick_language(languages: list[AudioTrack]) -> str:
    table = Table(show_header=True, header_style="bold", box=None, padding=(0, 2))
    table.add_column("#", style="dim", width=4)
    table.add_column("Code", width=8)
    table.add_column("Language")

    for i, track in enumerate(languages, 1):
        suffix = " [green](original)[/]" if track.is_default else ""
        table.add_row(str(i), track.code, track.name + suffix)

    console.print()
    console.print(table)
    console.print()

    choice = Prompt.ask(
        "Pick a language [dim](number or code)[/]",
        default="1",
    )

    if choice.isdigit():
        idx = int(choice) - 1
        if 0 <= idx < len(languages):
            return languages[idx].code
    for t in languages:
        if t.code == choice:
            return t.code

    console.print(f"[yellow]Unknown choice '{choice}', defaulting to first language.[/]")
    return languages[0].code


def pick_quality() -> str:
    options = ["1080p", "720p", "480p", "360p"]
    choice = Prompt.ask(
        "Pick quality",
        choices=options,
        default="1080p",
    )
    return choice


def download_with_ui(url: str, language: str, quality: str, output_dir: Path, title: str) -> Path:
    with Progress(
        SpinnerColumn(),
        TextColumn("[bold blue]{task.description}"),
        BarColumn(bar_width=40),
        TextColumn("[progress.percentage]{task.percentage:>5.1f}%"),
        TimeRemainingColumn(),
        console=console,
    ) as progress:
        task = progress.add_task("Downloading...", total=100)

        def on_progress(pct: float):
            progress.update(task, completed=pct)

        path = download(
            url=url,
            language=language,
            quality=quality,
            output_dir=output_dir,
            title=title,
            on_progress=on_progress,
        )

        progress.update(task, completed=100, description="Done")

    return path


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="ytlang",
        description="Download YouTube videos in any dubbed language.",
    )
    p.add_argument("url", nargs="?", help="YouTube URL")
    p.add_argument("--lang", "-l", help="Language code (e.g. de, ja, fr). Omit to pick interactively.")
    p.add_argument("--quality", "-q", default="1080p", help="Video quality: 1080p, 720p, 480p, 360p (default: 1080p)")
    p.add_argument("--output", "-o", default=".", help="Output directory (default: current dir)")
    p.add_argument("--batch", "-b", help="Path to a text file with one URL per line")
    p.add_argument("--list-langs", action="store_true", help="Just list available languages, don't download")
    p.add_argument("--json", action="store_true", help="Output machine-readable JSON (for GUI integration)")
    p.add_argument("--json-progress", action="store_true", help="Emit JSON progress lines to stdout (for GUI integration)")
    return p


def main():
    parser = build_parser()
    args = parser.parse_args()

    # JSON mode for GUI integration
    if args.json and args.list_langs and args.url:
        info = fetch_video_info(args.url)
        print(json.dumps({
            "title": info.title,
            "duration": info.duration,
            "thumbnail": info.thumbnail,
            "video_id": info.video_id,
            "languages": [
                {"code": t.code, "name": t.name, "is_default": t.is_default}
                for t in info.languages
            ],
        }))
        return

    if args.json_progress and args.url and args.lang:
        info = fetch_video_info(args.url)
        def on_progress(pct: float):
            print(json.dumps({"progress": pct}), flush=True)
        try:
            path = download(
                url=args.url,
                language=args.lang,
                quality=args.quality,
                output_dir=Path(args.output),
                title=info.title,
                on_progress=on_progress,
            )
            print(json.dumps({"file": str(path)}), flush=True)
        except RuntimeError as e:
            print(json.dumps({"error": str(e)}), flush=True)
            sys.exit(1)
        return

    if not args.url and not args.batch:
        url = Prompt.ask("[bold]YouTube URL[/]")
    elif args.batch:
        batch_path = Path(args.batch)
        if not batch_path.exists():
            console.print(f"[red]Batch file not found: {batch_path}[/]")
            sys.exit(1)
        urls = [line.strip() for line in batch_path.read_text().splitlines() if line.strip() and not line.startswith("#")]
        console.print(f"[bold]Batch mode:[/] {len(urls)} URLs")
        for i, url in enumerate(urls, 1):
            console.rule(f"[bold]{i}/{len(urls)}[/]")
            try:
                info = fetch_video_info(url)
                console.print(f"  [bold]{info.title}[/]")
                lang = args.lang or info.languages[0].code
                path = download_with_ui(url, lang, args.quality, Path(args.output), info.title)
                console.print(f"  [green]Saved:[/] {path}")
            except Exception as e:
                console.print(f"  [red]Failed:[/] {e}")
        return
    else:
        url = args.url

    with console.status("[bold blue]Fetching video info...", spinner="dots"):
        info = fetch_video_info(url)

    print_video_info(info)

    if args.list_langs:
        table = Table(title="Available Languages", show_header=True, header_style="bold")
        table.add_column("Code", width=10)
        table.add_column("Language")
        table.add_column("Default", width=10)
        for t in info.languages:
            table.add_row(t.code, t.name, "yes" if t.is_default else "")
        console.print(table)
        return

    if args.lang:
        language = args.lang
        codes = {t.code for t in info.languages}
        if language not in codes:
            console.print(f"[red]Language '{language}' not available for this video.[/]")
            console.print(f"[dim]Available: {', '.join(sorted(codes))}[/]")
            sys.exit(1)
    else:
        language = pick_language(info.languages)

    if not args.lang and not args.url:
        quality = pick_quality()
    else:
        quality = args.quality

    lang_name = next((t.name for t in info.languages if t.code == language), language)
    console.print()
    console.print(f"  [bold]Language:[/] {lang_name} ({language})")
    console.print(f"  [bold]Quality:[/]  {quality}")
    console.print()

    try:
        path = download_with_ui(url, language, quality, Path(args.output), info.title)
        size_mb = path.stat().st_size / (1024 * 1024)
        console.print()
        console.print(Panel(
            f"[green bold]Download complete[/]\n\n"
            f"  [bold]File:[/]  {path.name}\n"
            f"  [bold]Size:[/]  {size_mb:.0f} MB\n"
            f"  [bold]Path:[/]  {path}",
            border_style="green",
        ))
    except RuntimeError as e:
        console.print(f"\n[red bold]Error:[/] {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
