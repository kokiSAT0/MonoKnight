#!/usr/bin/env python3
"""作者のBGM・SE作成アプリを直接利用して、同じ音源を再生成する。"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import wave

parser = argparse.ArgumentParser(description="MonoKnight用音源の再生成")
parser.add_argument("--bgm-source", type=Path, required=True, help="bgm_createrの保存先")
parser.add_argument("--se-source", type=Path, required=True, help="game_se_createrの保存先")
args = parser.parse_args()
sys.path.insert(0, str(args.bgm_source.resolve()))
sys.path.insert(0, str(args.se_source.resolve() / "sound_forge"))

import numpy as np
from bgmcomposer.composition import generate_song
from bgmcomposer.synthesizer import synthesize_song
from soundforge.generators import generate_sound
from soundforge.presets import DEFAULT_PARAMETERS

root = Path(__file__).resolve().parents[1]
audio_dir = root / "MonoKnightApp" / "Audio"
metadata_dir = root / "docs" / "audio"
audio_dir.mkdir(parents=True, exist_ok=True)
metadata_dir.mkdir(parents=True, exist_ok=True)
rate = 44100
manifest = {
    "説明": "作者の生成アプリで合成したMonoKnight用オリジナル音源。外部音源・サンプル・MIDI未使用。",
    "source_audio_used": False,
    "third_party_samples_used": False,
    "external_midi_used": False,
    "sources": {},
    "assets": [],
}
for name, source in [("bgm_creater", args.bgm_source), ("game_se_creater", args.se_source)]:
    manifest["sources"][name] = {
        "repository": f"https://github.com/Kurohyou3/{name}",
        "commit": subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip(),
    }


def save(name, label, audio, settings, loop, gain):
    assert np.isfinite(audio).all(), "音源に非有限値があります"
    # 原アプリの正規化後に用途別の音圧を調整し、端点を0にしてクリックを防ぐ。
    audio = audio.astype(np.float32) * gain
    fade = min(len(audio) // 2, int(rate * 0.008))
    audio[:fade] *= np.linspace(0, 1, fade, dtype=np.float32)
    audio[-fade:] *= np.linspace(1, 0, fade, dtype=np.float32)
    pcm = (np.clip(audio, -1, 1) * 32767).astype("<i2")
    path = audio_dir / (name + ".wav")
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(rate)
        output.writeframes(pcm.tobytes())
    manifest["assets"].append({
        "file": path.name, "用途": label, "loop": loop, "sample_rate": rate,
        "frames": len(audio), "duration_sec": round(len(audio) / rate, 4),
        "peak": round(float(np.max(np.abs(audio))), 5),
        "rms": round(float(np.sqrt(np.mean(audio ** 2))), 5),
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "post_gain": gain, "parameters": settings,
    })


music = [
    ("bgm_title", "タイトル・塔選択", "title_menu", "D", "dorian", 92, "none", 100401),
    ("bgm_tutorial", "基礎塔", "stage_normal", "D", "pentatonic_major", 100, "light", 100402),
    ("bgm_growth", "成長塔", "stage_normal", "A", "dorian", 108, "light", 100403),
    ("bgm_trial", "試練塔", "stage_battle", "A", "natural_minor", 116, "light", 100404),
]
for name, label, category, key, scale, bpm, drums, seed in music:
    song = generate_song(category, key, scale, bpm, 16, seed, "sparse", "steady", drums, "triangle", 0.8, label)
    (metadata_dir / (name + ".song.json")).write_text(
        json.dumps(song.to_dict(), ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    save(name, label, synthesize_song(song), song.to_dict(), True, 0.65)

effects = [
    ("se_select", "カード選択・設定の試聴", "menu_move", 0.10, 680),
    ("se_move", "行動確定", "land_soft", 0.13, 180),
    ("se_pickup", "カード拾得", "item_pickup", 0.30, 660),
    ("se_damage", "被ダメージ", "damage_small", 0.22, 160),
    ("se_heal", "HP回復", "heal", 0.45, 520),
    ("se_clear", "フロアクリア", "stage_clear", 0.95, 520),
    ("se_defeat", "敗北", "defeat_jingle", 1.10, 330),
    ("se_victory", "登頂", "victory_jingle", 1.20, 520),
    ("se_warning", "無効な操作・施錠出口", "error_buzz", 0.14, 180),
    ("se_relic", "遺物取得", "power_up", 0.60, 440),
]
for index, (name, label, category, duration, frequency) in enumerate(effects):
    parameters = dict(DEFAULT_PARAMETERS[category])
    parameters.update(duration_sec=duration, base_frequency_hz=frequency, reverb_amount=0.025)
    seed = 100410 + index
    save(name, label, generate_sound(category, parameters, seed),
         {"category": category, "seed": seed, **parameters}, False, 0.45 if name == "se_move" else 0.65)

(metadata_dir / "manifest.json").write_text(
    json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
)
print(f"音源{len(manifest['assets'])}点を生成しました。")
