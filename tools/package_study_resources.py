#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""手动按 n1～n5 打包 study 资源，并同步资源清单。"""

import argparse
from datetime import datetime
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent
PROJECT_ROOT = ROOT.parent.parent
SOURCE = ROOT.parent / 'database' / 'study'
WEB = PROJECT_ROOT / 'resources' / 'web' / 'study'
MANIFEST = WEB / 'study.json'
ZIP = Path('/usr/bin/zip')
PASSWORD = 'yzc_@-YZCstudy_20260907'
LEVELS = ('n1', 'n2', 'n3', 'n4', 'n5')


def read_json(path):
    with path.open(encoding='utf-8', newline='') as stream:
        raw = stream.read()
    return json.loads(raw), '\r\n' if '\r\n' in raw else '\n'


def write_json(path, value, newline):
    with path.open('w', encoding='utf-8', newline=newline) as stream:
        stream.write(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(chunk)
    return result.hexdigest()


def publish(replacements, backup):
    backup.mkdir(parents=True)
    previous = {}
    # Finish every backup before replacing any published file.
    for _, target in replacements:
        saved = backup / target.relative_to(PROJECT_ROOT)
        if target.exists():
            saved.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(target, saved)
            previous[target] = saved
        else:
            previous[target] = None
    changed = []
    try:
        for staged, target in replacements:
            changed.append(target)
            os.replace(staged, target)
    except BaseException:
        failures = []
        for target in reversed(changed):
            try:
                saved = previous[target]
                if saved is None:
                    target.unlink(missing_ok=True)
                else:
                    # Retain the backup after rollback, replacing each file atomically.
                    with tempfile.NamedTemporaryFile(dir=target.parent, delete=False) as stream:
                        temporary = Path(stream.name)
                    try:
                        shutil.copy2(saved, temporary)
                        os.replace(temporary, target)
                    finally:
                        temporary.unlink(missing_ok=True)
            except OSError as error:
                failures.append(f'{target}: {error}')
        if failures:
            print('回退未全部完成，请从备份恢复：' + str(backup), file=sys.stderr)
            print('\n'.join(failures), file=sys.stderr)
        raise


def stage_level(level, stage):
    source = SOURCE / level
    database = source / 'data.sqlite'
    audio = source / 'mp3'
    # 仅检查这两个必要路径；mp3 允许为空，不检查数据库表或音频内容。
    if not database.is_file() or not audio.is_dir():
        raise ValueError(f'{source} 必须包含 data.sqlite 文件和 mp3 目录（目录可为空）')

    snapshot_parent = stage / level / 'snapshot'
    snapshot = snapshot_parent / level
    snapshot.mkdir(parents=True)
    shutil.copytree(audio, snapshot / 'mp3',
                    ignore=shutil.ignore_patterns('.*', '__MACOSX'))
    # 延用原脚本的 SQLite 快照方式，包含已提交 WAL 内容，不查询业务表。
    original = sqlite3.connect(database.resolve().as_uri() + '?mode=ro', uri=True)
    try:
        target = sqlite3.connect(str(snapshot / 'data.sqlite'))
        try:
            original.backup(target)
        finally:
            target.close()
    finally:
        original.close()

    filename = level + '.zip'
    print(f'正在打包 {filename}……', flush=True)
    archive = stage / level / filename
    subprocess.run(
        [str(ZIP), '-q', '-X', '-r', '-P', PASSWORD, str(archive),
         level + '/mp3/', level + '/data.sqlite'],
        cwd=snapshot_parent, check=True,
    )
    return archive, digest(archive)


def package_levels(levels):

    WEB.mkdir(parents=True, exist_ok=True)
    entries, newline = read_json(MANIFEST)
    if not isinstance(entries, list):
        raise ValueError('study.json 必须是资源数组')
    entries_by_id = {}
    for entry in entries:
        if (not isinstance(entry, dict) or not isinstance(entry.get('id'), str)
                or not entry['id'] or entry['id'] in entries_by_id):
            raise ValueError('study.json 的资源 ID 必须非空且唯一')
        entries_by_id[entry['id']] = entry
    for level in levels:
        if level not in entries_by_id:
            raise ValueError(f'study.json 中缺少资源 ID：{level}')
        if any(entry.get('resource_file') == level + '.zip' and entry['id'] != level
               for entry in entries):
            raise ValueError(f'{level}.zip 已被其他资源 ID 使用')

    with tempfile.TemporaryDirectory(prefix='.study-package-stage-', dir=ROOT) as temp:
        stage = Path(temp)
        replacements = []
        for level in levels:
            archive, sha256 = stage_level(level, stage)
            # 按目录级别匹配 ID，保留名称、说明、费率和版本。
            entries_by_id[level]['resource_file'] = archive.name
            entries_by_id[level]['sha256'] = sha256
            replacements.append((archive, WEB / archive.name))
        staged_manifest = stage / 'study.json'
        write_json(staged_manifest, entries, newline)
        backup = ROOT / '.package-backups' / ('study-' + datetime.now().strftime('%Y-%m-%d_%H-%M-%S-%f'))
        # 全部所选资源准备完成后发布，最后更新清单；保留备份与失败回退。
        replacements.append((staged_manifest, MANIFEST))
        publish(replacements, backup)
    for level in levels:
        print(f'打包完成：{WEB / (level + ".zip")}')
        print(f'SHA-256：{entries_by_id[level]["sha256"]}')
    print(f'已更新：{MANIFEST}；旧文件备份：{backup}')


def main():
    parser = argparse.ArgumentParser(
        description='打包 yzc_v3.1/database/study/n1～n5 到 resources/web/study，并更新 study.json。',
    )
    parser.add_argument('levels', nargs='*', help='级别目录名：n1～n5；不指定时打包全部')
    parser.add_argument('--all', action='store_true', help='打包全部五个级别')
    args = parser.parse_args()
    if args.all and args.levels:
        parser.error('--all 不能与级别同时指定')
    if any(level not in LEVELS for level in args.levels):
        parser.error('级别仅支持 n1、n2、n3、n4、n5')
    levels = list(dict.fromkeys(args.levels)) if args.levels else list(LEVELS)
    # 全部及单级别入口使用同一把锁，避免同时覆盖资源清单。
    with (ROOT / '.package-study.lock').open('a', encoding='utf-8') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ValueError('已有 study 打包脚本正在运行，请等待其完成') from None
        if not ZIP.is_file():
            raise ValueError('缺少 macOS 系统 /usr/bin/zip')
        package_levels(levels)


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        print('已取消打包。', file=sys.stderr)
        sys.exit(130)
    except subprocess.CalledProcessError as error:
        print(f'ZIP 打包失败，退出码：{error.returncode}。尚未发布本次资源。', file=sys.stderr)
        sys.exit(1)
    except (OSError, ValueError, KeyError, TypeError, IndexError, sqlite3.Error) as error:
        print(f'打包失败：{error}', file=sys.stderr)
        sys.exit(1)
