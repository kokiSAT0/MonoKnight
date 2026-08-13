#!/usr/bin/env python3
"""モノのフラットなアプリアイコンと起動マークを再生成する。"""

from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
APP_ICON_DIR = ROOT / "MonoKnightApp" / "Assets.xcassets" / "AppIcon.appiconset"
LAUNCH_MARK_DIR = ROOT / "MonoKnightApp" / "Assets.xcassets" / "LaunchMark.imageset"


def make_icon(size: int) -> Image.Image:
    scale = size / 1024
    point = lambda x, y: (round(x * scale), round(y * scale))
    box = lambda x0, y0, x1, y1: (*point(x0, y0), *point(x1, y1))

    image = Image.new("RGB", (size, size), "#071B38")
    draw = ImageDraw.Draw(image)

    # オーロラと氷床。色面を絞り、小さい表示でも輪郭が潰れない構成にする。
    draw.polygon([point(0, 205), point(360, 92), point(735, 175), point(1024, 54), point(1024, 190), point(690, 292), point(310, 207), point(0, 322)], fill="#36E3C1")
    draw.polygon([point(0, 300), point(310, 207), point(690, 292), point(1024, 190), point(1024, 258), point(705, 370), point(300, 282), point(0, 380)], fill="#7F6BF2")
    draw.polygon([point(0, 800), point(210, 680), point(360, 790), point(520, 640), point(700, 785), point(850, 675), point(1024, 810), point(1024, 1024), point(0, 1024)], fill="#1689C8")
    draw.polygon([point(0, 915), point(235, 782), point(490, 920), point(760, 770), point(1024, 910), point(1024, 1024), point(0, 1024)], fill="#82EAF0")

    # モノの体、腹、翼。
    draw.ellipse(box(245, 252, 779, 914), fill="#101927")
    draw.ellipse(box(337, 451, 687, 850), fill="#F1F7F7")
    draw.polygon([point(305, 520), point(145, 675), point(315, 745), point(390, 625)], fill="#111B2B")
    draw.polygon([point(719, 520), point(879, 675), point(709, 745), point(634, 625)], fill="#111B2B")

    # 氷の兜と宝石。
    draw.polygon([point(260, 446), point(315, 245), point(430, 170), point(512, 92), point(594, 170), point(709, 245), point(764, 446), point(656, 380), point(368, 380)], fill="#DDF7FF")
    draw.polygon([point(315, 245), point(430, 170), point(404, 379), point(260, 446)], fill="#86CFEA")
    draw.polygon([point(594, 170), point(709, 245), point(764, 446), point(620, 379)], fill="#9CE5F2")
    draw.polygon([point(512, 144), point(580, 260), point(512, 342), point(444, 260)], fill="#37E3D1")
    draw.polygon([point(512, 144), point(580, 260), point(512, 260), point(444, 260)], fill="#8A65F5")

    # 顔、目、くちばし。
    draw.ellipse(box(338, 335, 686, 610), fill="#F7FBFC")
    draw.ellipse(box(385, 405, 475, 522), fill="#0B1728")
    draw.ellipse(box(549, 405, 639, 522), fill="#0B1728")
    draw.ellipse(box(411, 430, 450, 479), fill="#37C8F2")
    draw.ellipse(box(575, 430, 614, 479), fill="#37C8F2")
    draw.ellipse(box(424, 438, 442, 458), fill="#FFFFFF")
    draw.ellipse(box(588, 438, 606, 458), fill="#FFFFFF")
    draw.polygon([point(512, 493), point(570, 542), point(512, 572), point(454, 542)], fill="#FFB338")

    # 水色のマフラー。生成原画と同じ識別要素を残す。
    draw.polygon([point(329, 566), point(695, 566), point(661, 655), point(363, 655)], fill="#20BFE7")
    draw.polygon([point(648, 613), point(835, 665), point(724, 741), point(635, 654)], fill="#20BFE7")

    # ひれ足と氷晶の星。
    draw.ellipse(box(326, 830, 493, 918), fill="#F2A72E")
    draw.ellipse(box(531, 830, 698, 918), fill="#F2A72E")
    for x, y in [(108, 132), (900, 150), (136, 520), (880, 484)]:
        draw.polygon([point(x, y - 22), point(x + 8, y - 7), point(x + 22, y), point(x + 8, y + 7), point(x, y + 22), point(x - 8, y + 7), point(x - 22, y), point(x - 8, y - 7)], fill="#FFFFFF")

    return image


def save() -> None:
    APP_ICON_DIR.mkdir(parents=True, exist_ok=True)
    LAUNCH_MARK_DIR.mkdir(parents=True, exist_ok=True)
    icon = make_icon(1024)
    for name in ["AppIcon1024x1024.png", "AppIcon1024x1024 1.png", "AppIcon1024x1024 2.png"]:
        icon.save(APP_ICON_DIR / name, optimize=True, compress_level=9)
    launch = make_icon(512)
    for name in ["LaunchMark.png", "LaunchMarkDark.png"]:
        launch.save(LAUNCH_MARK_DIR / name, optimize=True, compress_level=9)


if __name__ == "__main__":
    save()
