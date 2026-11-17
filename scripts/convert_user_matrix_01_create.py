#!/usr/bin/env python3
"""
Convert SAP Authorization Matrix (User Assignment workbook) to flat normalized CSV
for ABAP batch user creation program Z_USER_01_CREATE (via BAPI_USER_CREATE1).

Designed for full multi-header Authorization Matrix Excel workbooks where banner/category
rows precede the actual column header row and additional metadata columns
(e.g., #, User ID, Initial Password, Employee ID, Location, Organization name, User type)
appear alongside standard user fields.

Output columns:
1. Username
2. Full Name
3. Email
4. Phone No.
5. Department
6. Function
7. Initial Password

Output:
- <parent_dir>/converted/<stem>_01_Create_converted.csv (UTF-8 with BOM)
- <parent_dir>/converted/<stem>_Create_Parameter_converted.csv (UTF-8 with BOM, from sheet 'User Default')

Usage:
    python scripts/convert_user_matrix_01_create.py [input_excel_file] [--output-dir <dir>] [--keep-password]
"""

import os
import sys
import re
import csv
import glob
import argparse
import openpyxl

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')

SUPPRESS_EMAIL_KEYWORDS = (
    'không gán mail',
    'khong gan mail',
    'tránh spam',
    'trainh spam',
    'tranh spam',
)

DEPARTMENT_CORRECTIONS = {
    'ketoan': 'Kế toán',
    'ke toan': 'Kế toán',
    'kế toán': 'Kế toán',
    'kt': 'Kế toán',
    'accounting': 'Accounting',
    'finance': 'Finance',
    'taichinh': 'Tài chính',
    'tai chinh': 'Tài chính',
    'tài chính': 'Tài chính',
    'it': 'IT',
    'công nghệ thông tin': 'IT',
    'ban cntt': 'IT',
    'muahang': 'Mua hàng',
    'mua hang': 'Mua hàng',
    'mua hàng': 'Mua hàng',
    'procurement': 'Procurement',
    'purchasing': 'Purchasing',
    'ban kiem soat noi bo': 'Ban Kiểm soát nội bộ',
    'kiem soat noi bo': 'Ban Kiểm soát nội bộ',
    'internal audit': 'Internal Audit',
    'hr': 'HR',
    'nhansu': 'Nhân sự',
    'nhân sự': 'Nhân sự',
    'kinhdoanh': 'Kinh doanh',
    'kinh doanh': 'Kinh doanh',
    'sales': 'Sales',
}

HEADER_SCORE_KEYWORDS = (
    'full name', 'fullname', 'họ và tên', 'ho va ten', 'họ tên',
    'email', 'e-mail',
    'phone', 'điện thoại', 'dien thoai',
    'department', 'phòng ban', 'phong ban', 'bộ phận', 'bo phan',
    'function', 'chức danh', 'chuc danh', 'chức vụ', 'chuc vu',
    'initial password', 'password',
)


def normalize_header(val):
    """Collapses whitespace and newlines in a header cell."""
    return " ".join(str(val or '').split()).strip()


def format_sap_phone(raw_phone):
    """Normalizes phone numbers to (<CountryCode>)<Number> without '+' sign."""
    if not raw_phone:
        return ""

    digits_only = re.sub(r'\D', '', str(raw_phone).strip())
    if not digits_only:
        return ""

    if digits_only.startswith('0') and len(digits_only) in (10, 11):
        return f"(84){digits_only[1:]}"
    if digits_only.startswith('84') and len(digits_only) in (11, 12):
        return f"(84){digits_only[2:]}"
    if digits_only.startswith('1') and len(digits_only) == 11:
        return f"(1){digits_only[1:]}"
    if len(digits_only) >= 10:
        return f"({digits_only[:2]}){digits_only[2:]}"

    return digits_only


def normalize_casing(text):
    """Collapses repeated whitespace while preserving character casing."""
    if not text:
        return ""
    return " ".join(str(text).split())


