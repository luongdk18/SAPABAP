#!/usr/bin/env python3
"""
Convert SAP Users Creation Excel list to flat normalized CSV format for SAP User Batch Upload.
Prepares input file for ABAP batch user creation program Z_USER_01_CREATE (via BAPI_USER_CREATE1).

Key transformations:
1. Column 1: 'Username' - extracted from prefix before '@' in Email (or raw value if not an email), uppercased.
2. Column 2: 'Initial Password' - generated cryptographically secure 12-character password compliant with SAP S/4HANA.
3. Column 3: 'Full Name' - trimmed and normalized.
4. Column 4: 'Email' - trimmed.
5. Column 5: 'Phone No.' - standardized to unified format (<CountryCode>)<Number> without '+' sign for SAP compatibility.
6. Column 6: 'Department' - typo and casing corrections.
7. Column 7: 'Function' - typo, casing, and title-case corrections.

Output columns:
1. Username
2. Initial Password
3. Full Name
4. Email
5. Phone No.
6. Department
7. Function

Output:
- <filename>_converted.csv (UTF-8 with BOM for SAP GUI import)

Usage:
    python scripts/convert_user_01_create.py [input_excel_file]

Example:
    python scripts/convert_user_01_create.py excel-templates/Template_User_01_Create.xlsx
    -> Outputs: excel-templates/Template_User_01_Create_converted.csv
"""

import os
import sys
import re
import csv
import string
import secrets
import openpyxl

# --- Safe Console Output on Windows ---
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')

# Safe special characters for SAP S/4HANA passwords and CSV upload (no commas, quotes, or slashes)
SAFE_SPECIALS = "!@#$%*-_=+"

# Department spelling & casing corrections
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

# Function title corrections
FUNCTION_CORRECTIONS = {
    'ktt': 'Kế toán trưởng',
    'ke toan truong': 'Kế toán trưởng',
    'kế toán trưởng': 'Kế toán trưởng',
    'chief accountant': 'Chief Accountant',
    'giam doc tai chinh': 'Giám đốc Tài chính',
    'giám đốc tài chính': 'Giám đốc Tài chính',
    'cfo': 'CFO',
    'nhan vien ke toan': 'Nhân viên Kế toán',
    'nhân viên kế toán': 'Nhân viên Kế toán',
    'nv ke toan': 'Nhân viên Kế toán',
    'accountant': 'Accountant',
    'chuyen vien': 'Chuyên viên',
    'chuyên viên': 'Chuyên viên',
    'specialist': 'Specialist',
    'truong phong': 'Trưởng phòng',
    'trưởng phòng': 'Trưởng phòng',
    'head of department': 'Head of Department',
    'pho phong': 'Phó phòng',
    'phó phòng': 'Phó phòng',
    'deputy head': 'Deputy Head',
    'nhan vien': 'Nhân viên',
    'nhân viên': 'Nhân viên',
    'staff': 'Staff',
}


def generate_compliant_password(length=12):
    """
    Generates a cryptographically strong temporary password compliant with SAP policies:
    - At least 1 lowercase letter
    - At least 1 uppercase letter
    - At least 1 digit
    - At least 1 safe special character
    - Does not begin with '?' or '!'
    - No commas, semicolons, quotes or spaces
    """
    letters_lower = string.ascii_lowercase
    letters_upper = string.ascii_uppercase
    digits = string.digits

    while True:
        first_char = secrets.choice(letters_upper + letters_lower)
        all_pool = letters_lower + letters_upper + digits + SAFE_SPECIALS
        remaining = [secrets.choice(all_pool) for _ in range(length - 1)]
        candidate_list = [first_char] + remaining

        cand_str = "".join(candidate_list)
        has_lower = any(c in letters_lower for c in cand_str)
        has_upper = any(c in letters_upper for c in cand_str)
        has_digit = any(c in digits for c in cand_str)
        has_special = any(c in SAFE_SPECIALS for c in cand_str)

        if has_lower and has_upper and has_digit and has_special:
            return cand_str


