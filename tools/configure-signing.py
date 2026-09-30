#!/usr/bin/env python3
"""Isolate IDE-saved default debug signing; never decrypt passwords or modify release."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import tempfile
import time

BUNDLE = 'com.lingai.app'
APP_IDENTIFIER = '6917597519602711463'
# Explicitly approved LG-020 debug certificate. Renewal requires another review.
CERTIFICATE_SHA256 = '86a3ea78196a48435cf1afda1dd1cd5882b9400304c0777f75f976ca27976bd0'
DEVECO = Path('/Applications/DevEco-Studio.app/Contents')
FIELDS = {'certpath', 'storePassword', 'keyAlias', 'keyPassword', 'profile', 'signAlg', 'storeFile'}
PASSWORDS = ('storePassword', 'keyPassword')


class SigningError(Exception):
    """A fixed diagnostic code, never input data."""


def fail(code):
    raise SigningError(code)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def parse_json5(text):
    try:
        return json.loads(text)
    except ValueError:
        # DevEco's parser output is captured in memory, never forwarded to logs.
        script = 'const fs=require("fs");const j=require(process.argv[1]);process.stdout.write(JSON.stringify(j.parse(fs.readFileSync(0,"utf8"))));'
        parser = DEVECO / 'tools/hvigor/hvigor-ohos-plugin/node_modules/json5'
        result = subprocess.run([str(DEVECO / 'tools/node/bin/node'), '-e', script, str(parser)],
                                input=text, text=True, capture_output=True)
        if result.returncode:
            fail('CONFIG_PARSE_ERROR')
        try:
            return json.loads(result.stdout)
        except ValueError:
            fail('CONFIG_PARSE_ERROR')


# Find object spans without reformatting other configurations or products.
_TOKEN = re.compile(r'''\s+|//[^\n]*|/\*[\s\S]*?\*/|"(?:\\[\s\S]|[^"\\])*"|'(?:\\[\s\S]|[^'\\])*'|[{}\[\]:,]|[^\s{}\[\]:,]+''')


def object_spans(text):
    tokens = [m for m in _TOKEN.finditer(text)
              if not m.group().isspace() and not m.group().startswith(('//', '/*'))]
    spans = {}

    def visit(index, path):
        start = index
        token = tokens[index].group()
        if token == '{':
            index += 1
            while tokens[index].group() != '}':
                key = tokens[index].group()
                if key.startswith(('"', "'")):
                    if '\\' in key:
                        fail('ESCAPED_PROPERTY_NAME_UNSUPPORTED')
                    key = key[1:-1]
                if tokens[index + 1].group() != ':':
                    fail('CONFIG_STRUCTURE_ERROR')
                index = visit(index + 2, path + (key,))
                if tokens[index].group() == ',':
                    index += 1
                elif tokens[index].group() != '}':
                    fail('CONFIG_STRUCTURE_ERROR')
            index += 1
        elif token == '[':
            index += 1
            item = 0
            while tokens[index].group() != ']':
                index = visit(index, path + (item,))
                item += 1
                if tokens[index].group() == ',':
                    index += 1
                elif tokens[index].group() != ']':
                    fail('CONFIG_STRUCTURE_ERROR')
            index += 1
        else:
            index += 1
        if path in spans:
            fail('DUPLICATE_CONFIG_PROPERTY')
        spans[path] = (tokens[start].start(), tokens[index - 1].end())
        return index

    try:
        if visit(0, ()) != len(tokens):
            fail('CONFIG_STRUCTURE_ERROR')
    except IndexError:
        fail('CONFIG_STRUCTURE_ERROR')
    return spans


def regular_file(path, private=False):
    if path.is_symlink() or not path.is_file():
        fail('MATERIAL_REGULAR_FILE_REQUIRED')
    info = path.stat()
    if info.st_uid != os.getuid():
        fail('MATERIAL_OWNER_MISMATCH')
    if private and stat.S_IMODE(info.st_mode) != 0o600:
        fail('PRIVATE_FILE_MODE_MUST_BE_0600')
    return path.read_bytes()


def protected_directory(path):
    if path.is_symlink() or not path.is_dir():
        fail('PRIVATE_DIRECTORY_REQUIRED')
    info = path.stat()
    if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o700:
        fail('PRIVATE_DIRECTORY_MODE_MUST_BE_0700')


def openssl(*args, data=None):
    result = subprocess.run(['/usr/bin/openssl', *args], input=data, capture_output=True)
    if result.returncode:
        fail('PUBLIC_SIGNING_MATERIAL_INVALID')
    return result.stdout


def certificate_der(pem):
    return openssl('x509', '-outform', 'DER', data=pem)


def certificate_valid(pem):
    openssl('x509', '-noout', '-checkend', '0', data=pem)
    dates = openssl('x509', '-noout', '-startdate', data=pem).decode('ascii')
    try:
        start = datetime.strptime(dates.strip().split('=', 1)[1], '%b %d %H:%M:%S %Y %Z')
    except (ValueError, IndexError):
        fail('CERTIFICATE_DATE_INVALID')
    if start.replace(tzinfo=timezone.utc).timestamp() > time.time():
        fail('CERTIFICATE_NOT_YET_VALID')


def default_entry(document):
    configurations = document.get('app', {}).get('signingConfigs', [])
    matches = [(i, item) for i, item in enumerate(configurations) if item.get('name') == 'default']
    if len(matches) != 1:
        fail('EXACTLY_ONE_DEFAULT_REQUIRED')
    products = document.get('app', {}).get('products', [])
    default_products = [p for p in products if p.get('name') == 'default']
    if len(default_products) != 1 or default_products[0].get('signingConfig') != 'default':
        fail('DEFAULT_PRODUCT_BINDING_INVALID')
    if any(p.get('name') != 'default' and p.get('signingConfig') == 'default' for p in products):
        fail('DEBUG_SIGNATURE_BOUND_TO_OTHER_PRODUCT')
    return matches[0]


def validate_material(root, config, expected_fingerprint=CERTIFICATE_SHA256):
    app = parse_json5((root / 'AppScope/app.json5').read_text()).get('app', {})
    if app.get('bundleName') != BUNDLE:
        fail('PROJECT_BUNDLE_MISMATCH')
    if config.get('name') != 'default' or config.get('type') != 'HarmonyOS':
        fail('DEFAULT_SIGNING_TYPE_INVALID')
    material = config.get('material', {})
    if set(material) != FIELDS or not all(isinstance(v, str) and v for v in material.values()):
        fail('DEFAULT_MATERIAL_INCOMPLETE')
    if any(len(material[k]) < 32 for k in PASSWORDS):
        fail('IDE_ENCRYPTED_PASSWORD_CONFIGURATION_REQUIRED')
    if material['signAlg'] != 'SHA256withECDSA':
        fail('SIGNATURE_ALGORITHM_MISMATCH')
    contents = {}
    for field in ('storeFile', 'certpath', 'profile'):
        path = Path(material[field])
        if not path.is_absolute():
            path = root / path
        contents[field] = regular_file(path, private=field == 'storeFile')
    try:
        profile = json.loads(openssl('cms', '-verify', '-inform', 'DER', '-noverify', data=contents['profile']))
    except ValueError:
        fail('PROFILE_JSON_INVALID')
    info = profile.get('bundle-info', {})
    if profile.get('type') != 'debug' or info.get('bundle-name') != BUNDLE or str(info.get('app-identifier')) != APP_IDENTIFIER:
        fail('PROFILE_IDENTITY_MISMATCH')
    validity = profile.get('validity', {})
    start, end = validity.get('not-before'), validity.get('not-after')
    if not isinstance(start, (int, float)) or not isinstance(end, (int, float)) or not start <= time.time() < end:
        fail('PROFILE_EXPIRED_OR_NOT_YET_VALID')
    embedded = info.get('development-certificate')
    if not isinstance(embedded, str) or not embedded:
        fail('PROFILE_CERTIFICATE_MISSING')
    pem = embedded.encode('ascii')
    der = certificate_der(pem)
    fingerprint = digest(der)
    if fingerprint != expected_fingerprint:
        fail('APPROVED_CERTIFICATE_MISMATCH')
    certificates = re.findall(rb'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----', contents['certpath'], re.S)
    if not certificates or der not in [certificate_der(c) for c in certificates]:
        fail('PROFILE_CERTIFICATE_MISMATCH')
    certificate_valid(pem)
    return {'bundleName': BUNDLE, 'appIdentifier': APP_IDENTIFIER,
            'certificateSha256': fingerprint,
            'materialSha256': {key: digest(value) for key, value in contents.items()}}


def private_path(root):
    protected_directory(root / '.local')
    protected_directory(root / '.local/signing')
    return root / '.local/signing/default.json'


def blank_default(config):
    result = {key: value for key, value in config.items() if key != 'material'}
    result['material'] = {key: ('SHA256withECDSA' if key == 'signAlg' else '')
                          for key in config['material']}
    return result


def other_password_configurations(document):
    return [item['name'] for item in document.get('app', {}).get('signingConfigs', [])
            if item.get('name') != 'default' and
            any(item.get('material', {}).get(key) for key in PASSWORDS)]


def git_ignored(root, path):
    return subprocess.run(['git', 'check-ignore', '-q', str(path)], cwd=root, capture_output=True).returncode == 0


def check(root, expected_fingerprint=CERTIFICATE_SHA256):
    local = private_path(root)
    try:
        document = json.loads(regular_file(local, private=True))
    except ValueError:
        fail('LOCAL_CONFIG_JSON_INVALID')
    if document.get('schemaVersion') != 1:
        fail('LOCAL_CONFIG_VERSION_INVALID')
    identity = validate_material(root, document.get('signingConfig', {}), expected_fingerprint)
    if identity != document.get('identity'):
        fail('LOCAL_SIGNING_MATERIAL_CHANGED')
    source = parse_json5((root / 'build-profile.json5').read_text())
    _, default = default_entry(source)
    if default != blank_default(document['signingConfig']):
        fail('DEFAULT_SOURCE_NOT_SANITIZED')
    if not git_ignored(root, local):
        fail('LOCAL_CONFIG_MUST_BE_GIT_IGNORED')
    return {'status': 'default_ready', 'path': str(local),
            'sha256': digest(regular_file(local, private=True)),
            'other_signing_password_fields_remain': bool(other_password_configurations(source))}


def migrate(root, expected_fingerprint=CERTIFICATE_SHA256):
    source = root / 'build-profile.json5'
    before = regular_file(source)
    text = before.decode('utf8')
    document = parse_json5(text)
    index, default = default_entry(document)
    identity = validate_material(root, default, expected_fingerprint)
    local = private_path(root)
    if local.exists() or local.is_symlink():
        fail('LOCAL_CONFIG_EXISTS_NOT_OVERWRITTEN')
    if not git_ignored(root, local):
        fail('LOCAL_CONFIG_MUST_BE_GIT_IGNORED')
    start, end = object_spans(text)[('app', 'signingConfigs', index)]
    replacement = json.dumps(blank_default(default), ensure_ascii=False, indent=2)
    indent = re.match(r'\s*', text[text.rfind('\n', 0, start) + 1:start]).group()
    replacement = replacement.replace('\n', '\n' + indent)
    sanitized = (text[:start] + replacement + text[end:]).encode('utf8')
    expected = json.loads(json.dumps(document))
    expected['app']['signingConfigs'][index] = blank_default(default)
    if parse_json5(sanitized.decode('utf8')) != expected:
        fail('UNEXPECTED_CONFIGURATION_CHANGE')
    payload = (json.dumps({'schemaVersion': 1, 'identity': identity, 'signingConfig': default},
                          ensure_ascii=False, indent=2) + '\n').encode('utf8')
    fd = os.open(local, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'wb') as stream:
        stream.write(payload)
        stream.flush()
        os.fsync(stream.fileno())
    if regular_file(local, private=True) != payload:
        fail('LOCAL_CONFIG_READBACK_FAILED')
    if source.read_bytes() != before:
        fail('SOURCE_CHANGED_PRIVATE_COPY_PRESERVED')
    fd, temporary = tempfile.mkstemp(prefix='.signing-config-', dir=root / '.local/signing')
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(sanitized)
            stream.flush()
            os.fsync(stream.fileno())
        if source.read_bytes() != before:
            fail('SOURCE_CHANGED_PRIVATE_COPY_PRESERVED')
        os.replace(temporary, source)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    result = check(root, expected_fingerprint)
    result.update({'status': 'default_migrated', 'source_sha256': digest(source.read_bytes()),
                   'other_configuration_bytes_preserved': True})
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('check', 'migrate'))
    parser.add_argument('--project-root', type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    try:
        root = args.project_root.resolve()
        result = migrate(root) if args.action == 'migrate' else check(root)
        print(json.dumps(result, ensure_ascii=False))
        return 0
    except SigningError as error:
        print(json.dumps({'status': 'error', 'code': str(error)}))
        return 1
    except Exception:
        # Parser/subprocess exceptions may contain source text. Never print them.
        print(json.dumps({'status': 'error', 'code': 'SIGNING_CONFIGURATION_FAILED'}))
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
