#!/usr/bin/env python3
"""Write ignored Harmony local configuration from protected files, without logging secrets."""
import argparse
import json
import os
from pathlib import Path
import shlex
import stat
import subprocess
import sys
import tempfile
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]


def protected_text(path: Path) -> str:
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_mode & 0o077:
        raise ValueError(f"受控输入必须是权限 0600 的普通文件: {path}")
    if info.st_uid != os.getuid():
        raise ValueError(f"受控输入必须属于当前用户: {path}")
    return path.read_text(encoding="utf-8").strip()


def openssl_output(arguments: list[str], value: str) -> bytes:
    result = subprocess.run(
        ["openssl", *arguments], input=value.encode(), capture_output=True, check=False
    )
    if result.returncode:
        raise ValueError("本地 RSA 密钥格式验证失败，原配置未修改")
    return result.stdout


def configure(args: argparse.Namespace) -> None:
    parsed = urlparse(args.url)
    if parsed.scheme not in ("http", "https") or not parsed.hostname:
        raise ValueError("Unified URL 必须包含 http(s) 协议和主机")
    if parsed.username or parsed.password or parsed.query or parsed.fragment or parsed.path not in ("", "/"):
        raise ValueError("Unified URL 只能包含协议、主机和端口")
    if parsed.hostname in ("localhost", "127.0.0.1", "::1"):
        raise ValueError("手机配置必须使用可达的局域网地址，不能使用 localhost")

    pnvs_path = args.pnvs_file
    pnvs = protected_text(pnvs_path) if pnvs_path.exists() else ""
    if not pnvs and not args.build_only:
        raise ValueError("PNVS SDK 密钥尚未恢复；默认拒绝生成。仅构建检查可显式使用 --build-only")
    if pnvs and ("PLACEHOLDER" in pnvs.upper() or pnvs.startswith("<")):
        raise ValueError("PNVS SDK 密钥不能是占位值")

    required = {"LINGAI_LOCAL_APP_ID", "LINGAI_LOCAL_APP_KEY"}
    values = {}
    for line in protected_text(args.unified_local / "runtime.env").splitlines():
        key, separator, raw = line.partition("=")
        if separator and key.strip() in required:
            parts = shlex.split(raw, comments=True)
            if len(parts) != 1:
                raise ValueError("Unified 本地应用变量格式无效")
            values[key.strip()] = parts[0]
    if values.get("LINGAI_LOCAL_APP_ID") != "1" or not values.get("LINGAI_LOCAL_APP_KEY"):
        raise ValueError("Unified 本地应用必须包含编号 1 和非空 app key")

    private_key = protected_text(args.unified_local / "app-private.pem") + "\n"
    public_key = protected_text(args.unified_local / "app-public.pem") + "\n"
    if not private_key.startswith("-----BEGIN PRIVATE KEY-----"):
        raise ValueError("本地签名私钥必须是 PKCS#8 PEM")
    derived = openssl_output(["rsa", "-pubout", "-outform", "DER"], private_key)
    public_description = openssl_output(["pkey", "-pubin", "-text", "-noout"], public_key)
    if b"(2048 bit)" not in public_description:
        raise ValueError("本地签名公钥必须是 RSA2048")
    registered = openssl_output(["pkey", "-pubin", "-pubout", "-outform", "DER"], public_key)
    if derived != registered:
        raise ValueError("本地私钥与 Unified 登记的公钥不匹配")

    exported = {
        "UNIFIED_BASE_URL_DEV": args.url.rstrip("/"),
        "APP_KEY_DEV": values["LINGAI_LOCAL_APP_KEY"],
        "APP_PRIVATE_KEY_DEV": private_key,
        "PNVS_AUTH_SECRET_DEV": pnvs,
    }
    destination = ROOT / "entry/src/main/ets/local/Secret.dev.ets"
    destination.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(destination.parent, 0o700)
    content = "// 受控本地配置，由 tools/configure-local.py 生成，不提交。\n"
    content += "".join(
        f"export const {name}: string = {json.dumps(value, ensure_ascii=False)};\n"
        for name, value in exported.items()
    )
    temporary = None
    try:
        descriptor, temporary = tempfile.mkstemp(prefix=".Secret.dev.", dir=destination.parent)
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(content)
        os.replace(temporary, destination)
    finally:
        if temporary and Path(temporary).exists():
            Path(temporary).unlink()
    print(f"已生成权限 0600 的本地配置: {destination}")
    print("PNVS SDK 密钥已提供，仍需匹配最终签名并完成真机验证" if pnvs else "仅构建检查：PNVS 未配置，一键登录保持禁用")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--unified-local", required=True, type=Path, help="独立 Unified worktree 的受控 .local 目录")
    parser.add_argument("--url", required=True, help="手机可访问的 Unified 局域网 URL")
    parser.add_argument("--pnvs-file", type=Path, default=ROOT / ".local/pnvs-auth-secret.txt")
    parser.add_argument("--build-only", action="store_true", help="明确允许缺少 PNVS，仅用于编译检查")
    args = parser.parse_args()
    try:
        configure(args)
    except (ValueError, OSError) as error:
        print(f"配置未生成: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