def format_sap_phone(raw_phone):
    """
    Normalizes phone numbers to standard SAP format:
    Format: (<CountryCode>)<Number> without '+' sign
    Examples:
      - 0985176887 -> (84)985176887
      - +84985176887 -> (84)985176887
      - 84985176887 -> (84)985176887
      - 0912.345.678 -> (84)912345678
      - +1 (555) 123-4567 -> (1)5551234567
    """
    if not raw_phone:
        return ""

    raw_str = str(raw_phone).strip()
    digits_only = re.sub(r'\D', '', raw_str)

    if not digits_only:
        return ""

    # Vietnamese Domestic (starts with 0, 10-11 digits)
    if digits_only.startswith('0') and len(digits_only) in (10, 11):
        return f"(84){digits_only[1:]}"

    # International Vietnam (+84 or 84, followed by 9 digits)
    if digits_only.startswith('84') and len(digits_only) in (11, 12):
        return f"(84){digits_only[2:]}"

    # US/Canada (+1 or 1, followed by 10 digits)
    if digits_only.startswith('1') and len(digits_only) == 11:
        return f"(1){digits_only[1:]}"

    # Default fallback
    if len(digits_only) >= 10:
        return f"({digits_only[:2]}){digits_only[2:]}"

    return digits_only


def normalize_casing(text):
    """Standardizes casing and extra spaces."""
    if not text:
        return ""
    words = text.split()
    return " ".join(words)


def clean_department(dep_text):
    """Corrects typos and casings for standard departments."""
    if not dep_text:
        return ""
    norm = normalize_casing(str(dep_text)).strip()
    key = norm.lower()
    return DEPARTMENT_CORRECTIONS.get(key, norm)


def clean_function(func_text):
    """Corrects typos and casings for standard job titles/functions."""
    if not func_text:
        return ""
    norm = normalize_casing(str(func_text)).strip()
    key = norm.lower()
    return FUNCTION_CORRECTIONS.get(key, norm.title())


