#!/usr/bin/env python3
"""Reject an exported IPA when the native speech detector cannot be loaded."""
import argparse
from pathlib import Path
import plistlib
import subprocess
import tempfile
import zipfile


def verify(ipa: Path) -> None:
    with zipfile.ZipFile(ipa) as archive, tempfile.TemporaryDirectory() as tmp:
        info_name = next(
            name for name in archive.namelist()
            if name.startswith('Payload/') and name.count('/') == 2
            and name.endswith('/Info.plist')
        )
        info = plistlib.loads(archive.read(info_name))
        app = info_name.rsplit('/', 1)[0]
        executable = f"{app}/{info['CFBundleExecutable']}"
        binary = Path(tmp) / 'Runner'
        binary.write_bytes(archive.read(executable))
        exports = subprocess.check_output(
            ['xcrun', 'dyld_info', '-exports', str(binary)], text=True,
        )
        if '_OrtGetApiBase' not in exports.split():
            raise SystemExit('FAIL: IPA does not export OrtGetApiBase; speech startup will fail.')
        model = f'{app}/Frameworks/App.framework/flutter_assets/assets/vad/silero_vad_v5.onnx'
        if archive.getinfo(model).file_size < 1_000_000:
            raise SystemExit('FAIL: bundled speech model is missing or incomplete.')
        print(f"PASS: {info['CFBundleIdentifier']} {info['CFBundleShortVersionString']} "
              f"({info['CFBundleVersion']}): native speech symbol exported and model bundled.")


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ipa', type=Path)
    verify(parser.parse_args().ipa)
