#!/usr/bin/env python3
"""Download the game's music from Wikimedia Commons.

The music is not stored in the repository (it is ~150 MB). Every track is public domain / CC0
and listed in music/SOURCES.txt as:  <path in project> <TAB> <license> <TAB> <Commons page URL>.

Usage (from the project root):
    python tools/fetch_music.py               # download missing tracks
    python tools/fetch_music.py --force       # download everything again
    python tools/fetch_music.py --quality 0   # re-encode with ffmpeg to Vorbis q0 (~64 kbit/s, smaller builds)

Needs only Python 3.8+. ffmpeg is needed only for --quality. Then open the project in Godot —
it imports the new .ogg files by itself.
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.parse
import urllib.request

API = "https://commons.wikimedia.org/w/api.php"
UA = "DeviantMusicFetch/1.0 (game asset downloader; https://github.com/F-To-Pay)"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def read_sources():
    """[(project path, Commons file title)] from music/SOURCES.txt."""
    out = []
    with open(os.path.join(ROOT, "music", "SOURCES.txt"), encoding="utf-8") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 3 or not parts[0].startswith("music/"):
                continue
            url = parts[2].strip()
            title = urllib.parse.unquote(url.rsplit("/wiki/", 1)[-1]).replace("_", " ")
            out.append((parts[0].strip(), title))
    return out


def get_json(params):
    url = API + "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def resolve(titles):
    """Commons title -> download URL. FLAC originals are taken as Commons' own Ogg Vorbis transcode."""
    found = {}
    for i in range(0, len(titles), 20):
        chunk = titles[i:i + 20]
        data = get_json({"action": "query", "format": "json", "prop": "videoinfo",
                         "viprop": "url|derivatives|mime", "titles": "|".join(chunk)})
        q = data.get("query", {})
        back = {n["to"]: n["from"] for n in q.get("normalized", [])}
        for page in q.get("pages", {}).values():
            title = back.get(page.get("title"), page.get("title"))
            info = (page.get("videoinfo") or [None])[0]
            if not info:
                continue
            url = info["url"]
            if not url.lower().endswith(".ogg"):
                vorbis = [d for d in info.get("derivatives", [])
                          if "ogg" in d.get("type", "") and "vorbis" in d.get("type", "")]
                vorbis.sort(key=lambda d: int(d.get("bandwidth") or 0), reverse=True)
                if vorbis:
                    url = vorbis[0]["src"]
            found[title] = url
    return found


def download(url, dest):
    tmp = dest + ".part"
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=300) as r, open(tmp, "wb") as f:
        shutil.copyfileobj(r, f, 1 << 20)
    os.replace(tmp, dest)


def reencode(path, quality):
    tmp = path + ".tmp.ogg"
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", path, "-vn", "-map_metadata", "-1",
                    "-c:a", "libvorbis", "-q:a", str(quality), tmp], check=True)
    os.replace(tmp, path)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--force", action="store_true", help="download tracks that already exist too")
    ap.add_argument("--quality", type=float, default=None,
                    help="re-encode to Ogg Vorbis with this ffmpeg -q:a (e.g. 0 = ~64 kbit/s, 2 = ~96)")
    args = ap.parse_args()
    if args.quality is not None and shutil.which("ffmpeg") is None:
        sys.exit("--quality needs ffmpeg in PATH")

    tracks = read_sources()
    todo = [(p, t) for p, t in tracks if args.force or not os.path.exists(os.path.join(ROOT, p))]
    print(f"{len(tracks)} tracks, {len(todo)} to download")
    if not todo:
        return
    urls = resolve([t for _, t in todo])
    failed = []
    for n, (path, title) in enumerate(todo, 1):
        url = urls.get(title)
        dest = os.path.join(ROOT, path)
        if not url:
            print(f"[{n}/{len(todo)}] NOT FOUND on Commons: {title}")
            failed.append(path)
            continue
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        print(f"[{n}/{len(todo)}] {path}")
        try:
            download(url, dest)
            if args.quality is not None:
                reencode(dest, args.quality)
        except Exception as e:  # noqa: BLE001 — сеть/ffmpeg: сообщить и идти дальше
            print(f"    failed: {e}")
            failed.append(path)
        time.sleep(0.5)   # be polite to Wikimedia
    if failed:
        print(f"\n{len(failed)} track(s) failed — run again later: " + ", ".join(failed))
        sys.exit(1)
    print("\nDone. Open the project in Godot to import the music.")


if __name__ == "__main__":
    main()
