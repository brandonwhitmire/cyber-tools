#!/usr/bin/env python3
"""Validate the OS version reported by wes.py against the systeminfo.txt filenames in the Validation set."""

from __future__ import print_function

import os
import re
import subprocess
import sys


VALIDATION_DIR = os.path.dirname(os.path.abspath(__file__))
WES_SCRIPT = os.path.join(os.path.dirname(VALIDATION_DIR), 'wes.py')


def result_marker(matches):
    marker = '\u2713' if matches else '\u2717'
    encoding = getattr(sys.stdout, 'encoding', None)
    if encoding:
        try:
            marker.encode(encoding)
        except UnicodeEncodeError:
            marker = 'OK' if matches else 'X'
    color = '\033[32m' if matches else '\033[31m'
    reset = '\033[0m'
    if not sys.stdout.isatty():
        return marker
    return '%s%s%s' % (color, marker, reset)


def parse_expected(filename):
    """Return the detectable OS generation and release from a validation file's name."""
    stem = os.path.splitext(filename)[0]
    parts = stem.split('_')
    architecture = None
    if 'x86' in parts:
        architecture = '32-bit'
    elif 'x64' in parts:
        architecture = 'x64-based'

    if parts[0] == 'srv':
        generation = parts[1].replace('r2', ' R2')
        release = None
        if len(parts) > 2 and parts[2] in ('rtm', '1607', 'u1', 'sp1', 'sp2'):
            release = parts[2]
    else:
        generation = parts[0]
        release = parts[1] if len(parts) > 1 else None

    generation_aliases = {
        'xp': 'XP',
        'vista': 'VistaT',
    }
    generation = generation_aliases.get(generation, generation)

    if generation == '10' and release == 'rtm':
        release = '1507'

    # Only modern Windows builds have a release value in wes.py's output.
    if generation not in ('10', '11', '2016', '2019', '2022'):
        release = None

    # wes.py exposes modern client/server build releases, while validation file names
    # use RTM and service-pack labels for some of those same systems.
    release_aliases = {
        ('10', 'rtm'): '1507',
        ('srv', '2019', 'rtm'): '1809',
        ('srv', '2022', None): '21H2',
    }
    if parts[0] == 'srv':
        release = release_aliases.get(('srv', generation, release), release)
        if generation == '2003 R2':
            # systeminfo cannot distinguish Server 2003 from Server 2003 R2.
            generation = '2003'

    return generation, release, architecture


def parse_detected(output):
    generation_match = re.search(r'^\s+- Generation:[ \t]*([^\r\n]*)', output, re.MULTILINE)
    version_match = re.search(r'^\s+- Version:[ \t]*([^\r\n]*)', output, re.MULTILINE)
    architecture_match = re.search(r'^\s+- Architecture:[ \t]*([^\r\n]*)', output, re.MULTILINE)
    if not generation_match or not version_match or not architecture_match:
        raise ValueError('OS information was not present in wes.py output')
    architecture = architecture_match.group(1).strip().lower()
    if architecture in ('', 'x86', '32-bit'):
        architecture = '32-bit'
    elif architecture in ('x64', 'x64-based', 'x64 edition'):
        architecture = 'x64-based'
    return generation_match.group(1), version_match.group(1), architecture


def expected_label(generation, release, architecture):
    label = generation
    if release is None:
        if architecture is not None:
            return '%s (%s)' % (label, architecture)
        return label
    label = '%s (%s)' % (label, release)
    if architecture is not None:
        label += ' (%s)' % architecture
    return label


def detected_label(generation, release, architecture):
    label = generation
    if release in ('', 'None'):
        return '%s (%s)' % (label, architecture)
    return '%s (%s) (%s)' % (label, release, architecture)


def validate_file(path):
    filename = os.path.basename(path)
    expected_generation, expected_release, expected_architecture = parse_expected(filename)
    expected = expected_label(expected_generation, expected_release, expected_architecture)

    process = subprocess.Popen(
        [sys.executable, WES_SCRIPT, path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        universal_newlines=True,
    )
    stdout, stderr = process.communicate()

    if process.returncode != 0:
        return filename, expected, 'ERROR', False

    try:
        actual_generation, actual_release, actual_architecture = parse_detected(stdout)
    except ValueError:
        return filename, expected, 'ERROR', False

    detected = detected_label(actual_generation, actual_release, actual_architecture)
    matches = actual_generation == expected_generation and (
        expected_release is None or str(actual_release) == str(expected_release)
    ) and (expected_architecture is None or actual_architecture == expected_architecture)
    return filename, expected, detected, matches


def print_table(rows):
    headers = ('Systeminfo.txt filename', 'Expected OS version', 'Detected OS version', 'Match')
    widths = [len(header) for header in headers]
    for row in rows:
        widths[0] = max(widths[0], len(row[0]))
        widths[1] = max(widths[1], len(row[1]))
        widths[2] = max(widths[2], len(row[2]))
        widths[3] = max(widths[3], 1)

    format_string = '  '.join('%-' + str(width) + 's' for width in widths)
    print(format_string % headers)
    separator = tuple('-' * width for width in widths)
    print(format_string % separator)
    for filename, expected, detected, matches in rows:
        print(format_string % (filename, expected, detected, result_marker(matches)))


def main():
    if not os.path.isfile(WES_SCRIPT):
        print(
            'wes.py was not found in the parent directory of %s' % VALIDATION_DIR,
            file=sys.stderr,
        )
        return 1

    paths = [
        os.path.join(VALIDATION_DIR, name)
        for name in os.listdir(VALIDATION_DIR)
        if name.endswith('_systeminfo.txt')
    ]
    paths.sort()

    if not paths:
        print('No *_systeminfo.txt validation files found in %s' % VALIDATION_DIR, file=sys.stderr)
        return 1

    rows = []
    interrupted = False
    try:
        for path in paths:
            sys.stdout.write('Validating %s...' % os.path.basename(path))
            sys.stdout.flush()
            row = validate_file(path)
            rows.append(row)
            print(' %s' % result_marker(row[3]))
    except KeyboardInterrupt:
        print('\nValidation interrupted.')
        interrupted = True
    print_table(rows)

    passed = sum(1 for row in rows if row[3])
    print('\n%d/%d validation files matched.' % (passed, len(rows)))
    if interrupted:
        return 130
    return 0 if passed == len(rows) else 1


if __name__ == '__main__':
    sys.exit(main())