def clean_department(dep_text):
    """Normalizes whitespace and applies standard department spelling corrections."""
    if not dep_text:
        return ""
    norm = normalize_casing(dep_text).strip()
    return DEPARTMENT_CORRECTIONS.get(norm.lower(), norm)


def clean_function(func_text):
    """Normalizes whitespace while preserving acronyms and casing in job titles."""
    if not func_text:
        return ""
    return normalize_casing(func_text).strip()


def find_target_sheet(wb):
    """Selects the user assignment matrix sheet from the workbook."""
    preferred_exact = ('user asignment', 'user assignment')
    for name in wb.sheetnames:
        if name.strip().lower() in preferred_exact:
            return wb[name]

    for name in wb.sheetnames:
        low = name.strip().lower()
        if any(k in low for k in ('asignment', 'assignment', 'asign', 'assign', 'nguoi', 'danh sach')):
            if 'contact' not in low:
                return wb[name]

    for name in wb.sheetnames:
        low = name.strip().lower()
        if 'user' in low and 'default' not in low and 'contact' not in low:
            return wb[name]

    return wb.active


def detect_header_row(ws, max_scan_rows=15):
    """Scans top rows to locate the actual table header row in multi-header matrices."""
    best_row = 1
    best_score = -1

    scan_limit = min(max_scan_rows, ws.max_row)
    scan_cols = min(50, ws.max_column)

    for r in range(1, scan_limit + 1):
        score = 0
        for c in range(1, scan_cols + 1):
            low = normalize_header(ws.cell(r, c).value).lower()
            if not low:
                continue
            if any(kw in low for kw in HEADER_SCORE_KEYWORDS):
                score += 1
        if score > best_score:
            best_score = score
            best_row = r

    return best_row if best_score >= 3 else 1


def detect_user_columns(ws, header_row):
    """Maps logical user fields from the detected header row."""
    cols = {
        'user': None,
        'name': None,
        'email': None,
        'phone': None,
        'dept': None,
        'func': None,
        'pwd': None,
    }

    for col in range(1, ws.max_column + 1):
        low = normalize_header(ws.cell(header_row, col).value).lower()
        if not low:
            continue

        is_user_hdr = (
            low == 'user'
            or low.startswith('user ')
            or low.startswith('user(')
            or any(k in low for k in ('user id', 'userid', 'username', 'tài khoản', 'tai khoan', 'bname'))
        ) and 'type' not in low

        if is_user_hdr and cols['user'] is None:
            cols['user'] = col
        elif any(k in low for k in ('ho va ten', 'họ và tên', 'full name', 'fullname', 'họ tên', 'họ & tên')) and cols['name'] is None:
            cols['name'] = col
        elif 'name' in low and 'organization' not in low and 'role' not in low and cols['name'] is None:
            cols['name'] = col
        elif any(k in low for k in ('email', 'e-mail', 'mail')) and cols['email'] is None:
            cols['email'] = col
        elif any(k in low for k in ('dien thoai', 'điện thoại', 'phone', 'sđt', 'tel')) and cols['phone'] is None:
            cols['phone'] = col
        elif any(k in low for k in ('phong ban', 'phòng ban', 'bo phan', 'bộ phận', 'department', 'dept')) and cols['dept'] is None:
            cols['dept'] = col
        elif any(k in low for k in ('chuc danh', 'chức danh', 'vi tri', 'vị trí', 'function', 'chức vụ', 'title')) and cols['func'] is None:
            cols['func'] = col
        elif any(k in low for k in ('initial password', 'password', 'pwd', 'pass', 'mật khẩu', 'mat khau')) and cols['pwd'] is None:
            cols['pwd'] = col

    return cols


def row_has_email_suppression(ws, row):
    """Checks all cells on a row for email suppression directives."""
    for col_idx in range(1, ws.max_column + 1):
        val = ws.cell(row, col_idx).value
        if val is None:
            continue
        low = str(val).strip().lower()
        if low and any(kw in low for kw in SUPPRESS_EMAIL_KEYWORDS):
            return True
    return False


