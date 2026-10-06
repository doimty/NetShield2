"""Verify locale resources in source and optional real Theos staging directories."""
import argparse
from pathlib import Path
import plistlib
import re
import shutil
import tempfile
from check_localization import parse_strings

COMPONENTS = {'App': 'NetShield2', 'FilterData': 'NetShield2Data', 'FilterControl': 'NetShield2Control'}
LOCALES = ('en', 'zh-Hans')

def strings(path):
    data = path.read_bytes()
    if data.startswith((b'bplist00', b'<?xml')):
        return plistlib.loads(data)
    return parse_strings(data.decode('utf-8'))

def validate_localization_bundles(root, stage=None, scheme='rootless'):
    root = Path(root)
    expected = {locale: strings(root / 'Shared/Resources' / (locale + '.lproj') / 'Localizable.strings')
                for locale in LOCALES}
    app = (Path(stage) / ('var/jb/Applications/NetShield2.app' if scheme == 'rootless'
                         else 'Applications/NetShield2.app')) if stage else None
    for directory, name in COMPONENTS.items():
        make = (root / directory / 'Makefile').read_text()
        match = re.search(r'^' + name + r'_RESOURCE_DIRS\s*=\s*(.+)$', make, re.M)
        if not match or match.group(1).split() != ['Resources', '../Shared/Resources']:
            raise ValueError(f'{name}: expected own Resources and shared locale resource directory')
        info = plistlib.loads((root / directory / 'Resources/Info.plist').read_bytes())
        if info.get('CFBundleDevelopmentRegion') != 'en' or info.get('CFBundleLocalizations') != list(LOCALES):
            raise ValueError(f'{name}: inconsistent declared localization/fallback')
        if app:
            bundle = app if directory == 'App' else app / 'PlugIns' / (name + '.appex')
            for locale in LOCALES:
                path = bundle / (locale + '.lproj') / 'Localizable.strings'
                if strings(path) != expected[locale]:
                    raise ValueError(f'{name}: missing or changed {locale} translation data')
    return len(COMPONENTS) * len(LOCALES)

def self_test(root):
    checks = 0
    for scheme in ('rootless', 'roothide'):
        with tempfile.TemporaryDirectory(prefix='netshield-locale-stage-') as directory:
            stage = Path(directory)
            app = stage / ('var/jb/Applications/NetShield2.app' if scheme == 'rootless'
                           else 'Applications/NetShield2.app')
            bundles = [app, *(app / 'PlugIns' / (n + '.appex') for n in list(COMPONENTS.values())[1:])]
            for bundle in bundles:
                shutil.copytree(root / 'Shared/Resources', bundle)
            assert validate_localization_bundles(root, stage, scheme) == 6
            checks += 1
            for bundle in bundles:
                for locale in LOCALES:
                    path = bundle / (locale + '.lproj') / 'Localizable.strings'
                    original = path.read_bytes()
                    for replacement in (None, b'"wrong" = "wrong";'):
                        if replacement is None: path.unlink()
                        else: path.write_bytes(replacement)
                        try: validate_localization_bundles(root, stage, scheme)
                        except (ValueError, FileNotFoundError): pass
                        else: raise AssertionError('Missing/changed locale escaped stage validation')
                        checks += 1
                        path.write_bytes(original)
    print(f'Locale packaging fixtures: {checks} checks passed (not an iOS build).')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stage', type=Path)
    parser.add_argument('--scheme', choices=('rootless', 'roothide'), default='rootless')
    parser.add_argument('--self-test', action='store_true')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    if args.self_test: self_test(root)
    else: print(f'Validated locale packaging for {validate_localization_bundles(root, args.stage, args.scheme)} bundle/language combinations.')
