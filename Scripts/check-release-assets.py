#!/usr/bin/env python3
"""音源と提出用アプリの静的検証。App Store Connect側の設定は別途確認する。"""
import argparse
import array
import hashlib
import json
from pathlib import Path
import plistlib
import re
import sys
from urllib.parse import urlparse
import wave

parser = argparse.ArgumentParser(description="音源と提出用アプリの確認")
parser.add_argument("--app", type=Path, help="ビルド済み.appの保存先")
parser.add_argument("--strict", action="store_true", help="本番広告IDや公開URLが未設定なら失敗する")
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
manifest = json.loads((root / "docs/audio/manifest.json").read_text())
errors = []
warnings = []
assert len(manifest["assets"]) == 14
assert not manifest["source_audio_used"]
assert not manifest["third_party_samples_used"]
assert not manifest["external_midi_used"]

for item in manifest["assets"]:
    path = root / "MonoKnightApp/Audio" / item["file"]
    try:
        data = path.read_bytes()
        if hashlib.sha256(data).hexdigest() != item["sha256"]:
            errors.append(f"生成記録と一致しません: {item['file']}")
        with wave.open(str(path)) as audio:
            assert (audio.getnchannels(), audio.getsampwidth(), audio.getframerate()) == (1, 2, 44100)
            samples = array.array("h", audio.readframes(audio.getnframes()))
            if sys.byteorder != "little": samples.byteswap()
            assert samples[0] == 0 and samples[-1] == 0
            assert max(abs(x) for x in samples) < 32767
            assert audio.getnframes() == item["frames"]
        if args.app and (args.app / path.name).read_bytes() != data:
            errors.append(f"アプリ内の音源が古いか破損しています: {path.name}")
    except Exception as error:
        errors.append(f"音源検証に失敗: {item['file']} ({error})")

privacy_path = (args.app if args.app else root / "MonoKnightApp") / "PrivacyInfo.xcprivacy"
with privacy_path.open("rb") as source:
    privacy = plistlib.load(source)
reasons = {item["NSPrivacyAccessedAPIType"]: item["NSPrivacyAccessedAPITypeReasons"]
           for item in privacy["NSPrivacyAccessedAPITypes"]}
assert reasons["NSPrivacyAccessedAPICategoryUserDefaults"] == ["CA92.1"]
assert reasons["NSPrivacyAccessedAPICategorySystemBootTime"] == ["35F9.1"]

if args.app:
    with (args.app / "Info.plist").open("rb") as source:
        info = plistlib.load(source)
    if info.get("CFBundleIdentifier") != "com.kokisato.MonoKnightApp":
        errors.append("Bundle IDが現行の提出用IDと一致しません")
    if not info.get("NSUserTrackingUsageDescription"):
        errors.append("トラッキング説明がありません")
    if not info.get("SKAdNetworkItems"):
        errors.append("SKAdNetwork設定がありません")
    for key in ["GADApplicationIdentifier", "GADInterstitialAdUnitID"]:
        value = info.get(key, "")
        separator = "~" if key == "GADApplicationIdentifier" else "/"
        pattern = rf"ca-app-pub-\d{{16}}{re.escape(separator)}\d{{10}}"
        if not re.fullmatch(pattern, value) or "3940256099942544" in value:
            warnings.append(f"本番値の確認が必要です: {key}")
    rewarded = info.get("GADRewardedAdUnitID")
    if rewarded and (not re.fullmatch(r"ca-app-pub-\d{16}/\d{10}", rewarded) or "3940256099942544" in rewarded):
        warnings.append("本番値の確認が必要です: GADRewardedAdUnitID")
    if info.get("UIBackgroundModes"):
        errors.append("意図しないバックグラウンド権限があります")
    for name in ["GoogleMobileAds", "UserMessagingPlatform"]:
        if not (args.app / "Frameworks" / f"{name}.framework/PrivacyInfo.xcprivacy").is_file() and not list(args.app.rglob(f"{name}*.bundle/PrivacyInfo.xcprivacy")):
            errors.append(f"SDKのプライバシーマニフェストがありません: {name}")

metadata = json.loads((root / "docs/release-metadata.json").read_text())
for key in ["support_email", "support_url", "privacy_policy_url"]:
    value = metadata.get(key)
    if not value:
        warnings.append(f"公開前に入力してください: {key}")
    elif key == "support_email":
        if not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", value):
            warnings.append(f"メールアドレスを確認してください: {key}")
    else:
        url = urlparse(value)
        if url.scheme != "https" or not url.netloc:
            warnings.append(f"公開HTTPS URLを確認してください: {key}")

for error in errors: print("不合格: " + error)
for warning in warnings: print("未確定: " + warning)
if errors or (args.strict and warnings):
    print("提出準備は未完了です。上記の項目を解消してください。")
    sys.exit(1)
print("音源14点とプライバシー申告の静的検証に合格しました。")
if warnings: print("公開条件の未確定項目は残っています。")