def resolve_output_path(input_path, output_dir, suffix_token):
    """Builds the target CSV output path under <parent_dir>/converted/ by default."""
    base_name = os.path.basename(input_path)
    stem, _ = os.path.splitext(base_name)

    if stem.endswith(suffix_token) or stem.endswith(suffix_token.lstrip('_')):
        out_csv_name = f"{stem}_converted.csv"
    elif stem.endswith('_converted'):
        out_csv_name = f"{stem}.csv"
    else:
        out_csv_name = f"{stem}{suffix_token}_converted.csv"

    if output_dir is None:
        dir_name = os.path.dirname(input_path) or "."
        output_dir = os.path.join(dir_name, "converted")

    if output_dir.endswith('.csv'):
        if os.path.dirname(output_dir):
            os.makedirs(os.path.dirname(output_dir), exist_ok=True)
        return output_dir

    os.makedirs(output_dir, exist_ok=True)
    return os.path.join(output_dir, out_csv_name)


def convert_user_matrix_01_create(input_path, output_dir=None, include_password=False):
    """Reads an Authorization Matrix workbook and exports Z_USER_01_CREATE flat CSV."""
    if not os.path.splitext(input_path)[1]:
        input_path = input_path + ".xlsx"

    if not os.path.exists(input_path):
        print(f"[ERROR] Input file not found: {input_path}")
        sys.exit(1)

    out_csv_path = resolve_output_path(input_path, output_dir, "_01_Create")

    try:
        wb_in = openpyxl.load_workbook(input_path, data_only=True)
    except Exception as e:
        print(f"[ERROR] Could not read Excel workbook '{input_path}': {e}")
        sys.exit(1)

    ws = find_target_sheet(wb_in)
    header_row = detect_header_row(ws)
    cols = detect_user_columns(ws, header_row)

    print(f"[INFO] Processing sheet: '{ws.title}' (Header row: {header_row})")
    print(
        f"[INFO] Header mapping -> User: Col {cols['user']}, Name: Col {cols['name']}, "
        f"Email: Col {cols['email']}, Phone: Col {cols['phone']}, Dept: Col {cols['dept']}, "
        f"Func: Col {cols['func']}, Pwd: Col {cols['pwd']} (include={include_password})"
    )

    records = []
    skipped_empty = 0
    phone_formatted_count = 0
    missing_email_symbol_count = 0
    emails_suppressed_count = 0
    generated_usernames = set()

    for row in range(header_row + 1, ws.max_row + 1):
        raw_name = str(ws.cell(row, cols['name']).value or '').strip() if cols['name'] else ''
        raw_email = str(ws.cell(row, cols['email']).value or '').strip() if cols['email'] else ''
        raw_user = str(ws.cell(row, cols['user']).value or '').strip() if cols['user'] else ''
        raw_phone = ws.cell(row, cols['phone']).value if cols['phone'] else None
        raw_dept = str(ws.cell(row, cols['dept']).value or '').strip() if cols['dept'] else ''
        raw_func = str(ws.cell(row, cols['func']).value or '').strip() if cols['func'] else ''
        raw_pwd = str(ws.cell(row, cols['pwd']).value or '').strip() if (include_password and cols['pwd']) else ''

        if not raw_name and not raw_email and not raw_user:
            skipped_empty += 1
            continue

        suppress_email = row_has_email_suppression(ws, row)

        if '@' in raw_email:
            username = raw_email.split('@')[0].strip().upper()
        elif raw_email and not suppress_email:
            username = raw_email.strip().upper()
            missing_email_symbol_count += 1
        elif raw_user:
            username = raw_user.upper()
        else:
            cleaned_tokens = re.sub(r'[^a-zA-Z0-9]', '', raw_name)
            username = cleaned_tokens[:12].upper() if cleaned_tokens else f"USER_{row}"

        base_username = username
        counter = 1
        while username in generated_usernames:
            username = f"{base_username[:10]}_{counter}"
            counter += 1
        generated_usernames.add(username)

        email = '' if suppress_email else raw_email.lower()
        if suppress_email:
            emails_suppressed_count += 1

        phone = format_sap_phone(raw_phone)
        if phone:
            phone_formatted_count += 1

        records.append({
            'username': username,
            'fullname': normalize_casing(raw_name),
            'email': email,
            'phone': phone,
            'department': clean_department(raw_dept),
            'function': clean_function(raw_func),
            'password': raw_pwd,
        })

    try:
        with open(out_csv_path, 'w', newline='', encoding='utf-8-sig') as f:
            writer = csv.writer(f)
            writer.writerow([
                "Username",
                "Full Name",
                "Email",
                "Phone No.",
                "Department",
                "Function",
                "Initial Password",
            ])
            for r in records:
                writer.writerow([
                    r['username'],
                    r['fullname'],
                    r['email'],
                    r['phone'],
                    r['department'],
                    r['function'],
                    r['password'],
                ])
    except PermissionError:
        print(f"[ERROR] Permission denied when writing to '{out_csv_path}'. Please close the file in Excel and try again.")
        sys.exit(1)

    print("\n--- Execution Summary ---")
    print(f"[OK] Input File       : {input_path}")
    print(f"[OK] Output CSV       : {out_csv_path} ({len(records)} data rows)")
    print(f"[OK] Total Users      : {len(records)} generated ({len(generated_usernames)} unique usernames)")
    print(f"[OK] Phones Formatted : {phone_formatted_count} normalized to SAP format")
    if missing_email_symbol_count > 0:
        print(f"[INFO] Non-@ Accounts : {missing_email_symbol_count} raw IDs directly converted to Username")
    if emails_suppressed_count > 0:
        print(f"[INFO] Emails Suppressed: {emails_suppressed_count} user(s)")
    if skipped_empty > 0:
        print(f"[INFO] Skipped Empty  : {skipped_empty} empty row(s)")

    return out_csv_path, len(records)


