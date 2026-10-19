#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Regenerate one ryshxgs textbook's word audio with Azure Speech.

The tool is deliberately book-scoped: it creates and validates a complete set of
candidates before backing up and replacing the MP3 files referenced by yzc_words.
Azure credentials are read from the macOS Keychain and are never persisted.
"""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import csv
import hashlib
import html
import json
from pathlib import Path
import re
import shutil
import sqlite3
import subprocess
import time
import urllib.error
import urllib.request


ROOT = Path("/Users/javalee/work/proj/yzc_f")
APP = ROOT / "yzc_v3.1"
TEXTBOOK = APP / "database/textbook"
KEYCHAIN_SERVICE = "yzc_f.azure_speech.key"
REGION = "japaneast"
ENDPOINT = f"https://{REGION}.tts.speech.microsoft.com/cognitiveservices/v1"
OUTPUT_FORMAT = "audio-24khz-96kbitrate-mono-mp3"
FFPROBE = Path("/opt/homebrew/bin/ffprobe")
FEMALE_VOICE = "ja-JP-NanamiNeural"
MALE_VOICE = "ja-JP-DaichiNeural"
BOOKS = ("ryshxgs_1_1", "ryshxgs_1_2", "ryshxgs_2_1", "ryshxgs_2_2")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write("\n")


def load_key() -> str:
    completed = subprocess.run(
        ["/usr/bin/security", "find-generic-password", "-s", KEYCHAIN_SERVICE, "-w"],
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    key = completed.stdout.strip()
    if not key:
        raise RuntimeError(f"钥匙串项目 {KEYCHAIN_SERVICE!r} 没有可用密码")
    return key


def spoken_text(kana: str) -> str:
    value = re.sub(r"\s+", "", kana.strip())
    value = value.replace("～", "").replace("〜", "").replace("/", "、")
    if not value:
        raise RuntimeError(f"规范化后没有可发音内容：{kana!r}")
    return value


def load_rows(book: str) -> list[dict[str, object]]:
    db_path = TEXTBOOK / book / "data.sqlite"
    connection = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    connection.row_factory = sqlite3.Row
    try:
        raw_rows = connection.execute(
            """
            SELECT id, lesson, sort, word, kana, phonetic
            FROM yzc_words
            ORDER BY lesson, sort, id
            """
        ).fetchall()
    finally:
        connection.close()

    rows: list[dict[str, object]] = []
    seen_lesson_sort: set[tuple[str, int]] = set()
    seen_filenames: set[str] = set()
    for raw in raw_rows:
        row = dict(raw)
        lesson = str(row["lesson"] or "").strip()
        sort = int(row["sort"])
        kana = str(row["kana"] or "").strip()
        phonetic = str(row["phonetic"] or "").strip()
        filename = Path(phonetic).name
        if not lesson or not kana or not phonetic:
            raise RuntimeError(f"单词记录缺少 lesson/kana/phonetic：{row}")
        if phonetic != filename or not filename.endswith(".mp3"):
            raise RuntimeError(f"不安全或非 MP3 的 phonetic：{phonetic!r}")
        key = (lesson, sort)
        if key in seen_lesson_sort:
            raise RuntimeError(f"同一课存在重复 sort：{lesson} / {sort}")
        if filename in seen_filenames:
            raise RuntimeError(f"多个单词共用同一音频文件：{filename}")
        seen_lesson_sort.add(key)
        seen_filenames.add(filename)
        gender = "女" if sort % 2 == 1 else "男"
        row.update(
            {
                "lesson": lesson,
                "sort": sort,
                "kana": kana,
                "spoken": spoken_text(kana),
                "filename": filename,
                "gender": gender,
                "voice": FEMALE_VOICE if gender == "女" else MALE_VOICE,
            }
        )
        rows.append(row)
    if not rows:
        raise RuntimeError(f"{book} 没有单词记录")
    return rows


def ssml_for(row: dict[str, object]) -> bytes:
    voice = html.escape(str(row["voice"]), quote=True)
    text = html.escape(str(row["spoken"]))
    return (
        "<speak version='1.0' xml:lang='ja-JP'>"
        f"<voice name='{voice}'>"
        f"<prosody rate='+0%' pitch='+0Hz' volume='+0%'>{text}</prosody>"
        "</voice></speak>"
    ).encode("utf-8")


def synthesize(row: dict[str, object], destination: Path, api_key: str) -> None:
    request = urllib.request.Request(
        ENDPOINT,
        data=ssml_for(row),
        method="POST",
        headers={
            "Ocp-Apim-Subscription-Key": api_key,
            "Content-Type": "application/ssml+xml",
            "X-Microsoft-OutputFormat": OUTPUT_FORMAT,
            "User-Agent": "yzc-f-word-audio-generator",
        },
    )
    last_error: Exception | None = None
    for attempt in range(1, 6):
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                audio = response.read()
            if len(audio) < 1024 or not audio.startswith((b"ID3", b"\xff\xf3", b"\xff\xfb")):
                raise RuntimeError(f"Azure 返回内容不是有效 MP3（{len(audio)} 字节）")
            destination.parent.mkdir(parents=True, exist_ok=True)
            with destination.open("wb") as stream:
                stream.write(audio)
            return
        except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError, RuntimeError) as error:
            last_error = error
            if attempt == 5:
                break
            time.sleep(min(2 ** attempt, 16))
    raise RuntimeError(
        f"生成失败：{row['lesson']} #{row['sort']} {row['kana']} / {row['voice']} / {last_error}"
    )


def inspect_audio(path: Path) -> dict[str, object]:
    completed = subprocess.run(
        [
            str(FFPROBE),
            "-v", "error",
            "-select_streams", "a:0",
            "-show_entries", "stream=codec_name,sample_rate,channels,bit_rate,duration",
            "-of", "json",
            str(path),
        ],
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    streams = json.loads(completed.stdout).get("streams", [])
    if len(streams) != 1:
        raise RuntimeError(f"无法识别唯一音频流：{path}")
    stream = streams[0]
    if stream.get("codec_name") != "mp3":
        raise RuntimeError(f"音频编码不是 MP3：{path} / {stream}")
    if int(stream.get("sample_rate", 0)) != 24000 or int(stream.get("channels", 0)) != 1:
        raise RuntimeError(f"音频规格不是 24kHz 单声道：{path} / {stream}")
    if int(stream.get("bit_rate", 0)) < 90000:
        raise RuntimeError(f"音频码率低于目标：{path} / {stream}")
    return stream


def manifest_rows(rows: list[dict[str, object]], directory: Path) -> list[dict[str, object]]:
    result: list[dict[str, object]] = []
    for row in rows:
        path = directory / str(row["filename"])
        result.append(
            {
                "book": row["book"],
                "id": row["id"],
                "lesson": row["lesson"],
                "sort": row["sort"],
                "word": row["word"],
                "kana": row["kana"],
                "spoken": row["spoken"],
                "gender": row["gender"],
                "voice": row["voice"],
                "phonetic": row["phonetic"],
                "filename": row["filename"],
                "bytes": path.stat().st_size,
                "sha256": sha256_file(path),
            }
        )
    return result


def write_manifest(path: Path, rows: list[dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fields = list(rows[0])
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--book", required=True, choices=BOOKS)
    parser.add_argument("--work-dir", type=Path, required=True)
    parser.add_argument("--workers", type=int, default=6)
    args = parser.parse_args()

    book = args.book
    work_dir = args.work_dir.resolve()
    book_dir = TEXTBOOK / book
    formal_dir = book_dir / "mp3"
    candidate_dir = work_dir / "candidates" / book
    backup_dir = work_dir / "backups" / book / "mp3"
    manifest_dir = work_dir / "manifests"
    receipt_path = work_dir / "receipts" / f"{book}.json"
    if candidate_dir.exists() or backup_dir.exists() or receipt_path.exists():
        raise RuntimeError(f"工作目录中已存在 {book} 的输出，拒绝混用：{work_dir}")
    if not FFPROBE.is_file():
        raise RuntimeError(f"找不到 ffprobe：{FFPROBE}")

    rows = load_rows(book)
    for row in rows:
        row["book"] = book
        source = formal_dir / str(row["filename"])
        if not source.is_file() or source.stat().st_size == 0:
            raise RuntimeError(f"正式音频不存在或为空：{source}")

    print(f"[{book}] 读取 {len(rows)} 条单词，开始 Azure 生成", flush=True)
    api_key = load_key()
    failures: list[str] = []
    completed_count = 0
    with ThreadPoolExecutor(max_workers=args.workers) as executor:
        future_rows = {
            executor.submit(
                synthesize,
                row,
                candidate_dir / str(row["filename"]),
                api_key,
            ): row
            for row in rows
        }
        for future in as_completed(future_rows):
            row = future_rows[future]
            try:
                future.result()
            except Exception as error:
                failures.append(str(error))
            completed_count += 1
            if completed_count % 50 == 0 or completed_count == len(rows):
                print(f"[{book}] Azure 进度 {completed_count}/{len(rows)}，失败 {len(failures)}", flush=True)
    if failures:
        write_json(work_dir / "failures" / f"{book}.json", failures)
        raise RuntimeError(f"{book} 有 {len(failures)} 个候选生成失败，未发布")

    print(f"[{book}] 开始检查候选音频规格", flush=True)
    inspected = 0
    with ThreadPoolExecutor(max_workers=args.workers) as executor:
        futures = [
            executor.submit(inspect_audio, candidate_dir / str(row["filename"]))
            for row in rows
        ]
        for future in as_completed(futures):
            future.result()
            inspected += 1
            if inspected % 100 == 0 or inspected == len(rows):
                print(f"[{book}] 规格检查 {inspected}/{len(rows)}", flush=True)

    before = manifest_rows(rows, formal_dir)
    after = manifest_rows(rows, candidate_dir)
    write_manifest(manifest_dir / f"{book}-before.csv", before)
    write_manifest(manifest_dir / f"{book}-after.csv", after)

    backup_dir.mkdir(parents=True, exist_ok=False)
    shutil.copy2(book_dir / "data.sqlite", work_dir / "backups" / book / "data.sqlite")
    for row in rows:
        filename = str(row["filename"])
        shutil.copy2(formal_dir / filename, backup_dir / filename)

    published: list[str] = []
    try:
        for row in rows:
            filename = str(row["filename"])
            shutil.copy2(candidate_dir / filename, formal_dir / filename)
            published.append(filename)
    except Exception:
        for filename in published:
            shutil.copy2(backup_dir / filename, formal_dir / filename)
        raise

    mismatches: list[str] = []
    for row in rows:
        filename = str(row["filename"])
        if sha256_file(formal_dir / filename) != sha256_file(candidate_dir / filename):
            mismatches.append(filename)
    if mismatches:
        for row in rows:
            filename = str(row["filename"])
            shutil.copy2(backup_dir / filename, formal_dir / filename)
        raise RuntimeError(f"发布后哈希不一致，已回退：{mismatches[:5]}")

    receipt = {
        "book": book,
        "status": "published",
        "word_count": len(rows),
        "female_count": sum(1 for row in rows if row["gender"] == "女"),
        "male_count": sum(1 for row in rows if row["gender"] == "男"),
        "female_voice": FEMALE_VOICE,
        "male_voice": MALE_VOICE,
        "output_format": OUTPUT_FORMAT,
        "database_modified": False,
        "before_bytes": sum(int(row["bytes"]) for row in before),
        "after_bytes": sum(int(row["bytes"]) for row in after),
        "manifest_before": str(manifest_dir / f"{book}-before.csv"),
        "manifest_after": str(manifest_dir / f"{book}-after.csv"),
        "backup_dir": str(work_dir / "backups" / book),
    }
    write_json(receipt_path, receipt)
    print(
        f"[{book}] 已发布 {len(rows)} 个音频：女声 {receipt['female_count']}，男声 {receipt['male_count']}",
        flush=True,
    )


if __name__ == "__main__":
    main()
