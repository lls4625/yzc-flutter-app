#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Generate and publish one JLPT paper's listening audio with Azure Speech.

This production tool is intentionally paper-scoped.  It reads the current N1-N5
study databases, validates the frozen spoken segments against the current question
text, generates a new revision into staging, and publishes one paper transactionally.
The Azure key is read from the macOS Keychain and is never written to disk.
"""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
import hashlib
import html
import json
from pathlib import Path
import re
import shutil
import sqlite3
import subprocess
import tempfile
import time


ROOT = Path("/Users/javalee/work/proj/yzc_f")
APP = ROOT / "yzc_v3.1"
STUDY = APP / "database/study"
WORK = ROOT / "docs/vibe/2026-10-18_21-55-09-J练习N5-N1-Azure听力重制"
KEYCHAIN_SERVICE = "yzc_f.azure_speech.key"
REGION = "japaneast"
ENDPOINT = f"https://{REGION}.tts.speech.microsoft.com/cognitiveservices/v1"
OUTPUT_FORMAT = "audio-24khz-96kbitrate-mono-mp3"
FFMPEG = Path("/opt/homebrew/bin/ffmpeg")
FFPROBE = Path("/opt/homebrew/bin/ffprobe")
FEMALE = "ja-JP-NanamiNeural"
MALE = "ja-JP-KeitaNeural"
RELEASE_NOTE = ["v3发布版3.1.0"]
LEVELS = ("n5", "n4", "n3", "n2", "n1")


def compact(value: object) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write("\n")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def decode_question(row: sqlite3.Row) -> dict[str, object]:
    value = dict(row)
    for key in tuple(value):
        if key.endswith("_json") and value[key] is not None:
            value[key] = json.loads(value[key])
    return value


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


def paper_number_from_id(paper_id: str) -> int:
    match = re.search(r"(?:-|V2-)(\d{2})$", paper_id)
    if not match:
        raise RuntimeError(f"无法从试卷 ID 识别套号：{paper_id}")
    return int(match.group(1))


def next_revision_filename(current: str) -> tuple[int, str]:
    match = re.fullmatch(r"(.+)-v(\d+)\.mp3", current)
    if not match:
        raise RuntimeError(f"音频文件名不符合修订格式：{current}")
    revision = int(match.group(2)) + 1
    return revision, f"{match.group(1)}-v{revision}.mp3"


def load_record_candidates(level: str, filename: str) -> list[dict[str, object]]:
    stem = Path(filename).stem
    paths: list[Path]
    if level == "n4":
        paths = [ROOT / "docs/vibe/n4-listening-final-media-v6-2026-09-25/audio-records" / f"{stem}.json"]
    elif level == "n3":
        paths = [ROOT / "docs/vibe/n3-listening-media-v1-2026-09-25/audio-records" / f"{stem}.json"]
    elif level == "n2":
        paths = [ROOT / "docs/vibe/n2-listening-media-v1-2026-09-27/audio-records" / f"{stem}.json"]
    else:
        paths = list((ROOT / "docs/vibe").rglob(f"{stem}.tts.json"))
    paths.extend((ROOT / "docs/vibe").rglob(f"{stem}.tts.json"))
    paths.extend((ROOT / "docs/vibe").rglob(f"{stem}.json"))
    paths = list(dict.fromkeys(paths))
    records: list[dict[str, object]] = []
    for path in paths:
        if not path.is_file():
            continue
        value = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(value, dict) and isinstance(value.get("segments"), list):
            value["_record_path"] = str(path)
            records.append(value)
    return records


def transcript_parts(transcript: str) -> list[tuple[str, str]]:
    matches = list(re.finditer(r"(?:^|\n)\s*([^：\n]{1,16})：", transcript))
    if not matches:
        return []
    result: list[tuple[str, str]] = []
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(transcript)
        result.append((match.group(1).strip(), transcript[match.end():end].strip()))
    return result


def strip_number_prefix(text: str) -> str:
    return re.sub(
        r"^(?:[零一二三四五六七八九十]+番[。．、\s]*|[零一二三四五六七八九十]+[。．、\s]+)",
        "",
        text.strip(),
    )


def speech_compare_key(text: str) -> str:
    digit_names = str.maketrans("0123456789", "〇一二三四五六七八九")
    value = text.translate(digit_names)
    return re.sub(r"[\s、，,。．]", "", value)


def voice_gender(segment: dict[str, object]) -> str:
    explicit = str(segment.get("speaker_gender") or "").lower()
    if explicit in {"female", "女"}:
        return "female"
    if explicit in {"male", "男"}:
        return "male"
    voice = str(segment.get("voice") or "")
    if voice == FEMALE or "Nanami" in voice:
        return "female"
    if voice == MALE or "Keita" in voice:
        return "male"
    raise RuntimeError(f"无法确定片段声音性别：{segment}")


def normalized_segments(record: dict[str, object]) -> list[dict[str, object]]:
    result: list[dict[str, object]] = []
    for raw in record["segments"]:
        segment = dict(raw)
        gender = voice_gender(segment)
        segment["voice"] = FEMALE if gender == "female" else MALE
        segment["speaker_gender"] = gender
        segment["rate"] = "+0%"
        segment["pitch"] = "+0Hz"
        segment["volume"] = "+0%"
        result.append(segment)
    return result


def validate_record(question: dict[str, object], record: dict[str, object]) -> list[dict[str, object]]:
    if record.get("id") != question["id"]:
        raise RuntimeError(f"制作记录 ID 不一致：{question['id']}")
    if record.get("filename") not in {None, question["phonetic"]}:
        raise RuntimeError(f"制作记录文件名不一致：{question['id']}")
    segments = normalized_segments(record)
    material = question["material_json"]
    transcript = str(material.get("transcript") or "").strip()
    if not transcript:
        raise RuntimeError(f"听力正文为空：{question['id']}")
    spoken = [(str(item.get("role")), str(item.get("text", "")).strip()) for item in segments]
    dialogue = transcript_parts(transcript)
    if dialogue:
        for role, text in dialogue:
            matching = [spoken_text for spoken_role, spoken_text in spoken if spoken_role == role]
            if not any(
                spoken_text == text or speech_compare_key(spoken_text) == speech_compare_key(text)
                for spoken_text in matching
            ):
                raise RuntimeError(f"对话片段与数据库不一致：{question['id']} {role}：{text}")
    elif not any(transcript in text for _, text in spoken):
        raise RuntimeError(f"独白/发话与数据库不一致：{question['id']}")

    stem = str(question["stem_json"].get("text") or "").strip()
    if question["type_code"] not in {"L_RESPONSE", "L_UTTERANCE"}:
        if not any(stem == text or stem in text for _, text in spoken):
            raise RuntimeError(f"题干未按数据库进入音频：{question['id']}")

    options = [str(item.get("text") or "").strip() for item in question["options_json"]]
    option_segments = [strip_number_prefix(text) for role, text in spoken if role == "spoken_option"]
    expected_options = bool(record.get("includes_options"))
    if expected_options and option_segments != options:
        raise RuntimeError(f"朗读选项与数据库顺序或文字不一致：{question['id']}")
    if not expected_options and option_segments:
        raise RuntimeError(f"不应朗读纸面选项：{question['id']}")
    if any(role in {"answer", "explanation", "correct_answer"} for role, _ in spoken):
        raise RuntimeError(f"音频混入答案或解析：{question['id']}")

    for segment in segments:
        role = str(segment["role"])
        if any(mark in role for mark in ("女", "母", "姉", "妹", "女性")) and voice_gender(segment) != "female":
            raise RuntimeError(f"明确女性角色使用了非女声：{question['id']} {role}")
        if any(mark in role for mark in ("男", "父", "兄", "弟", "男性")) and voice_gender(segment) != "male":
            raise RuntimeError(f"明确男性角色使用了非男声：{question['id']} {role}")
    return segments


def explicit_arrow_gender(text: str) -> str | None:
    compact_text = re.sub(r"\s+", " ", text).lower()
    female = bool(re.search(r"(?:arrow|箭头|矢印)[^.。；;]{0,90}(?:woman|girl|female|女性|女生|女人|女の人)", compact_text))
    male = bool(re.search(r"(?:arrow|箭头|矢印)[^.。；;]{0,90}(?:man|boy|male|男性|男生|男人|男の人)", compact_text))
    if female and male:
        return None
    if female:
        return "female"
    if male:
        return "male"
    return None


def validate_scene_gender(question: dict[str, object], segments: list[dict[str, object]]) -> dict[str, object]:
    material = question["material_json"]
    scene = material.get("scene_image")
    if not isinstance(scene, dict):
        return {"has_scene_image": False, "explicit_gender": None, "status": "not_applicable"}
    evidence = " ".join(
        str(value) for value in (
            scene.get("alt_text"), material.get("scene_description"), material.get("scene_source_cn")
        ) if value
    )
    gender = explicit_arrow_gender(evidence)
    option_genders = {voice_gender(item) for item in segments if item.get("role") == "spoken_option"}
    if gender and option_genders != {gender}:
        raise RuntimeError(
            f"配图箭头人物与选项声音性别不一致：{question['id']} image={gender} voices={sorted(option_genders)}"
        )
    return {
        "has_scene_image": True,
        "path": scene.get("path"),
        "explicit_gender": gender,
        "spoken_option_genders": sorted(option_genders),
        "status": "matched" if gender else "image_metadata_gender_unspecified",
    }


def ssml(segments: list[dict[str, object]]) -> bytes:
    body: list[str] = []
    for segment in segments:
        pause = int(segment.get("pause_ms") or 0)
        break_tag = f'<break time="{pause}ms"/>' if pause else ""
        body.append(
            f'<voice name="{html.escape(str(segment["voice"]), quote=True)}">'
            f'{html.escape(str(segment["text"]), quote=False)}{break_tag}</voice>'
        )
    document = (
        '<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="ja-JP">'
        + "".join(body)
        + "</speak>"
    )
    return document.encode("utf-8")


def synthesize(target: Path, segments: list[dict[str, object]], key: str) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_suffix(".partial.mp3")
    payload = ssml(segments)
    with tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", prefix=".azure-speech-header-", suffix=".txt", delete=False
    ) as header_stream:
        header_path = Path(header_stream.name)
        header_stream.write(f"Ocp-Apim-Subscription-Key: {key}\n")
    try:
        completed = subprocess.run(
            [
                "/usr/bin/curl", "--fail-with-body", "--silent", "--show-error",
                "--retry", "5", "--retry-all-errors", "--retry-delay", "2",
                "--retry-max-time", "300", "--remove-on-error", "--request", "POST",
                "--header", "@" + str(header_path),
                "--header", "Content-Type: application/ssml+xml",
                "--header", f"X-Microsoft-OutputFormat: {OUTPUT_FORMAT}",
                "--header", "User-Agent: yzc-f-jlpt-azure-listening-v3.1.0",
                "--data-binary", "@-", "--output", str(temporary), ENDPOINT,
            ],
            input=payload,
            check=False,
            capture_output=True,
        )
        if completed.returncode != 0:
            detail = completed.stderr.decode("utf-8", errors="replace").strip()
            response = temporary.read_bytes().decode("utf-8", errors="replace").strip() if temporary.is_file() else ""
            raise RuntimeError(f"Azure Speech 生成失败：{detail} {response}".strip())
        if not temporary.is_file() or temporary.stat().st_size == 0:
            raise RuntimeError("Azure Speech 返回空音频")
        temporary.replace(target)
    finally:
        header_path.unlink(missing_ok=True)
        temporary.unlink(missing_ok=True)


def technical_metadata(path: Path) -> dict[str, object]:
    subprocess.run(
        [str(FFMPEG), "-nostdin", "-hide_banner", "-loglevel", "error", "-i", str(path), "-f", "null", "-"],
        check=True,
        capture_output=True,
    )
    probe = subprocess.run(
        [
            str(FFPROBE), "-v", "error", "-select_streams", "a:0",
            "-show_entries", "stream=sample_rate,channels,bit_rate:format=duration",
            "-of", "json", str(path),
        ],
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    value = json.loads(probe.stdout)
    stream = value["streams"][0]
    return {
        "duration_seconds": round(float(value["format"]["duration"]), 3),
        "sample_rate_hz": int(stream["sample_rate"]),
        "channels": int(stream["channels"]),
        "bitrate_bps": int(stream.get("bit_rate") or 96000),
        "bytes": path.stat().st_size,
        "sha256": sha256_file(path),
    }


def content_hash(question: dict[str, object]) -> str:
    payload = {key: value for key, value in question.items() if key not in {"content_hash", "created_at", "updated_at"}}
    return hashlib.sha256(json.dumps(payload, ensure_ascii=False, sort_keys=True).encode("utf-8")).hexdigest()


def audio_metadata(record: dict[str, object], paper_number: int) -> dict[str, object]:
    voices: dict[str, object] = {}
    for segment in record["segments"]:
        voices.setdefault(str(segment["role"]), str(segment["voice"]))
    return {
        "source": "azure_speech",
        "engine_version": "REST API",
        "region": REGION,
        "output_format": OUTPUT_FORMAT,
        "scope": "full_question",
        "media_revision": record["media_revision"],
        "path_field": "phonetic",
        "path_base": "mp3",
        "synthetic": True,
        "includes_prompt_before": record["includes_prompt_before"],
        "includes_prompt_after": record["includes_prompt_after"],
        "includes_options": record["includes_options"],
        "includes_item_number": True,
        "item_number_scope": f"within_type_in_paper_{paper_number:02d}",
        "includes_type_instruction": False,
        "includes_answer_or_explanation": False,
        "duration_pcm_seconds": record["duration_seconds"],
        "rate": "+0%",
        "pitch": "+0Hz",
        "volume": "+0%",
        "sample_rate_hz": record["sample_rate_hz"],
        "channels": record["channels"],
        "bitrate_bps": record["bitrate_bps"],
        "bytes": record["bytes"],
        "sha256": record["sha256"],
        "playback_order": record["playback_order"],
        "voice_cast": voices,
        "technical_check": "azure_response_decoded_and_probed",
        "technical_check_completed": True,
        "human_listening_review_completed": False,
        "generated_at": record["generated_at"],
    }


def instruction_metadata(old: dict[str, object], record: dict[str, object]) -> dict[str, object]:
    value = dict(old)
    value.update({
        "path": record["filename"],
        "source": "azure_speech",
        "engine_version": "REST API",
        "region": REGION,
        "shared_revision": record["media_revision"],
        "duration_pcm_seconds": record["duration_seconds"],
        "bytes": record["bytes"],
        "sha256": record["sha256"],
        "technical_check": "azure_response_decoded_and_probed",
        "technical_check_completed": True,
        "human_listening_review_completed": False,
        "generated_at": record["generated_at"],
    })
    return value


def build_instruction_records(level: str, rows: list[dict[str, object]], key: str) -> dict[str, dict[str, object]]:
    by_type: dict[str, dict[str, object]] = {}
    for question in rows:
        type_code = str(question["type_code"])
        if type_code in by_type:
            continue
        presentation = question["presentation_json"]
        old = presentation.get("instruction_audio")
        text = str(presentation.get("instruction_ja") or "").strip()
        if not isinstance(old, dict) or not text:
            raise RuntimeError(f"缺少共享题型说明：{level} {type_code}")
        revision, filename = next_revision_filename(str(old["path"]))
        segment = {"role": "instruction", "text": text, "pause_ms": 800, "voice": FEMALE, "speaker_gender": "female"}
        target = WORK / "staging" / level / "shared" / filename
        if not target.is_file():
            synthesize(target, [segment], key)
        tech = technical_metadata(target)
        by_type[type_code] = {
            "kind": "shared_instruction",
            "level": level.upper(),
            "type_code": type_code,
            "media_revision": revision,
            "filename": filename,
            "segments": [segment],
            "generated_at": datetime.now().astimezone().isoformat(timespec="seconds"),
            **tech,
        }
    return by_type


def load_published_instruction_records(level: str) -> dict[str, dict[str, object]]:
    database = STUDY / level / "data.sqlite"
    connection = sqlite3.connect(f"file:{database}?mode=ro", uri=True)
    connection.row_factory = sqlite3.Row
    try:
        rows = connection.execute(
            """
            SELECT q.type_code,q.presentation_json
            FROM stydy_jlpt_paper_item i
            JOIN stydy_jlpt_question q ON q.id=i.question_id AND q.version=i.question_version
            JOIN stydy_jlpt_paper p ON p.id=i.paper_id AND p.version=i.paper_version
            WHERE q.exam_section_code='listening'
            ORDER BY p.id,i.position
            """
        ).fetchall()
    finally:
        connection.close()
    records: dict[str, dict[str, object]] = {}
    for row in rows:
        type_code = str(row["type_code"])
        if type_code in records:
            continue
        metadata = json.loads(row["presentation_json"] or "{}").get("instruction_audio")
        if not isinstance(metadata, dict) or metadata.get("source") != "azure_speech":
            continue
        filename = str(metadata["path"])
        target = STUDY / level / "mp3" / filename
        if not target.is_file():
            raise RuntimeError(f"已发布共享题型说明文件不存在：{target}")
        tech = technical_metadata(target)
        records[type_code] = {
            "kind": "shared_instruction",
            "level": level.upper(),
            "type_code": type_code,
            "media_revision": int(metadata["shared_revision"]),
            "filename": filename,
            "segments": [],
            "generated_at": metadata.get("generated_at"),
            "reused_from_level_publication": True,
            **tech,
        }
    return records


def flags(type_code: str, includes_options: bool) -> tuple[bool, bool, list[str]]:
    if type_code in {"L_TASK", "L_POINT"}:
        return True, True, ["number_scene", "question", "dialogue", "question_repeat"]
    if type_code == "L_UTTERANCE":
        return True, False, ["number_scene_question", "spoken_options"]
    if type_code == "L_RESPONSE":
        return False, False, ["number", "stimulus", "spoken_options"]
    if type_code in {"L_SUMMARY", "L_INTEGRATED"}:
        return False, True, ["number", "dialogue_or_monologue", "question", "spoken_options"]
    raise RuntimeError(f"未知听力题型：{type_code}")


def load_paper(level: str, paper_number: int) -> tuple[str, list[dict[str, object]]]:
    database = STUDY / level / "data.sqlite"
    connection = sqlite3.connect(f"file:{database}?mode=ro", uri=True)
    connection.row_factory = sqlite3.Row
    try:
        papers = connection.execute("SELECT id,version FROM stydy_jlpt_paper ORDER BY id").fetchall()
        matched = [(str(row["id"]), int(row["version"])) for row in papers if paper_number_from_id(str(row["id"])) == paper_number]
        if len(matched) != 1:
            raise RuntimeError(f"{level} 第{paper_number:02d}套定位结果不是唯一：{matched}")
        paper_id, paper_version = matched[0]
        rows = connection.execute(
            """
            SELECT q.* FROM stydy_jlpt_paper_item i
            JOIN stydy_jlpt_question q ON q.id=i.question_id AND q.version=i.question_version
            WHERE i.paper_id=? AND i.paper_version=? AND q.exam_section_code='listening'
            ORDER BY i.position
            """,
            (paper_id, paper_version),
        ).fetchall()
        return paper_id, [decode_question(row) for row in rows]
    finally:
        connection.close()


def generate_paper(level: str, paper_number: int, key: str) -> tuple[str, list[dict[str, object]], dict[str, dict[str, object]]]:
    paper_id, questions = load_paper(level, paper_number)
    expected = {"n5": 24, "n4": 28, "n3": 28, "n2": 30, "n1": 30}[level]
    if len(questions) != expected:
        raise RuntimeError(f"{level} 第{paper_number:02d}套听力题数应为{expected}，实际{len(questions)}")
    instruction_records = (
        build_instruction_records(level, questions, key)
        if paper_number == 1
        else load_published_instruction_records(level)
    )
    expected_instruction_count = len({str(item["type_code"]) for item in questions})
    if len(instruction_records) != expected_instruction_count:
        raise RuntimeError(
            f"{level} 共享题型说明数量应为{expected_instruction_count}，实际{len(instruction_records)}"
        )
    def generate_question(index: int, question: dict[str, object]) -> dict[str, object]:
        candidates = load_record_candidates(level, str(question["phonetic"]))
        validated: list[tuple[dict[str, object], list[dict[str, object]]]] = []
        errors: list[str] = []
        for candidate in candidates:
            try:
                validated.append((candidate, validate_record(question, candidate)))
            except RuntimeError as error:
                errors.append(str(error))
        if not validated:
            raise RuntimeError(f"没有与当前数据库匹配的制作记录：{question['id']}；{errors[:3]}")
        signatures = {compact(segments) for _, segments in validated}
        if len(signatures) != 1:
            raise RuntimeError(f"同名制作记录内容不一致：{question['id']}")
        source_record, segments = validated[0]
        image_gender = validate_scene_gender(question, segments)
        revision, filename = next_revision_filename(str(question["phonetic"]))
        target = WORK / "staging" / level / f"p{paper_number:02d}" / filename
        if not target.is_file():
            synthesize(target, segments, key)
        tech = technical_metadata(target)
        prompt_before, prompt_after, playback_order = flags(str(question["type_code"]), bool(source_record.get("includes_options")))
        result = {
            "id": question["id"],
            "question_version": question["version"],
            "paper_id": paper_id,
            "paper_number": paper_number,
            "ordinal_in_paper": index,
            "type_code": question["type_code"],
            "source_phonetic": question["phonetic"],
            "source_record": source_record["_record_path"],
            "filename": filename,
            "media_revision": revision,
            "segments": segments,
            "includes_options": bool(source_record.get("includes_options")),
            "includes_prompt_before": prompt_before,
            "includes_prompt_after": prompt_after,
            "playback_order": playback_order,
            "question_text_matched": True,
            "option_text_and_order_matched": True,
            "explicit_role_gender_matched": True,
            "scene_gender_check": image_gender,
            "generated_at": datetime.now().astimezone().isoformat(timespec="seconds"),
            **tech,
        }
        print(f"GENERATED {level.upper()} p{paper_number:02d} {index}/{expected} {question['id']}", flush=True)
        return result

    completed_by_index: dict[int, dict[str, object]] = {}
    with ThreadPoolExecutor(max_workers=6) as executor:
        futures = {
            executor.submit(generate_question, index, question): index
            for index, question in enumerate(questions, start=1)
        }
        for future in as_completed(futures):
            index = futures[future]
            completed_by_index[index] = future.result()
    completed = [completed_by_index[index] for index in range(1, expected + 1)]
    return paper_id, completed, instruction_records


def backup_database(level: str) -> Path:
    source_path = STUDY / level / "data.sqlite"
    backup_path = WORK / "backups" / f"{level}-data-before-azure-v3.1.0.sqlite"
    if backup_path.exists():
        return backup_path
    backup_path.parent.mkdir(parents=True, exist_ok=True)
    source = sqlite3.connect(source_path)
    target = sqlite3.connect(backup_path)
    try:
        source.backup(target)
    finally:
        target.close()
        source.close()
    return backup_path


def publish(level: str, paper_id: str, records: list[dict[str, object]], instructions: dict[str, dict[str, object]]) -> dict[str, object]:
    database = STUDY / level / "data.sqlite"
    media = STUDY / level / "mp3"
    backup = backup_database(level)
    media.mkdir(parents=True, exist_ok=True)
    for record in list(records) + list(instructions.values()):
        if record.get("kind") == "shared_instruction" and record.get("reused_from_level_publication"):
            source = media / str(record["filename"])
        else:
            source = WORK / "staging" / level / ("shared" if record.get("kind") == "shared_instruction" else f"p{record['paper_number']:02d}") / str(record["filename"])
        target = media / str(record["filename"])
        if target.exists() and sha256_file(target) != record["sha256"]:
            raise RuntimeError(f"正式目录已有不同内容的同名文件：{target}")
        if not target.exists():
            shutil.copy2(source, target)
        if sha256_file(target) != record["sha256"]:
            raise RuntimeError(f"正式文件复制后摘要不一致：{target}")

    stamp = datetime.now().astimezone().isoformat(timespec="seconds")
    connection = sqlite3.connect(database)
    connection.row_factory = sqlite3.Row
    updated_ids: list[str] = []
    try:
        connection.execute("BEGIN IMMEDIATE")
        for record in records:
            row = connection.execute(
                "SELECT * FROM stydy_jlpt_question WHERE id=? AND version=?",
                (record["id"], record["question_version"]),
            ).fetchone()
            if row is None:
                raise RuntimeError(f"发布时题目不存在：{record['id']}")
            question = decode_question(row)
            if question["phonetic"] != record["source_phonetic"]:
                raise RuntimeError(f"发布前音频引用已变化：{record['id']}")
            question["phonetic"] = record["filename"]
            material = question["material_json"]
            material["delivery"] = "audio_file"
            material["audio"] = audio_metadata(record, int(record["paper_number"]))
            question["material_json"] = material
            presentation = question["presentation_json"]
            if record["type_code"] in instructions:
                presentation["instruction_audio"] = instruction_metadata(
                    presentation["instruction_audio"], instructions[str(record["type_code"])]
                )
            question["presentation_json"] = presentation
            question["updated_at"] = stamp
            question["content_hash"] = content_hash(question)
            fields = [key for key in question if key not in {"id", "version"}]
            values = [compact(question[key]) if key.endswith("_json") and question[key] is not None else question[key] for key in fields]
            result = connection.execute(
                "UPDATE stydy_jlpt_question SET " + ",".join(f"{field}=?" for field in fields) + " WHERE id=? AND version=?",
                values + [question["id"], question["version"]],
            )
            if result.rowcount != 1:
                raise RuntimeError(f"题目更新数量异常：{record['id']}")
            snapshot = connection.execute(
                "UPDATE stydy_jlpt_paper_item SET question_snapshot_json=? WHERE paper_id=? AND question_id=? AND question_version=?",
                (compact(question), paper_id, question["id"], question["version"]),
            )
            if snapshot.rowcount != 1:
                raise RuntimeError(f"试卷快照更新数量异常：{record['id']}")
            updated_ids.append(str(question["id"]))

        paper = connection.execute(
            "SELECT version,parts_json,recipe_json FROM stydy_jlpt_paper WHERE id=?",
            (paper_id,),
        ).fetchone()
        if paper is None:
            raise RuntimeError(f"试卷不存在：{paper_id}")
        parts = json.loads(paper["parts_json"] or "[]")
        recipe = json.loads(paper["recipe_json"] or "{}")
        if instructions:
            mapped = {}
            for type_code, record in instructions.items():
                sample = next(item for item in records if item["type_code"] == type_code)
                qrow = connection.execute(
                    "SELECT presentation_json FROM stydy_jlpt_question WHERE id=? AND version=?",
                    (sample["id"], sample["question_version"]),
                ).fetchone()
                mapped[type_code] = json.loads(qrow["presentation_json"])["instruction_audio"]
            for part in parts:
                if part.get("code") == "listening":
                    part["type_instruction_audio"] = mapped
                    part["media_revision"] = max(int(item["media_revision"]) for item in records)
            shared = recipe.get("official_shared_type_instruction_audio")
            if isinstance(shared, dict):
                shared["source"] = "azure_speech"
                shared["engine_version"] = "REST API"
                shared["region"] = REGION
                shared["updated_at"] = stamp
                shared["paths"] = {key: value["filename"] for key, value in instructions.items()}
                shared["technical_check_completed"] = True
                shared["human_listening_review_completed"] = False
        connection.execute(
            "UPDATE stydy_jlpt_paper SET editorial_notes_json=?,parts_json=?,recipe_json=? WHERE id=? AND version=?",
            (compact(RELEASE_NOTE), compact(parts), compact(recipe), paper_id, int(paper["version"])),
        )
        connection.commit()
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()

    check = sqlite3.connect(f"file:{database}?mode=ro", uri=True)
    try:
        notes = json.loads(check.execute("SELECT editorial_notes_json FROM stydy_jlpt_paper WHERE id=?", (paper_id,)).fetchone()[0])
        if notes != RELEASE_NOTE:
            raise RuntimeError(f"备注回读不一致：{paper_id}")
        for record in records:
            row = check.execute(
                "SELECT phonetic,material_json FROM stydy_jlpt_question WHERE id=? AND version=?",
                (record["id"], record["question_version"]),
            ).fetchone()
            if row is None or row[0] != record["filename"]:
                raise RuntimeError(f"音频引用回读不一致：{record['id']}")
            audio = json.loads(row[1])["audio"]
            if audio.get("sha256") != record["sha256"] or audio.get("source") != "azure_speech":
                raise RuntimeError(f"音频元数据回读不一致：{record['id']}")
            target = media / str(record["filename"])
            if not target.is_file() or sha256_file(target) != record["sha256"]:
                raise RuntimeError(f"正式音频回读不一致：{target}")
    finally:
        check.close()
    return {
        "level": level.upper(),
        "paper_id": paper_id,
        "question_audio_count": len(records),
        "shared_instruction_count": len(instructions),
        "database_backup": str(backup),
        "release_note": RELEASE_NOTE,
        "published_at": stamp,
        "database_readback_verified": True,
        "manual_listening_completed": False,
        "app_build_or_test_performed": False,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="逐套生成并发布 J练习 Azure Speech 听力资源")
    parser.add_argument("--level", required=True, choices=LEVELS)
    parser.add_argument("--paper", required=True, type=int, choices=range(1, 21))
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if not FFMPEG.is_file() or not FFPROBE.is_file():
        raise RuntimeError("缺少 /opt/homebrew/bin/ffmpeg 或 ffprobe")
    receipt = WORK / "receipts" / f"{args.level}-p{args.paper:02d}.json"
    if receipt.exists():
        print(f"ALREADY_COMPLETE {args.level.upper()} p{args.paper:02d}")
        return
    key = load_key()
    paper_id, records, instructions = generate_paper(args.level, args.paper, key)
    manifest = WORK / "manifests" / f"{args.level}-p{args.paper:02d}-audio.json"
    write_json(manifest, {"questions": records, "shared_instructions": instructions})
    result = publish(args.level, paper_id, records, instructions)
    result["manifest"] = str(manifest)
    write_json(receipt, result)
    print(
        f"PAPER_COMPLETE {args.level.upper()} p{args.paper:02d} "
        f"questions={len(records)} shared={len(instructions)}",
        flush=True,
    )


if __name__ == "__main__":
    main()