def find_user_default_sheet(wb):
    """Locates the 'User Default' parameter sheet in the workbook."""
    for name in wb.sheetnames:
        if normalize_header(name).lower() == 'user default':
            return wb[name]
    for name in wb.sheetnames:
        low = normalize_header(name).lower()
        if 'user default' in low or ('default' in low and 'user' in low) or 'parameter' in low:
            return wb[name]
    return None


def detect_param_header_and_cols(ws, max_scan_rows=10):
    """Detects header row and columns (Parameter ID, Parameter Value, Description) on User Default sheet."""
    scan_rows = min(max_scan_rows, ws.max_row)
    scan_cols = min(20, ws.max_column)

    for r in range(1, scan_rows + 1):
        cols = {'pid': None, 'val': None, 'desc': None}
        for c in range(1, scan_cols + 1):
            low = normalize_header(ws.cell(r, c).value).lower()
            if not low:
                continue
            if any(k in low for k in ('parameter id', 'paramater id', 'param id', 'parid')) and cols['pid'] is None:
                cols['pid'] = c
            elif any(k in low for k in ('parameter value', 'paramater value', 'param value', 'parva')) and cols['val'] is None:
                cols['val'] = c
            elif ('value' in low and 'parameter' not in low and 'paramater' not in low) and cols['val'] is None:
                cols['val'] = c
            elif any(k in low for k in ('description', 'mô tả', 'mo ta', 'desc')) and cols['desc'] is None:
                cols['desc'] = c
        if cols['pid'] is not None and cols['val'] is not None:
            return r, cols

    return 2, {'pid': 2, 'val': 3, 'desc': 4}


