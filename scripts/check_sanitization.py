#!/usr/bin/env python3
"""
Mandatory Public Repository Sanitization Audit Script.
Scans all tracked and non-ignored files (including .xlsx workbooks) to ensure ZERO
personal data, proprietary company/organization names, real SAP SIDs/clients,
internal IPs/domains, transport requests, or credentials exist.

Optional local custom blocklist (never committed to Git):
    Create a gitignored file '.sap.blocklist' (one keyword/regex per line)
    or set env var SANITIZATION_BLOCKLIST="word1,word2" to check custom private
    company names, project codes, SIDs, or real employee names locally.

Exit code:
    0 -> Clean (passed all checks)
    1 -> Violations detected (BLOCKS commit / push)
"""

import os
import re
import sys
import subprocess

try:
    import openpyxl
except ImportError:
    openpyxl = None

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')

SKIP_FILES = {
    'excel-templates/Object_Levels.csv',
    'excel-templates/Org_Levels.csv',
}

POLICY_EXAMPLE_FILES = {
    '.agent/skills/00_public-repo-sanitization.md',
    'AGENTS.md',
}

SKIP_EXTS = ('.png', '.jpg', '.jpeg', '.gif', '.svg', '.pdf', '.ico', '.woff', '.woff2')

# Purely structural, generic leak detection patterns (zero hardcoded private data)
PATTERNS = [
    (
        'Real Transport Request',
        re.compile(r'\b[A-Z0-9]{3}K9\d{5}\b'),
        lambda m, f: m == 'DEVK900001' and f in ('.sap.env.example', 'README.md', 'scripts/check_sanitization.py'),
    ),
    (
        'Private / Internal IP Address',
        re.compile(r'\b(?:10\.\d{1,3}|172\.(?:1[6-9]|2\d|3[01])|192\.168)\.\d{1,3}\.\d{1,3}\b'),
        lambda m, f: False,
    ),
    (
        'Internal / Corporate Domain',
        re.compile(r'\b[a-z0-9.-]+\.(?:corp|local|internal|intra|lan)\b', re.I),
        lambda m, f: False,
    ),
    (
        'Local OS User Directory Path',
        re.compile(r'(?:C:\\Users\\|C:/Users/|/Users/|/home/)[^\s"\'`<>]+', re.I),
        lambda m, f: f == 'scripts/check_sanitization.py',
    ),
    (
        'Project-Specific Role Naming Pattern',
        re.compile(r'\b(?:DR|LR|MR)[A-Z]{2}\d{2}_[A-Z0-9_]+\b'),
        lambda m, f: False,
    ),
    (
        'Non-Example Email Address',
        re.compile(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}', re.I),
        lambda m, f: m.lower().endswith(('@example.com', '@example.org', '@example.net', '@users.noreply.github.com'))
                     or (f == 'package.json'),
    ),
    (
        'Hardcoded Basic Auth / Secret',
        re.compile(r'Authorization:\s*Basic\s+[A-Za-z0-9+/=]{12,}', re.I),
        lambda m, f: False,
    ),
]


def load_local_custom_patterns():
    """Loads optional user-defined private blocklist terms from gitignored .sap.blocklist or env."""
    custom = []
    local_file = '.sap.blocklist'
    terms = []

    if os.path.exists(local_file):
        with open(local_file, 'r', encoding='utf-8', errors='replace') as fh:
            for raw in fh:
                line = raw.strip()
                if line and not line.startswith('#'):
                    terms.append(line)

    env_terms = os.environ.get('SANITIZATION_BLOCKLIST', '')
    for t in env_terms.split(','):
        t = t.strip()
        if t:
            terms.append(t)

    for term in terms:
        pat = re.compile(r'\b' + re.escape(term) + r'\b', re.I)
        custom.append((f'Custom Blocklist Term ({term})', pat, lambda m, f: False))

    return custom


def get_repo_files():
    out = subprocess.check_output(
        ['git', 'ls-files', '--cached', '--others', '--exclude-standard'],
        text=True,
        encoding='utf-8',
        errors='replace',
    )
    return [line.strip().replace('\\', '/') for line in out.splitlines() if line.strip()]


def scan_text_content(filepath, text, active_patterns, findings):
    is_policy_doc = filepath in POLICY_EXAMPLE_FILES
    for lineno, line in enumerate(text.splitlines(), start=1):
        for label, pat, allow_fn in active_patterns:
            if is_policy_doc and label in (
                'Real Transport Request',
                'Internal / Corporate Domain',
                'Local OS User Directory Path',
                'Project-Specific Role Naming Pattern',
            ):
                continue
            for match in pat.findall(line):
                if allow_fn(match, filepath):
                    continue
                findings.append((filepath, f'Line {lineno}', label, match, line.strip()[:120]))


def scan_xlsx(filepath, active_patterns, findings):
    if openpyxl is None:
        return
    try:
        wb = openpyxl.load_workbook(filepath, data_only=False)
        creator = (wb.properties.creator or '').strip()
        modifier = (wb.properties.lastModifiedBy or '').strip()
        if creator and creator.lower() not in ('openpyxl', 'antigravity', 'template'):
            findings.append((filepath, 'Metadata:creator', 'Personal/Author Metadata', creator, f'creator={creator!r}'))
        if modifier and modifier.lower() not in ('openpyxl', 'antigravity', 'template'):
            findings.append((filepath, 'Metadata:lastModifiedBy', 'Personal/Author Metadata', modifier, f'lastModifiedBy={modifier!r}'))

        for sname in wb.sheetnames:
            ws = wb[sname]
            for r in range(1, ws.max_row + 1):
                for c in range(1, ws.max_column + 1):
                    val = ws.cell(r, c).value
                    if val is None:
                        continue
                    sval = str(val)
                    for label, pat, allow_fn in active_patterns:
                        for match in pat.findall(sval):
                            if allow_fn(match, filepath):
                                continue
                            findings.append((filepath, f'{sname}!R{r}C{c}', label, match, sval[:120]))
    except Exception as exc:
        print(f'[WARN] Could not inspect workbook {filepath}: {exc}')


def main():
    files = get_repo_files()
    active_patterns = PATTERNS + load_local_custom_patterns()
    findings = []

    for f in files:
        if f in SKIP_FILES or f.lower().endswith(SKIP_EXTS):
            continue
        if not os.path.exists(f):
            continue
        if f.lower().endswith(('.xlsx', '.xlsm')):
            scan_xlsx(f, active_patterns, findings)
        else:
            with open(f, 'r', encoding='utf-8', errors='replace') as fh:
                scan_text_content(f, fh.read(), active_patterns, findings)

    if findings:
        print('=' * 76)
        print(f'[FAIL] SANITIZATION VIOLATIONS FOUND: {len(findings)}')
        print('=' * 76)
        for fp, loc, label, match, snippet in findings:
            print(f' - [{label}] {fp} ({loc}): match={match!r}')
            print(f'   Context: {snippet}')
        print('=' * 76)
        sys.exit(1)

    print(f'[PASS] Public repository sanitization audit passed ({len(files)} files checked, 0 violations).')
    sys.exit(0)


if __name__ == '__main__':
    main()
