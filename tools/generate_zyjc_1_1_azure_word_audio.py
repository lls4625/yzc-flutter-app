#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Generate staged Azure Speech audio for every zyjc_1_1 word."""

from __future__ import annotations

import argparse
from concurrent.futures import Future, ThreadPoolExecutor, as_completed
import csv
from dataclasses import dataclass
import html
from pathlib import Path
import re
import sqlite3
import subprocess
import tempfile


PROJECT_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_DATABASE = PROJECT_ROOT / "database/textbook/zyjc_1_1/data.sqlite"
KEYCHAIN_SERVICE = "yzc_f.azure_speech.key"
REGION = "japaneast"
ENDPOINT = f"https://{REGION}.tts.speech.microsoft.com/cognitiveservices/v1"
OUTPUT_FORMAT = "audio-24khz-96kbitrate-mono-mp3"
FEMALE_VOICE = "ja-JP-NanamiNeural"
MALE_VOICE = "ja-JP-KeitaNeural"


@dataclass(frozen=True)
class Job:
    ordinal: int
    word_id: str
    lesson: str
    sort: int
    kana: str
    spoken: str
    voice: str
    gender: str
    phonetic_before: str
    filename: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="从只读数据库生成1,076条 Azure 单词候选音频；不覆盖正式文件。"
    )
    parser.add_argument("--database", type=Path, default=DEFAULT_DATABASE)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--workers", type=int, default=4)
    return parser.parse_args()


def readonly_database(path: Path) -> sqlite3.Connection:
    if not path.is_file() or path.is_symlink():
        raise ValueError(f"数据库必须是现有普通文件：{path}")
    connection = sqlite3.connect(path.resolve().as_uri() + "?mode=ro", uri=True)
    connection.row_factory = sqlite3.Row
    return connection


def normalize_kana(kana: str) -> str:
    spoken = kana.strip().replace("～", "").replace("/", "、")
    spoken = re.sub(r"\s+", " ", spoken).strip(" 、")
    if not spoken:
        raise ValueError(f"kana 去除占位符后为空：{kana!r}")
    return spoken


def load_jobs(database: Path) -> list[Job]:
    connection = readonly_database(database)
    try:
        rows = connection.execute(
            """
            SELECT id, lesson, sort, kana, phonetic
            FROM yzc_words
            ORDER BY CAST(substr(lesson, 2) AS INTEGER), sort, id
            """
        ).fetchall()
    finally:
        connection.close()
    if len(rows) != 1076:
        raise ValueError(f"预期1,076条单词，实际读取{len(rows)}条；停止生成")

    jobs: list[Job] = []
    filenames: set[str] = set()
    for ordinal, row in enumerate(rows, start=1):
        word_id = str(row["id"])
        lesson = str(row["lesson"])
        sort = int(row["sort"])
        kana = str(row["kana"] or "")
        if not kana.strip():
            raise ValueError(f"缺少 kana：{word_id}")
        expected = f"w_{lesson}_{sort:02d}.mp3"
        phonetic_before = str(row["phonetic"] or "")
        if phonetic_before and phonetic_before != expected:
            raise ValueError(
                f"现有单词音频引用与命名规则不一致：{word_id} "
                f"{phonetic_before!r} != {expected!r}"
            )
        if expected in filenames:
            raise ValueError(f"单词音频文件名重复：{expected}")
        filenames.add(expected)
        female = ordinal % 2 == 1
        jobs.append(
            Job(
                ordinal=ordinal,
                word_id=word_id,
                lesson=lesson,
                sort=sort,
                kana=kana,
                spoken=normalize_kana(kana),
                voice=FEMALE_VOICE if female else MALE_VOICE,
                gender="女" if female else "男",
                phonetic_before=phonetic_before,
                filename=expected,
            )
        )
    return jobs


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
        raise ValueError(f"钥匙串项目 {KEYCHAIN_SERVICE!r} 没有可用密码")
    return key


def ssml(job: Job) -> bytes:
    document = (
        '<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" '
        'xml:lang="ja-JP">'
        f'<voice name="{job.voice}">{html.escape(job.spoken, quote=False)}</voice>'
        "</speak>"
    )
    return document.encode("utf-8")


def synthesize(job: Job, key: str, target: Path) -> str:
    if target.is_file() and target.stat().st_size > 0:
        return "existing"
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
                "User-Agent: yzc-f-azure-word-audio",
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
        return "generated"
    finally:
        header_path.unlink(missing_ok=True)
        temporary.unlink(missing_ok=True)


def write_manifest(path: Path, jobs: list[Job], states: dict[str, str]) -> None:
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, lineterminator="\n")
        writer.writerow(
            [
                "ordinal",
                "id",
                "lesson",
                "sort",
                "kana",
                "spoken",
                "gender",
                "voice",
                "phonetic_before",
                "filename",
                "status",
            ]
        )
        for job in jobs:
            writer.writerow(
                [
                    job.ordinal,
                    job.word_id,
                    job.lesson,
                    job.sort,
                    job.kana,
                    job.spoken,
                    job.gender,
                    job.voice,
                    job.phonetic_before,
                    job.filename,
                    states.get(job.filename, "pending"),
                ]
            )


def main() -> None:
    args = parse_args()
    database = args.database.resolve()
    output = args.output_dir.resolve()
    formal_audio = (database.parent / "mp3").resolve()
    if output == formal_audio or formal_audio in output.parents:
        raise ValueError(f"候选目录不能是正式 mp3 目录或其子目录：{formal_audio}")
    if args.workers < 1 or args.workers > 8:
        raise ValueError("--workers 必须在1到8之间")
    output.mkdir(parents=True, exist_ok=True)
    jobs = load_jobs(database)
    key = load_key()
    states: dict[str, str] = {}
    manifest = output / "manifest.csv"
    future_jobs: dict[Future[str], Job] = {}
    with ThreadPoolExecutor(max_workers=args.workers) as executor:
        for job in jobs:
            future_jobs[executor.submit(synthesize, job, key, output / job.filename)] = job
        completed_count = 0
        try:
            for future in as_completed(future_jobs):
                job = future_jobs[future]
                state = future.result()
                states[job.filename] = state
                completed_count += 1
                print(
                    f"[{completed_count:04d}/{len(jobs)}] {state} {job.filename} "
                    f"{job.gender} -> {job.voice}",
                    flush=True,
                )
                write_manifest(manifest, jobs, states)
        except BaseException:
            for future in future_jobs:
                future.cancel()
            raise
    write_manifest(manifest, jobs, states)
    print(f"Azure 单词候选生成完成：{output}（{len(jobs)}条）", flush=True)
    print("未修改数据库，未覆盖正式单词音频。", flush=True)


if __name__ == "__main__":
    main()
