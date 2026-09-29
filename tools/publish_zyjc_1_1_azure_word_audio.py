#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Publish staged zyjc_1_1 Azure word audio with database-safe rollback."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
import shutil
import sqlite3
import tempfile


PROJECT_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_DATABASE = PROJECT_ROOT / "database/textbook/zyjc_1_1/data.sqlite"


@dataclass(frozen=True)
class Entry:
    word_id: str
    filename: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="备份旧版单词音频和数据库后发布1,076条 Azure 单词音频。"
    )
    parser.add_argument("--source-dir", type=Path, required=True)
    parser.add_argument("--backup-dir", type=Path, required=True)
    parser.add_argument("--database", type=Path, default=DEFAULT_DATABASE)
    return parser.parse_args()


def load_entries(database: Path) -> list[Entry]:
    connection = sqlite3.connect(database.resolve().as_uri() + "?mode=ro", uri=True)
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
        raise ValueError(f"预期1,076条单词，实际读取{len(rows)}条")
    entries: list[Entry] = []
    filenames: set[str] = set()
    for word_id, lesson, sort, kana, phonetic in rows:
        if not str(kana or "").strip():
            raise ValueError(f"缺少 kana：{word_id}")
        filename = f"w_{lesson}_{int(sort):02d}.mp3"
        if phonetic and str(phonetic) != filename:
            raise ValueError(f"现有 phonetic 与规则不一致：{word_id} {phonetic!r}")
        if filename in filenames:
            raise ValueError(f"文件名重复：{filename}")
        filenames.add(filename)
        entries.append(Entry(str(word_id), filename))
    return entries


def backup_database(source_path: Path, backup_path: Path) -> None:
    source = sqlite3.connect(source_path.resolve().as_uri() + "?mode=ro", uri=True)
    try:
        target = sqlite3.connect(str(backup_path))
        try:
            source.backup(target)
        finally:
            target.close()
    finally:
        source.close()


def main() -> None:
    args = parse_args()
    database = args.database.resolve()
    source = args.source_dir.resolve()
    backup = args.backup_dir.resolve()
    formal = (database.parent / "mp3").resolve()
    if not database.is_file() or database.is_symlink():
        raise ValueError(f"数据库必须是现有普通文件：{database}")
    if not source.is_dir() or source.is_symlink():
        raise ValueError(f"候选目录必须是现有普通目录：{source}")
    if backup.exists():
        raise ValueError(f"备份目录已存在，拒绝覆盖：{backup}")
    if source == formal or formal in source.parents:
        raise ValueError("候选源目录不能是正式音频目录或其子目录")
    if backup == formal or formal in backup.parents:
        raise ValueError("备份目录不能是正式音频目录或其子目录")

    entries = load_entries(database)
    for entry in entries:
        candidate = source / entry.filename
        if not candidate.is_file() or candidate.is_symlink() or candidate.stat().st_size == 0:
            raise ValueError(f"候选文件缺失、为空或为符号链接：{candidate}")

    backup_audio = backup / "mp3"
    backup_audio.mkdir(parents=True)
    backup_database(database, backup / "data.sqlite")
    existed: dict[str, bool] = {}
    for entry in entries:
        target = formal / entry.filename
        existed[entry.filename] = target.exists()
        if target.exists():
            if not target.is_file() or target.is_symlink() or target.stat().st_size == 0:
                raise ValueError(f"正式旧版文件异常：{target}")
            shutil.copy2(target, backup_audio / entry.filename)

    replaced: list[str] = []
    try:
        with tempfile.TemporaryDirectory(prefix=".azure-word-publish-", dir=formal) as temp:
            stage = Path(temp)
            for entry in entries:
                shutil.copy2(source / entry.filename, stage / entry.filename)
            for entry in entries:
                (stage / entry.filename).replace(formal / entry.filename)
                replaced.append(entry.filename)

        connection = sqlite3.connect(str(database))
        try:
            with connection:
                for entry in entries:
                    cursor = connection.execute(
                        "UPDATE yzc_words SET phonetic = ? WHERE id = ?",
                        (entry.filename, entry.word_id),
                    )
                    if cursor.rowcount != 1:
                        raise ValueError(f"数据库记录不存在或不唯一：{entry.word_id}")
        finally:
            connection.close()
    except BaseException:
        rollback_errors: list[str] = []
        for filename in reversed(replaced):
            target = formal / filename
            try:
                if existed[filename]:
                    with tempfile.NamedTemporaryFile(
                        dir=formal, prefix=filename + ".", suffix=".rollback", delete=False
                    ) as stream:
                        temporary = Path(stream.name)
                    try:
                        shutil.copy2(backup_audio / filename, temporary)
                        temporary.replace(target)
                    finally:
                        temporary.unlink(missing_ok=True)
                else:
                    target.unlink(missing_ok=True)
            except OSError as error:
                rollback_errors.append(f"{filename}: {error}")
        if rollback_errors:
            raise RuntimeError(
                "发布失败且部分音频回滚失败，请从备份人工恢复："
                + str(backup)
                + "\n"
                + "\n".join(rollback_errors)
            )
        raise

    print(f"已正式发布 Azure 单词音频：{len(entries)}条")
    print(f"旧版单词音频及数据库备份：{backup}")
    print("yzc_words.phonetic 已补齐；课文、图片和视频未修改。")


if __name__ == "__main__":
    main()
