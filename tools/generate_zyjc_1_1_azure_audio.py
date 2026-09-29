#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Generate staged zyjc_1_1 lesson audio with Azure Speech.

The program reads the authoring database in read-only mode and writes MP3 files
to an explicitly supplied staging directory. It never publishes over the
textbook assets and never modifies SQLite.
"""

from __future__ import annotations

import argparse
import csv
from dataclasses import dataclass
import html
from pathlib import Path
import re
import sqlite3
import subprocess
import sys
import tempfile
import time


PROJECT_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_DATABASE = PROJECT_ROOT / "database/textbook/zyjc_1_1/data.sqlite"
KEYCHAIN_SERVICE = "yzc_f.azure_speech.key"
REGION = "japaneast"
ENDPOINT = f"https://{REGION}.tts.speech.microsoft.com/cognitiveservices/v1"
OUTPUT_FORMAT = "audio-24khz-96kbitrate-mono-mp3"


@dataclass(frozen=True)
class Cast:
    label: str
    voice: str
    gender: str


@dataclass(frozen=True)
class Job:
    content_id: str
    lesson: str
    sort: int
    category: str
    role: str
    content: str
    spoken: str
    cast: Cast
    filename: str


ROLE_CASTS = {
    "ヤオ": Cast("林遥（15岁女生）", "ja-JP-MayuNeural", "女"),
    "葵": Cast("佐藤葵（同龄女生）", "ja-JP-ShioriNeural", "女"),
    "母": Cast("王静（成年女性）", "zh-CN-XiaoxiaoMultilingualNeural", "女"),
    "田中": Cast("田中真紀（成年女教师）", "ja-JP-NanamiNeural", "女"),
    "先生": Cast("田中真紀（成年女教师）", "ja-JP-NanamiNeural", "女"),
    "岡田": Cast("岡田（成年男性）", "ja-JP-NaokiNeural", "男"),
    "店員": Cast("店員（成年男性）", "de-DE-FlorianMultilingualNeural", "男"),
    "職員": Cast("学校職員（成年男性）", "ja-JP-DaichiNeural", "男"),
    "来場者": Cast("活動来場者（成年女性）", "en-US-AmandaMultilingualNeural", "女"),
}

NARRATORS = {
    1: Cast("正文女声", "en-US-EmmaMultilingualNeural", "女"),
    0: Cast("正文男声", "en-US-BrianMultilingualNeural", "男"),
}

PRONUNCIATION_REPLACEMENTS = (
    ("水葉女子高等学校", "みずは女子高等学校"),
    ("水葉女子高校", "みずは女子高校"),
    ("川辺中学校", "かわべ中学校"),
    ("王静", "ワン・ジン"),
    ("林海", "リン・ハイ"),
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "从只读 data.sqlite 生成 zyjc_1_1 Azure Speech 候选音频；"
            "不会覆盖教材 mp3，也不会修改数据库。"
        )
    )
    parser.add_argument(
        "--database",
        type=Path,
        default=DEFAULT_DATABASE,
        help="源 SQLite 路径，默认使用 zyjc_1_1/data.sqlite",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        required=True,
        help="候选音频暂存目录；禁止指向教材正式 mp3 目录",
    )
    parser.add_argument(
        "--delay",
        type=float,
        default=3.2,
        help="每次请求完成后的等待秒数，默认3.2秒以兼容免费层速率限制",
    )
    return parser.parse_args()


def readonly_database(path: Path) -> sqlite3.Connection:
    if not path.is_file() or path.is_symlink():
        raise ValueError(f"数据库必须是现有普通文件：{path}")
    connection = sqlite3.connect(path.resolve().as_uri() + "?mode=ro", uri=True)
    connection.row_factory = sqlite3.Row
    return connection


def lesson_number(lesson: str) -> int:
    if len(lesson) < 2 or lesson[0] != "l" or not lesson[1:].isdigit():
        raise ValueError(f"无法识别课次：{lesson!r}")
    return int(lesson[1:])


def spoken_text(content: str) -> str:
    result = content
    for source, replacement in PRONUNCIATION_REPLACEMENTS:
        result = result.replace(source, replacement)
    return result


def load_jobs(database: Path) -> list[Job]:
    connection = readonly_database(database)
    try:
        rows = connection.execute(
            """
            SELECT id, lesson, category, role, content, sort, phonetic
            FROM yzc_content
            WHERE media_type = 'text'
              AND content IS NOT NULL
              AND trim(content) <> ''
              AND category IN ('05', '06')
            ORDER BY CAST(substr(lesson, 2) AS INTEGER), sort
            """
        ).fetchall()
    finally:
        connection.close()

    jobs: list[Job] = []
    filenames: set[str] = set()
    for row in rows:
        lesson = str(row["lesson"])
        sort = int(row["sort"])
        category = str(row["category"])
        role = str(row["role"] or "")
        if category == "05":
            if role not in ROLE_CASTS:
                raise ValueError(f"未配置角色：{lesson} sort={sort} role={role!r}")
            cast = ROLE_CASTS[role]
        else:
            cast = NARRATORS[lesson_number(lesson) % 2]
            role = "正文"
        expected = str(row["phonetic"] or "")
        if not re.fullmatch(rf"l_{re.escape(lesson)}_[0-9]{{2}}\.mp3", expected):
            raise ValueError(f"现有音频引用格式不正确：{row['id']} {expected!r}")
        filename = expected
        if filename in filenames:
            raise ValueError(f"音频文件名重复：{filename}")
        filenames.add(filename)
        content = str(row["content"])
        jobs.append(
            Job(
                content_id=str(row["id"]),
                lesson=lesson,
                sort=sort,
                category=category,
                role=role,
                content=content,
                spoken=spoken_text(content),
                cast=cast,
                filename=filename,
            )
        )
    if len(jobs) != 230:
        raise ValueError(f"预期230条课文文本，实际读取{len(jobs)}条；停止生成")
    return jobs


def load_key() -> str:
    completed = subprocess.run(
        [
            "/usr/bin/security",
            "find-generic-password",
            "-s",
            KEYCHAIN_SERVICE,
            "-w",
        ],
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    key = completed.stdout.strip()
    if not key:
        raise ValueError(f"钥匙串项目 {KEYCHAIN_SERVICE!r} 没有可用密码")
    return key


def ssml(job: Job) -> bytes:
    text = html.escape(job.spoken, quote=False)
    if "Multilingual" in job.cast.voice:
        text = f'<lang xml:lang="ja-JP">{text}</lang>'
    document = (
        '<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" '
        'xml:lang="ja-JP">'
        f'<voice name="{html.escape(job.cast.voice, quote=True)}">{text}</voice>'
        "</speak>"
    )
    return document.encode("utf-8")


def synthesize(job: Job, key: str, target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        prefix=".azure-speech-header-",
        suffix=".txt",
        delete=False,
    ) as header_stream:
        header_path = Path(header_stream.name)
        header_stream.write(f"Ocp-Apim-Subscription-Key: {key}\n")
    with tempfile.NamedTemporaryFile(
        dir=target.parent,
        prefix=target.name + ".",
        suffix=".tmp",
        delete=False,
    ) as output_stream:
        temporary = Path(output_stream.name)
    try:
        completed = subprocess.run(
            [
                "/usr/bin/curl",
                "--fail-with-body",
                "--silent",
                "--show-error",
                "--retry",
                "5",
                "--retry-all-errors",
                "--retry-delay",
                "2",
                "--retry-max-time",
                "300",
                "--remove-on-error",
                "--request",
                "POST",
                "--header",
                "@" + str(header_path),
                "--header",
                "Content-Type: application/ssml+xml",
                "--header",
                f"X-Microsoft-OutputFormat: {OUTPUT_FORMAT}",
                "--header",
                "User-Agent: yzc-f-azure-textbook-audio",
                "--data-binary",
                "@-",
                "--output",
                str(temporary),
                ENDPOINT,
            ],
            input=ssml(job),
            check=False,
            capture_output=True,
        )
        if completed.returncode != 0:
            detail = completed.stderr.decode("utf-8", errors="replace").strip()
            raise RuntimeError(f"Azure 生成失败：{job.filename}: {detail}")
        if not temporary.is_file() or temporary.stat().st_size == 0:
            raise RuntimeError(f"Azure Speech 返回空音频：{job.filename}")
        temporary.replace(target)
    finally:
        header_path.unlink(missing_ok=True)
        temporary.unlink(missing_ok=True)


def write_manifest(path: Path, jobs: list[Job], states: dict[str, str]) -> None:
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, lineterminator="\n")
        writer.writerow(
            [
                "id",
                "lesson",
                "sort",
                "category",
                "role",
                "cast",
                "gender",
                "content",
                "spoken",
                "voice",
                "filename",
                "status",
            ]
        )
        for job in jobs:
            writer.writerow(
                [
                    job.content_id,
                    job.lesson,
                    job.sort,
                    job.category,
                    job.role,
                    job.cast.label,
                    job.cast.gender,
                    job.content,
                    job.spoken,
                    job.cast.voice,
                    job.filename,
                    states.get(job.filename, "pending"),
                ]
            )


def main() -> int:
    args = parse_args()
    database = args.database.resolve()
    output = args.output_dir.resolve()
    formal_audio = (database.parent / "mp3").resolve()
    if output == formal_audio or formal_audio in output.parents:
        raise ValueError(f"候选目录不能是教材正式 mp3 目录或其子目录：{formal_audio}")
    if args.delay < 0:
        raise ValueError("--delay 不能为负数")
    output.mkdir(parents=True, exist_ok=True)
    jobs = load_jobs(database)
    key = load_key()
    states: dict[str, str] = {}
    manifest = output / "manifest.csv"
    for index, job in enumerate(jobs, start=1):
        target = output / job.filename
        if target.is_file() and target.stat().st_size > 0:
            states[job.filename] = "existing"
            print(f"[{index:03d}/{len(jobs)}] 已存在 {job.filename}", flush=True)
            continue
        print(
            f"[{index:03d}/{len(jobs)}] 生成 {job.filename} "
            f"{job.role} -> {job.cast.voice}",
            flush=True,
        )
        synthesize(job, key, target)
        states[job.filename] = "generated"
        write_manifest(manifest, jobs, states)
        if args.delay:
            time.sleep(args.delay)
    write_manifest(manifest, jobs, states)
    print(f"候选音频生成完成：{output}（{len(jobs)}条）", flush=True)
    print("未修改数据库，未覆盖教材正式音频。", flush=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"错误：{error}", file=sys.stderr)
        raise SystemExit(1)
