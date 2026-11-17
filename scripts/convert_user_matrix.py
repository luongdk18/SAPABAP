#!/usr/bin/env python3
"""
Consolidated SAP Authorization Matrix (User Assignment) Conversion Script.
Single-command converter: reads a full multi-header Authorization Matrix Excel workbook
and generates flat CSV files matching the normalized SAP upload layout:
1. <stem>_01_Create_converted.csv -> for ABAP Z_USER_01_CREATE
2. <stem>_Create_Parameter_converted.csv -> User Parameters loaded onto Z_USER_01_CREATE screen
3. <stem>_02_Assign_converted.csv -> for ABAP Z_USER_02_ASSIGN_ROLE

Usage:
    python scripts/convert_user_matrix.py [input_excel_file] [--output-dir <directory>] [--keep-password]

Examples:
    python scripts/convert_user_matrix.py "excel-working/Authorization_Matrix_Assign_User_V1.0.xlsx"
    python scripts/convert_user_matrix.py
"""

import os
import sys
import glob
import argparse

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')

from convert_user_matrix_01_create import convert_user_matrix_01_create, convert_user_matrix_01_parameter
from convert_user_matrix_02_assign import convert_user_matrix_02_assign


def resolve_default_file():
    """Finds default Authorization Matrix workbook in excel-working/ when no path is given."""
    patterns = [
        os.path.join("excel-working", "*Authorization Matrix*Assign User*.xlsx"),
        os.path.join("excel-working", "*Matrix*Assign*User*.xlsx"),
        os.path.join("excel-working", "*Assign*User*.xlsx"),
        "*Authorization Matrix*Assign User*.xlsx",
    ]
    for pat in patterns:
        matches = sorted(glob.glob(pat))
        matches = [m for m in matches if not os.path.basename(m).startswith("~$")]
        if matches:
            return matches[0]
    return None


def convert_user_matrix_all(input_path=None, output_dir=None, include_password=False):
    """Executes both 01_Create and 02_Assign conversions from an Authorization Matrix workbook."""
    if not input_path:
        input_path = resolve_default_file()

    if not input_path:
        print("[ERROR] No Authorization Matrix input Excel file provided or found in default locations.")
        print("Usage: python scripts/convert_user_matrix.py <path_to_excel_file>")
        sys.exit(1)

    if not os.path.splitext(input_path)[1]:
        input_path = input_path + ".xlsx"

    if not os.path.exists(input_path):
        print(f"[ERROR] Input file does not exist: {input_path}")
        sys.exit(1)

    print("=" * 70)
    print("CONSOLIDATED AUTHORIZATION MATRIX USER CONVERSION")
    print(f"Input File: {input_path}")
    print("=" * 70)

    print("\n[STEP 1/3] Converting User Master Data (Z_USER_01_CREATE)...")
    out_create, count_create = convert_user_matrix_01_create(
        input_path,
        output_dir,
        include_password=include_password,
    )

    print("\n[STEP 2/3] Converting User Default Parameters (Z_USER_01_CREATE)...")
    out_param, count_param = convert_user_matrix_01_parameter(input_path, output_dir)

    print("\n[STEP 3/3] Converting Role Assignment Matrix (Z_USER_02_ASSIGN_ROLE)...")
    out_assign, count_assign = convert_user_matrix_02_assign(input_path, output_dir)

    print("\n" + "=" * 70)
    print("MATRIX CONVERSION COMPLETED SUCCESSFULLY (CSV FILES READY)")
    print("=" * 70)
    print(f"Source Excel     : {input_path}")
    print(f"1. User Creation : {out_create} ({count_create} users -> Z_USER_01_CREATE)")
    if out_param:
        print(f"2. User Params   : {out_param} ({count_param} parameters -> Z_USER_01_CREATE screen)")
    else:
        print("2. User Params   : (Skipped - sheet 'User Default' not found)")
    print(f"3. Role Assign   : {out_assign} ({count_assign} assignments -> Z_USER_02_ASSIGN_ROLE)")
    print("=" * 70 + "\n")
    return True


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Convert SAP Authorization Matrix User Excel to 2 flat CSV files.")
    parser.add_argument("input_file", nargs="?", default=None, help="Path to Authorization Matrix Excel file")
    parser.add_argument("--output-dir", "-o", default=None, help="Custom output directory for converted CSV files")
    parser.add_argument("--keep-password", action="store_true", help="Include Initial Password values instead of leaving blank")
    args = parser.parse_args()

    convert_user_matrix_all(args.input_file, args.output_dir, include_password=args.keep_password)
