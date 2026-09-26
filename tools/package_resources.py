#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Manually package edited resources into the local web server directory."""

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
WEB = PROJECT_ROOT / 'resources' / 'web' / 'textbook'
TEXTBOOKS = WEB / 'yzc_textbook.json'
ZIP = Path('/usr/bin/zip')
V3_PACKAGES = ROOT.parent / 'database/textbook'


def readonly_database(path):
    # Never open the author's database for writing or replace it after packing.
    return sqlite3.connect(path.resolve().as_uri() + '?mode=ro', uri=True)


def stage_v3(folder, stage, password):
    source = V3_PACKAGES / folder
    database = source / 'data.sqlite'
    audio = source / 'mp3'
    if not database.is_file() or not audio.is_dir():
        raise ValueError(f'{source} 必须包含 data.sqlite 和 mp3 目录')

    snapshot_parent = stage / folder / 'snapshot'
    snapshot = snapshot_parent / folder
    snapshot.mkdir(parents=True)
    # Only these two paths enter the archive; authoring JSON files are ignored.
    # Filter every directory level before ZIP recursively reads the snapshot.
    shutil.copytree(
        audio, snapshot / 'mp3',
        ignore=shutil.ignore_patterns('.*', '__MACOSX'),
    )
    staged_database = snapshot / 'data.sqlite'
    original = readonly_database(database)
    try:
        target = sqlite3.connect(str(staged_database))
        try:
            original.backup(target)
            # Match the published textbook by its stable ID, not its display name.
            identities = target.execute('SELECT id FROM yzc_textbook LIMIT 2').fetchall()
            if len(identities) != 1 or not isinstance(identities[0][0], str) or not identities[0][0]:
                raise ValueError(f'{folder} 必须包含唯一且非空的教材 ID')
            textbook_id = identities[0][0]
        finally:
            target.close()
    finally:
        original.close()

    filename = folder + '.zip'
    archive = stage / folder / filename
    subprocess.run(
        [str(ZIP), '-q', '-X', '-r', '-P', password, str(archive),
         folder + '/mp3/', folder + '/data.sqlite'],
        cwd=snapshot_parent, check=True,
    )
    entry = {'file': filename, 'sha256': digest(archive)}
    return textbook_id, entry, (archive, WEB / filename)


def package_v3(selected, all_packages, password):
    WEB.mkdir(parents=True, exist_ok=True)
    if TEXTBOOKS.is_symlink() or not TEXTBOOKS.is_file():
        raise ValueError(f'教材目录必须为现有普通文件：{TEXTBOOKS}')
    textbooks, newline = read_json(TEXTBOOKS)
    if not isinstance(textbooks, list):
        raise ValueError('yzc_textbook.json 必须是教材数组')
    entries = {}
    for row in textbooks:
        if (not isinstance(row, dict) or not isinstance(row.get('id'), str)
                or not row['id'] or row['id'] in entries):
            raise ValueError('yzc_textbook.json 的教材 ID 必须非空且唯一')
        entries[row['id']] = row
    aliases = {'elementary_1': 'xbr_1_1'}
    folders = sorted(
        p.name for p in V3_PACKAGES.iterdir()
        if p.is_dir() and not p.name.startswith('.') and p.name != 'study'
    ) if all_packages else list(dict.fromkeys(aliases.get(p, p) for p in selected))
    if not folders:
        raise ValueError('没有可打包的册别')
    for folder in folders:
        if folder == 'study':
            raise ValueError('study 资源请使用 package_study_resources.py 打包')
        if (not folder or folder.startswith('.') or Path(folder).name != folder
                or any(char in folder for char in '\\:%?#\r\n\x00')):
            raise ValueError(f'无效册别目录名：{folder!r}')
        source = V3_PACKAGES / folder
        if source.is_symlink() or not source.is_dir():
            raise ValueError(f'教材源目录不存在或为符号链接：{source}')
        if (WEB / (folder + '.zip')).is_symlink():
            raise ValueError(f'发布 ZIP 不能为符号链接：{folder}')
    with tempfile.TemporaryDirectory(prefix='.v3-package-stage-', dir=ROOT) as temp:
        stage = Path(temp)
        replacements = []
        packaged_ids = set()
        for folder in folders:
            print(f'正在打包 V3：{folder}', flush=True)
            textbook_id, entry, replacement = stage_v3(folder, stage, password)
            if textbook_id not in entries:
                raise ValueError(f'{folder} 的教材 ID {textbook_id} 未在 yzc_textbook.json 中配置')
            if textbook_id in packaged_ids:
                raise ValueError(f'不同册别不能使用同一教材 ID：{textbook_id}')
            packaged_ids.add(textbook_id)
            if any(row.get('resource_file') == entry['file'] and row['id'] != textbook_id
                   for row in textbooks):
                raise ValueError(f'ZIP 文件名已被其他教材使用：{entry["file"]}')
            entries[textbook_id]['resource_file'] = entry['file']
            entries[textbook_id]['sha256'] = entry['sha256']
            replacements.append(replacement)
        staged_textbooks = stage / 'yzc_textbook.json'
        write_json(staged_textbooks, textbooks, newline)
        # Publish metadata last, with the same backups and rollback as the ZIPs.
        replacements.append((staged_textbooks, TEXTBOOKS))
        backup = ROOT / '.package-backups' / ('v3-' + datetime.now().strftime('%Y-%m-%d_%H-%M-%S-%f'))
        publish(replacements, backup)
    print(f'V3 发布目录：{WEB}；旧文件备份：{backup}')
    print('已同步更新 yzc_textbook.json 的 resource_file 和 sha256。')
    print('教材源数据库未改写。请在 APP 中下载更新。')


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


def main():
    parser = argparse.ArgumentParser(
        description='打包 yzc_v3.1/database/textbook 教材，更新 resources/web/textbook 的 ZIP 与 yzc_textbook.json；不启动或上传服务器。',
    )
    parser.add_argument('packages', nargs='*', help='教材目录名，可指定多个，例如 xbr_1_1；兼容 elementary_1 别名')
    parser.add_argument('--all', action='store_true', help='打包 yzc_v3.1/database/textbook 中全部册别')
    parser.add_argument('--v3', action='store_true', help='兼容已有执行脚本；现在默认打包 yzc_v3.1/database/textbook 教材')
    args = parser.parse_args()
    if bool(args.packages) == args.all:
        parser.error('请指定册别 ID，或单独使用 --all')
    password = os.environ.get('RESOURCE_ARCHIVE_PASSWORD', 'yzc_@-YZCtextboot_20260907')

    # Advisory lock prevents two instances of this script from publishing together.
    with (ROOT / '.package-resources.lock').open('a', encoding='utf-8') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ValueError('已有打包脚本正在运行，请等待其完成') from None
        if not ZIP.is_file():
            raise ValueError('缺少 macOS 系统 /usr/bin/zip')
        if not password:
            raise ValueError('资源包密码不能为空')
        package_v3(args.packages, args.all, password)


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        print('已取消打包。', file=sys.stderr)
        sys.exit(130)
    except subprocess.CalledProcessError as error:
        print(f'ZIP 打包失败，退出码：{error.returncode}。尚未发布本次资源。', file=sys.stderr)
        sys.exit(1)
    except (OSError, ValueError, KeyError, TypeError, sqlite3.Error) as error:
        print(f'打包失败：{error}', file=sys.stderr)
        sys.exit(1)
