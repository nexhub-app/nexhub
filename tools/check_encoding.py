#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""NexHub 编码与硬编码中文检测脚本。

用途：
  1. 扫描 lib/、plugins/、lib/l10n/*.arb、tools/ 下的文本文件，凡非 UTF-8（无 BOM）
     即判定为编码错误（中文乱码的主要根源）。
  2. 扫描 .dart 文件中出现在字符串字面量内的中文字符（CJK），排除经过
     AppLocalizations / l10n. 引用的情形，命中即报告 file:line，防止新的硬编码中文。

CI / pre-commit 调用：
  python tools/check_encoding.py
退出码：发现任何问题返回 1，否则 0。
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

# 需要扫描的目录（相对仓库根）
SCAN_DIRS = ["lib", "plugins", "tools"]
# 需要扫描的扩展名
TEXT_EXTS = {".dart", ".arb", ".json", ".yaml", ".yml", ".md"}

# CJK 统一表意文字区（含扩展 A 的一部分）
CJK = re.compile(r"[㐀-䶿一-鿿豈-﫿]")
# 排除：经 l10n / AppLocalizations 引用（视为合法）
L10N_REF = re.compile(r"AppLocalizations|l10n\.")

# 允许包含 CJK 字符数据的 .dart 文件白名单（如繁简映射表等数据文件，
# 这些 CJK 字符是数据而非用户可见字符串，不需要走 l10n）
CJK_DATA_WHITELIST = {
    "lib/features/novel/presentation/novel_chinese_converter.dart",
    # 书源规则引擎：含广告关键词、跳过模式、分类名等 CJK 数据
    "lib/features/shuyuan/analyze/analyze_url.dart",
    "lib/features/shuyuan/analyze/rule_analyzer.dart",
    "lib/features/shuyuan/web_book/book_content.dart",
    "lib/features/shuyuan/web_book/book_info.dart",
    "lib/features/shuyuan/web_book/book_list.dart",
    "lib/features/shuyuan/web_book/web_book.dart",
    # 本地小说解析器：章节标题正则（第X章/节/回/卷）必须含 CJK 才能匹配中文小说；
    # 解析器无 BuildContext 无法访问 l10n，占位标题（未命名章节/第N章）作为数据输出。
    "lib/core/local/local_novel_parser.dart",
    # 在线筛选 Sheet：地区候选 value 是透传给 MacCMS 源 API 的协议值（中国大陆/日本/...），
    # 用户可见标签已通过 labelKey + l10n 解析；CJK 字符为数据而非 UI 文案。
    "lib/core/widgets/online_filter_sheet.dart",
}

problems: list[str] = []


def walk_files():
    for d in SCAN_DIRS:
        base = ROOT / d
        if not base.exists():
            continue
        for p in base.rglob("*"):
            if p.is_file() and p.suffix in TEXT_EXTS:
                yield p


def check_file(p: pathlib.Path) -> None:
    data = p.read_bytes()
    # 1) UTF-8 无 BOM 检测
    if data.startswith(b"\xef\xbb\xbf"):
        problems.append(f"{p.relative_to(ROOT)}: 文件含 UTF-8 BOM（应去除）")
        # BOM 文件仍尝试按 utf-8 解析以继续字面量检查
        text = data[3:].decode("utf-8", errors="replace")
    else:
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError as e:
            problems.append(f"{p.relative_to(ROOT)}: 非 UTF-8 编码（乱码风险）-> {e}")
            return

    # 2) .dart 字符串字面量内硬编码中文检测
    if p.suffix != ".dart":
        return

    # 白名单文件（CJK 数据文件）跳过硬编码中文检测
    rel = str(p.relative_to(ROOT)).replace("\\", "/")
    if rel in CJK_DATA_WHITELIST:
        return

    in_multiline_comment = False
    for i, line in enumerate(text.splitlines(), 1):
        # 处理多行注释开始
        if "/*" in line and "*/" not in line:
            in_multiline_comment = True
            continue
        # 处理多行注释结束
        if "*/" in line:
            in_multiline_comment = False
            continue
        # 在多行注释中跳过
        if in_multiline_comment:
            continue

        stripped = line.strip()
        # 跳过单行注释（行首或行内）
        if stripped.startswith("//"):
            continue
        # 提取字符串字面量部分，排除注释
        str_content = line.split("//")[0]
        # 检查字符串字面量中的中文
        if not CJK.search(str_content):
            continue
        if L10N_REF.search(str_content):
            continue
        problems.append(f"{p.relative_to(ROOT)}:{i}: 疑似硬编码中文字面量")


def main() -> int:
    for p in walk_files():
        check_file(p)
    if problems:
        print("编码/硬编码中文检测未通过：")
        for item in problems:
            print("  - " + item)
        print(f"\n共 {len(problems)} 处问题。请修正后再提交。")
        return 1
    print("✅ 编码检测通过：全部文件 UTF-8，无硬编码中文字面量。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
