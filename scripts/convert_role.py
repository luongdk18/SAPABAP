#!/usr/bin/env python3
"""
Consolidated SAP Role Conversion Script.
Single-command converter: locates consolidated Role Excel workbook(s)
(e.g., excel-working/MM_Roles.xlsx or excel-templates/Template_Role.xlsx)
and invokes all 4 role conversion scripts in sequence:
1. scripts/convert_role_01_master.py    -> <stem>_01_Master_converted.csv
2. scripts/convert_role_02_derive.py    -> <stem>_02_Derived_converted.csv
3. scripts/convert_role_03_org_obj.py   -> <stem>_03a_Org_Levels_converted.csv,
                                           <stem>_03b_Auth_Objects_converted.csv,
                                           <stem>_03c_Activity_converted.csv
4. scripts/convert_role_04_composite.py -> <stem>_04_Composite_converted.csv

Usage:
    python scripts/convert_role.py [input_excel_file ...] [--output-dir <directory>]

Examples:
    python scripts/convert_role.py
    python scripts/convert_role.py excel-working/MM_Roles.xlsx
    npm run convert:role
    npm run convert:role:all
"""

import os
import sys
import re
import glob
import argparse

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')

from convert_role_01_master import convert_role_01_master
from convert_role_02_derive import convert_role_02_derive
from convert_role_03_org_obj import convert_role_03_org_obj
from convert_role_04_composite import convert_role_04_composite

EXCLUDED_TOKENS = ('_01_', '_02_', '_03_', '_04_', '_converted', 'assign user', 'user_')


def is_consolidated_role_file(path):
    """Returns True if path is a consolidated Role workbook rather than a temp or per-step file."""
    name = os.path.basename(path)
    if name.startswith('~$'):
        return False
    low = name.lower()
    return not any(tok in low for tok in EXCLUDED_TOKENS)


def resolve_default_role_files():
    """Discovers consolidated Role Excel workbooks in excel-working/ or excel-templates/."""
    for folder in ("excel-working", "excel-templates"):
        candidates = sorted(
            f for f in glob.glob(os.path.join(folder, "*Role*.xlsx"))
            if is_consolidated_role_file(f)
        )
        if candidates:
            return candidates
    return []


def resolve_input_files(input_args):
    """Expands CLI paths/glob patterns or falls back to default workbook discovery."""
    if not input_args:
        return resolve_default_role_files()

    resolved = []
    for arg in input_args:
        matches = sorted(m for m in glob.glob(arg) if not os.path.basename(m).startswith('~$'))
        if matches:
            resolved.extend(matches)
        else:
            candidate = arg if os.path.splitext(arg)[1] else f"{arg}.xlsx"
            resolved.append(candidate)
    return resolved


def expected_output_paths(input_path, output_dir=None):
    """Computes the 6 CSV output paths produced by the 4 role conversion steps."""
    base_name = os.path.basename(input_path)
    stem, _ = os.path.splitext(base_name)
    out_dir = output_dir or os.path.join(os.path.dirname(input_path) or ".", "converted")

    master_name = f"{stem}_converted.csv" if stem.endswith("_01_Master") else f"{stem}_01_Master_converted.csv"
    derived_name = f"{stem}_converted.csv" if stem.endswith("_02_Derived") else f"{stem}_02_Derived_converted.csv"
    comp_name = f"{stem}_converted.csv" if stem.endswith("_04_Composite") else f"{stem}_04_Composite_converted.csv"

    clean_stem = re.sub(r'_(03[abcC]?_)?(org|object|obj|activity|actvt).*$', '', stem, flags=re.IGNORECASE)
    if not clean_stem:
        clean_stem = stem

    return [
        ("1. Master Roles  (Z_ROLE_01_CREATE_MASTER)", os.path.join(out_dir, master_name)),
        ("2. Derived Roles (Z_ROLE_02_CREATE_DERIVE)", os.path.join(out_dir, derived_name)),
        ("3a. Org Levels   (Z_ROLE_03A_UPDATE_ORG)", os.path.join(out_dir, f"{clean_stem}_03a_Org_Levels_converted.csv")),
        ("3b. Auth Objects (Z_ROLE_03B_UPDATE_OBJECT)", os.path.join(out_dir, f"{clean_stem}_03b_Auth_Objects_converted.csv")),
        ("3c. Activities   (Z_ROLE_03C_UPDATE_ACTIVITY)", os.path.join(out_dir, f"{clean_stem}_03c_Activity_converted.csv")),
        ("4. Composite     (Z_ROLE_04_CREATE_COMPOSITE)", os.path.join(out_dir, comp_name)),
    ]


def convert_role_workbook(input_path, output_dir=None):
    """Runs all 4 role conversion scripts sequentially on a single workbook."""
    if not os.path.splitext(input_path)[1]:
        input_path = f"{input_path}.xlsx"

    if not os.path.exists(input_path):
        print(f"[ERROR] Input file does not exist: {input_path}")
        return False

    print("=" * 70)
    print("CONSOLIDATED SAP ROLE CONVERSION")
    print(f"Input File: {input_path}")
    print("=" * 70)

    steps = [
        ("[STEP 1/4] Converting Master Roles (Z_ROLE_01_CREATE_MASTER)...", convert_role_01_master),
        ("[STEP 2/4] Converting Derived Roles (Z_ROLE_02_CREATE_DERIVE)...", convert_role_02_derive),
        ("[STEP 3/4] Converting Org Levels, Auth Objects & Activities (Z_ROLE_03*)...", convert_role_03_org_obj),
        ("[STEP 4/4] Converting Composite Roles (Z_ROLE_04_CREATE_COMPOSITE)...", convert_role_04_composite),
    ]

    for banner, func in steps:
        print(f"\n{banner}")
        if func(input_path, output_dir) is False:
            print(f"[ERROR] Conversion step failed for: {input_path}")
            return False

    print("\n" + "=" * 70)
    print("ROLE CONVERSION COMPLETED SUCCESSFULLY (6 CSV FILES READY)")
    print("=" * 70)
    print(f"Source Excel : {input_path}")
    for label, csv_path in expected_output_paths(input_path, output_dir):
        print(f"  {label}: {csv_path}")
    print("=" * 70 + "\n")
    return True


def convert_role_all(input_args=None, output_dir=None):
    """Resolves Role Excel workbooks and converts each through all 4 steps."""
    target_files = resolve_input_files(input_args)
    if not target_files:
        print("[ERROR] No consolidated Role Excel file provided or found in excel-working/ or excel-templates/.")
        print("Usage: python scripts/convert_role.py <path_to_role_excel>")
        return False

    all_ok = True
    for tf in target_files:
        if not convert_role_workbook(tf, output_dir):
            all_ok = False
    return all_ok


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Convert SAP Role Excel workbook(s) to 6 flat CSV files.")
    parser.add_argument("input_files", nargs="*", help="Path(s) or glob pattern(s) to Role Excel file(s)")
    parser.add_argument("--output-dir", "-o", default=None, help="Custom output directory for converted CSV files")
    args = parser.parse_args()

    if not convert_role_all(args.input_files, args.output_dir):
        sys.exit(1)