def convert_user_matrix_01_parameter(input_path, output_dir=None):
    """Reads sheet 'User Default' and exports Z_USER_01_CREATE Parameter CSV."""
    if not os.path.splitext(input_path)[1]:
        input_path = input_path + ".xlsx"

    if not os.path.exists(input_path):
        print(f"[ERROR] Input file not found: {input_path}")
        sys.exit(1)

    try:
        wb_in = openpyxl.load_workbook(input_path, data_only=True)
    except Exception as e:
        print(f"[ERROR] Could not read Excel workbook '{input_path}': {e}")
        sys.exit(1)

    ws = find_user_default_sheet(wb_in)
    if ws is None:
        print(f"[WARN] Sheet 'User Default' not found in '{input_path}'. Skipping parameter CSV export.")
        return None, 0

    header_row, cols = detect_param_header_and_cols(ws)
    out_csv_path = resolve_output_path(input_path, output_dir, "_Create_Parameter")

    print(
        f"[INFO] Processing sheet: '{ws.title}' (Header row: {header_row}, "
        f"ID: Col {cols['pid']}, Value: Col {cols['val']}, Desc: Col {cols['desc']})"
    )

    param_records = []
    seen_pids = set()

    for row in range(header_row + 1, ws.max_row + 1):
        val_pid = ws.cell(row, cols['pid']).value if cols['pid'] else None
        raw_pid = normalize_header(val_pid).upper()
        if not raw_pid:
            continue

        val_cell = ws.cell(row, cols['val']).value if cols['val'] else None
        raw_val = "" if val_cell is None else str(val_cell).strip()

        val_desc = ws.cell(row, cols['desc']).value if cols['desc'] else None
        raw_desc = normalize_casing(str(val_desc or '')).strip()

        if raw_pid in seen_pids:
            for rec in param_records:
                if rec['parid'] == raw_pid:
                    rec['parva'] = raw_val
                    rec['desc'] = raw_desc
                    break
        else:
            seen_pids.add(raw_pid)
            param_records.append({
                'parid': raw_pid,
                'parva': raw_val,
                'desc': raw_desc,
            })

    try:
        with open(out_csv_path, 'w', newline='', encoding='utf-8-sig') as f:
            writer = csv.writer(f)
            writer.writerow(["Parameter ID", "Parameter Value", "Description"])
            for r in param_records:
                writer.writerow([r['parid'], r['parva'], r['desc']])
    except PermissionError:
        print(f"[ERROR] Permission denied when writing to '{out_csv_path}'. Please close the file in Excel and try again.")
        sys.exit(1)

    print(f"[OK] Parameter CSV    : {out_csv_path} ({len(param_records)} parameter row(s))")
    return out_csv_path, len(param_records)


def resolve_default_matrix_file():
    """Finds an Authorization Matrix user workbook in excel-working/ without hardcoding entity names."""
    patterns = [
        os.path.join("excel-working", "*Authorization Matrix*Assign User*.xlsx"),
        os.path.join("excel-working", "*Matrix*Assign*User*.xlsx"),
        "*Authorization Matrix*Assign User*.xlsx",
    ]
    for pat in patterns:
        matches = sorted(glob.glob(pat))
        matches = [m for m in matches if not os.path.basename(m).startswith("~$")]
        if matches:
            return matches[0]
    return None


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Convert Authorization Matrix Excel to Z_USER_01_CREATE CSVs.")
    parser.add_argument("input_file", nargs="?", default=None, help="Path to Authorization Matrix Excel file")
    parser.add_argument("--output-dir", "-o", default=None, help="Custom output directory or .csv path")
    parser.add_argument("--keep-password", action="store_true", help="Include Initial Password column values instead of leaving empty")
    args = parser.parse_args()

    target_file = args.input_file or resolve_default_matrix_file()
    if not target_file:
        print("[ERROR] No Authorization Matrix Excel file provided or found in excel-working/.")
        sys.exit(1)

    convert_user_matrix_01_create(target_file, args.output_dir, include_password=args.keep_password)
    param_out_dir = (os.path.dirname(args.output_dir) or ".") if (args.output_dir and args.output_dir.endswith('.csv')) else args.output_dir
    convert_user_matrix_01_parameter(target_file, param_out_dir)
