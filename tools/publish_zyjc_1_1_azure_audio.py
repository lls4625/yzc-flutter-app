#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Publish staged zyjc_1_1 Azure lesson audio with backup and rollback."""

from __future__ import annotations

import argparse
from pathlib import Path
import shutil
import sqlite3
import tempfile


PROJECT_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_DATABASE = PROJECT_ROOT / "database/textbook/zyjc_1_1/data.sqlite"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="备份旧版课文音频后发布230条 Azure 候选；不修改 SQLite。"
    )
    parser.add_argument("--source-dir", type=Path, required=True)
    parser.add_argument("--backup-dir", type=Path, required=True)
    parser.add_argument("--database", type=Path, default=DEFAULT_DATABASE)
    return parser.parse_args()


def expected_filenames(database: Path) -> list[str]:
    if not database.is_file() or database.is_symlink():
        raise ValueError(f"数据库必须是现有普通文件：{database}")
    connection = sqlite3.connect(database.resolve().as_uri() + "?mode=ro", uri=True)
    try:
        rows = connection.execute(
            """
            SELECT phonetic
            FROM yzc_content
            WHERE media_type = 'text'
              AND content IS NOT NULL
              AND trim(content) <> ''
              AND category IN ('05', '06')
            ORDER BY id
            """
        ).fetchall()
    finally:
        connection.close()
    names = [str(row[0] or "") for row in rows]
    if len(names) != 230 or len(set(names)) != 230:
        raise ValueError("数据库课文音频引用必须恰好包含230个非重复文件名")
    for name in names:
        if not name.startswith("l_l") or not name.endswith(".mp3") or Path(name).name != name:
            raise ValueError(f"无效课文音频文件名：{name!r}")
    return names


def require_files(folder: Path, names: list[str], label: str) -> None:
    if not folder.is_dir() or folder.is_symlink():
        raise ValueError(f"{label}目录必须是现有普通目录：{folder}")
    for name in names:
        path = folder / name
        if not path.is_file() or path.is_symlink() or path.stat().st_size == 0:
            raise ValueError(f"{label}文件缺失、为空或为符号链接：{path}")


def publish(source: Path, target: Path, backup: Path, names: list[str]) -> None:
    if backup.exists():
        raise ValueError(f"备份目录已存在，拒绝覆盖：{backup}")
    backup.mkdir(parents=True)
    for name in names:
        shutil.copy2(target / name, backup / name)

    replaced: list[str] = []
    try:
        with tempfile.TemporaryDirectory(prefix=".azure-audio-publish-", dir=target) as temp:
            stage = Path(temp)
            for name in names:
                shutil.copy2(source / name, stage / name)
            for name in names:
                (stage / name).replace(target / name)
                replaced.append(name)
    except BaseException:
        rollback_errors: list[str] = []
        for name in reversed(replaced):
            try:
                with tempfile.NamedTemporaryFile(
                    dir=target, prefix=name + ".", suffix=".rollback", delete=False
                ) as stream:
                    temporary = Path(stream.name)
                try:
                    shutil.copy2(backup / name, temporary)
                    temporary.replace(target / name)
                finally:
                    temporary.unlink(missing_ok=True)
            except OSError as error:
                rollback_errors.append(f"{name}: {error}")
        if rollback_errors:
            raise RuntimeError(
                "替换失败且部分回滚失败，请从备份目录人工恢复："
                + str(backup)
                + "\n"
                + "\n".join(rollback_errors)
            )
        raise


def main() -> None:
    args = parse_args()
    database = args.database.resolve()
    source = args.source_dir.resolve()
    backup = args.backup_dir.resolve()
    target = (database.parent / "mp3").resolve()
    if source == target or target in source.parents:
        raise ValueError("候选源目录不能是正式音频目录或其子目录")
    if backup == target or target in backup.parents:
        raise ValueError("备份目录不能是正式音频目录或其子目录")
    names = expected_filenames(database)
    require_files(source, names, "候选")
    require_files(target, names, "正式旧版")
    publish(source, target, backup, names)
    print(f"已正式替换 Azure 课文音频：{len(names)}条")
    print(f"旧版 Edge 音频备份：{backup}")
    print("数据库未修改；单词、图片和视频未修改。")


if __name__ == "__main__":
    main()