def convert_user_01_create(input_path):
    """
    Reads SAP Users Creation Excel sheet and generates normalized flat CSV.
    """
    if not os.path.splitext(input_path)[1]:
        input_path = input_path + ".xlsx"

    if not os.path.exists(input_path):
        print(f"[ERROR] Input file not found: {input_path}")
        sys.exit(1)

    dir_name = os.path.dirname(input_path)
    base_name = os.path.basename(input_path)
    stem, _ = os.path.splitext(base_name)

    out_csv_name = f"{stem}_converted.csv"
    out_csv_path = os.path.join(dir_name, out_csv_name) if dir_name else out_csv_name

    # Load Workbook
    try:
        wb_in = openpyxl.load_workbook(input_path, data_only=True)
    except Exception as e:
        print(f"[ERROR] Could not read Excel workbook '{input_path}': {e}")
        sys.exit(1)

    # Sheet discovery
    target_sheet = None
    for name in wb_in.sheetnames:
        low_name = name.strip().lower()
        if 'user' in low_name or 'nguoi' in low_name or 'danh sach' in low_name:
            target_sheet = wb_in[name]
            break

    if target_sheet is None:
        target_sheet = wb_in.active
        print(f"[INFO] Using active sheet '{target_sheet.title}'.")
    else:
        print(f"[INFO] Processing sheet: '{target_sheet.title}'")

    ws = target_sheet

    # Header Detection
    header_row = 1
    col_name = None
    col_email = None
    col_phone = None
    col_dept = None
    col_func = None

    for col in range(1, ws.max_column + 1):
        val = str(ws.cell(header_row, col).value or '').strip().lower()
        if not val:
            continue

        if ('ho va ten' in val or 'họ và tên' in val or 'full name' in val or 'họ tên' in val or 'name' in val) and col_name is None:
            col_name = col
        elif ('email' in val or 'e-mail' in val or 'mail' in val) and col_email is None:
            col_email = col
        elif ('dien thoai' in val or 'điện thoại' in val or 'phone' in val or 'sđt' in val or 'tel' in val) and col_phone is None:
            col_phone = col
        elif ('phong ban' in val or 'phòng ban' in val or 'bo phan' in val or 'bộ phận' in val or 'department' in val or 'dept' in val) and col_dept is None:
            col_dept = col
        elif ('chuc danh' in val or 'chức danh' in val or 'vi tri' in val or 'vị trí' in val or 'function' in val or 'chức vụ' in val or 'title' in val) and col_func is None:
            col_func = col

    # Defaults fallback
    if col_name is None:
        col_name = 1
    if col_email is None:
        col_email = 2
    if col_phone is None:
        col_phone = 3
    if col_dept is None:
        col_dept = 4
    if col_func is None:
        col_func = 5

    print(f"[INFO] Header mapping -> Name: Col {col_name}, Email: Col {col_email}, Phone: Col {col_phone}, Dept: Col {col_dept}, Func: Col {col_func}")

    records = []
    skipped_empty = 0
    phone_formatted_count = 0
    missing_email_symbol_count = 0
    generated_usernames = set()

    for row in range(2, ws.max_row + 1):
        raw_name = str(ws.cell(row, col_name).value or '').strip()
        raw_email = str(ws.cell(row, col_email).value or '').strip()
        raw_phone = ws.cell(row, col_phone).value
        raw_dept = str(ws.cell(row, col_dept).value or '').strip()
        raw_func = str(ws.cell(row, col_func).value or '').strip()

        # Skip rows without identity
        if not raw_name and not raw_email:
            skipped_empty += 1
            continue

        # 1. Derive Username from Email prefix or raw identifier
        if '@' in raw_email:
            username = raw_email.split('@')[0].strip().upper()
        elif raw_email:
            username = raw_email.strip().upper()
            missing_email_symbol_count += 1
        else:
            # Fallback username from name
            cleaned_tokens = re.sub(r'[^a-zA-Z0-9]', '', raw_name)
            username = cleaned_tokens[:12].upper() if cleaned_tokens else f"USER_{row}"

        # Ensure uniqueness
        base_username = username
        counter = 1
        while username in generated_usernames:
            username = f"{base_username[:10]}_{counter}"
            counter += 1
        generated_usernames.add(username)

        # 2. Cryptographically random compliant initial password
        password = generate_compliant_password(12)

        # 3. Clean full name
        full_name = normalize_casing(raw_name)

        # 4. Clean email
        email = raw_email.strip()

        # 5. Normalize phone
        phone = format_sap_phone(raw_phone)
        if phone:
            phone_formatted_count += 1

        # 6. Clean department
        department = clean_department(raw_dept)

        # 7. Clean function
        function = clean_function(raw_func)

        records.append({
            'username': username,
            'password': password,
            'fullname': full_name,
            'email': email,
            'phone': phone,
            'department': department,
            'function': function
        })

    # CSV Export (UTF-8 with BOM)
    try:
        with open(out_csv_path, 'w', newline='', encoding='utf-8-sig') as f:
            writer = csv.writer(f)
            writer.writerow([
                "Username",
                "Initial Password",
                "Full Name",
                "Email",
                "Phone No.",
                "Department",
                "Function"
            ])
            for r in records:
                writer.writerow([
                    r['username'],
                    r['password'],
                    r['fullname'],
                    r['email'],
                    r['phone'],
                    r['department'],
                    r['function']
                ])
    except PermissionError:
        print(f"[ERROR] Permission denied when writing to '{out_csv_path}'. Please close the file in Excel and try again.")
        sys.exit(1)

    # Execution Summary
    print(f"\n--- Execution Summary ---")
    print(f"[OK] Input File       : {input_path}")
    print(f"[OK] Output CSV       : {out_csv_path} ({len(records)} data rows)")
    print(f"[OK] Total Users      : {len(records)} generated ({len(generated_usernames)} unique usernames)")
    print(f"[OK] Phones Formatted : {phone_formatted_count} normalized to SAP E.164 format")
    if missing_email_symbol_count > 0:
        print(f"[INFO] Non-@ Accounts : {missing_email_symbol_count} raw IDs directly converted to Username")
    if skipped_empty > 0:
        print(f"[INFO] Skipped Empty  : {skipped_empty} empty row(s)")


# Compatibility alias
convert_users_excel = convert_user_01_create


# --- CLI Entrypoint ---
if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] in ('-h', '--help'):
        print("Usage: python scripts/convert_user_01_create.py [path_to_excel_file]")
        print("Example: python scripts/convert_user_01_create.py excel-templates/Template_User_01_Create.xlsx")
        sys.exit(0)

    target_file = None

    if len(sys.argv) > 1:
        target_file = sys.argv[1]
    else:
        # Default candidates lookup
        candidates = [
            os.path.join("excel-working", "User_01_Create.xlsx"),
            os.path.join("excel-working", "Users_Create.xlsx"),
            os.path.join("excel-templates", "Template_User_01_Create.xlsx"),
            os.path.join("excel-templates", "Template_Users_Create.xlsx"),
            "Template_User_01_Create.xlsx",
            "User_01_Create.xlsx",
            "Users_Create.xlsx",
            "FICO_Users_Create.xlsx"
        ]
        for cand in candidates:
            if os.path.exists(cand):
                target_file = cand
                break

    if not target_file:
        print("[ERROR] No input file provided or found in default locations.")
        print("Usage: python scripts/convert_user_01_create.py <path_to_excel_file>")
        print("Example: python scripts/convert_user_01_create.py excel-templates/Template_User_01_Create.xlsx")
        sys.exit(1)

    convert_user_01_create(target_file)
