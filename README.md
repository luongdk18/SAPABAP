# SAP ABAP ADT MCP Server & Z_AUTH_TEST

Dự án tích hợp **SAP ABAP ADT Model Context Protocol (MCP) Server** và chương trình ABAP **`Z_AUTH_TEST`** (Phân tích lỗi phân quyền SU53, giả lập kiểm tra Role và tự động phân quyền kèm sinh Profile).

---

## 📌 Mục lục
1. [Giới thiệu tổng quan](#1-giới-thiệu-tổng-quan)
2. [Yêu cầu hệ thống (Prerequisites)](#2-yêu-cầu-hệ-thống-prerequisites)
3. [Hướng dẫn cài đặt MCP Server (Step-by-Step)](#3-hướng-dẫn-cài-đặt-mcp-server-step-by-step)
4. [Cấu hình MCP trên các công cụ AI (Client Setup)](#4-cấu-hình-mcp-trên-các-công-cụ-ai-client-setup)
5. [Triển khai chương trình ABAP Z_AUTH_TEST](#5-triển-khai-chương-trình-abap-z_auth_test)
6. [Hướng dẫn đưa dự án lên GitHub](#6-hướng-dẫn-đưa-dự-án-lên-github)
7. [Bảo mật & Lưu ý quan trọng](#7-bảo-mật--lưu-ý-quan-trọng)

---

## 1. Giới thiệu tổng quan

Kho lưu trữ này cung cấp giải pháp toàn diện kết nối giữa **AI Assistant** và hệ thống **SAP S/4HANA / ECC**:
- **SAP ADT MCP Server (`@mcp-abap-adt/core`)**: Triển khai giao thức Model Context Protocol (MCP) cho phép các trợ lý AI (Google Antigravity, Claude Desktop, Cursor, VS Code) tương tác trực tiếp với SAP qua ABAP Development Tools (ADT REST API) để đọc, cập nhật, kích hoạt chương trình ABAP, truy vấn bảng, kiểm tra cú pháp, đọc trace dump.
- **Chương trình ABAP `Z_AUTH_TEST`** (`src/z_auth_test.prog.abap`):
  - Đọc buffer SU53 trong 3 giờ gần nhất của user đích.
  - Phân tích chi tiết tất cả các Authorization Object, Field và Value bị thiếu.
  - Đối chiếu với các Single Roles mà user đang sở hữu.
  - Đánh giá độ phủ quyền (Coverage) theo từng Role và hiển thị trạng thái bằng icon màu trực quan.
  - Cho phép chọn các dòng thiếu quyền và bấm **"Add to Role"** để tự động gán vào Role được chọn qua chuẩn PFCG Function Modules.
  - Tự động bổ sung tất cả các fields mặc định từ bảng `TOBJ` (điền `*` cho các field mở) và các biến Organizational Level trong `AGR_1252`.
  - Tự động sinh (regenerate) Profile cho role sau khi add.

---

## 2. Yêu cầu hệ thống (Prerequisites)

### 2.1. Phía máy trạm (Client / Developer Machine)
- **Hệ điều hành**: Windows 10/11, macOS, hoặc Linux.
- **Node.js**: Phiên bản **>= 22.0.0** (bắt buộc cho `@mcp-abap-adt/core` v10+).
- **npm**: Phiên bản **>= 9.0.0** (đi kèm Node.js).
- **Git**: Đã cài đặt Git CLI.
- **AI Client hỗ trợ MCP**: Google Antigravity, Claude Desktop, Cursor IDE, Windsurf, hoặc VS Code (với Cline / Roo Code / Continue).

### 2.2. Phía hệ thống SAP (SAP System Prerequisites)
- **Hệ thống SAP**: SAP NetWeaver 7.50 trở lên hoặc SAP S/4HANA (On-Premise / Private Cloud / BTP ABAP Environment).
- **Dịch vụ ADT ICF đã được kích hoạt** (Giao dịch `SICF`):
  - Đảm bảo node `/default_host/sap/bc/adt` đã được Active.
- **Cổng HTTPS**: Cổng HTTPS của SAP Web Dispatcher / ICM hoạt động bình thường (ví dụ: port `44300` hoặc `44310`).
- **Tài khoản người dùng SAP (SAP User)**:
  - Tài khoản kỹ thuật hoặc developer account có quyền ADT (`S_ADT_RES`, `S_RFC`, `S_DEVELOP`, `S_TABU_DIS`, v.v.).
  - Nếu thao tác trên Role/Profile: cần quyền PFCG (`S_USER_AGR`, `S_USER_PRO`).

---

## 3. Hướng dẫn cài đặt MCP Server (Step-by-Step)

### Bước 1: Kiểm tra phiên bản Node.js
Mở Terminal / PowerShell và kiểm tra:
```bash
node -v
npm -v
```
> ⚠️ **Lưu ý**: Nếu phiên bản Node.js < 22, vui lòng tải và cài đặt bản Node.js mới nhất từ [nodejs.org](https://nodejs.org/).

### Bước 2: Cài đặt gói `@mcp-abap-adt/core`
Cài đặt MCP server toàn cục (Global) trên máy:
```bash
npm install -g @mcp-abap-adt/core
```

Kiểm tra lệnh đã khả dụng:
```bash
# Trên Windows CMD/PowerShell:
where mcp-abap-adt

# Trên Linux/macOS:
which mcp-abap-adt
```

### Bước 3: Cấu hình biến môi trường kết nối SAP
1. Trong thư mục dự án, sao chép file mẫu `.sap.env.example` thành `.sap.env`:
   ```bash
   cp .sap.env.example .sap.env
   ```
2. Mở file `.sap.env` và điền thông tin hệ thống SAP của bạn:
   ```ini
   # Đường dẫn HTTPS tới máy chủ SAP (kèm cổng ADT)
   SAP_URL=https://saps4dev.example.com:44310

   # Client (Mandant)
   SAP_CLIENT=100

   # Phương thức xác thực: basic (On-premise user/password) hoặc xsuaa (BTP)
   SAP_AUTH_TYPE=basic
   SAP_SYSTEM_TYPE=onprem

   # Tài khoản SAP
   SAP_USERNAME=YOUR_USER
   SAP_PASSWORD=YOUR_PASSWORD

   # Ngôn ngữ đăng nhập & System ID
   SAP_LANGUAGE=EN
   SAP_MASTER_SYSTEM=DEV

   # Đặt 0 nếu hệ thống nội bộ dùng SSL tự ký (Self-signed Certificate)
   NODE_TLS_REJECT_UNAUTHORIZED=0
   ```

> 🔒 **CẢNH BÁO BẢO MẬT**: File `.sap.env` chứa mật khẩu SAP. File này đã được thêm vào `.gitignore` và **tuyệt đối không bao giờ được commit lên GitHub**!

---

## 4. Cấu hình MCP trên các công cụ AI (Client Setup)

### 4.1. Cấu hình cho Google Antigravity
Chỉnh sửa file cấu hình MCP của Antigravity tại:
`C:\Users\<username>\.gemini\config\mcp_config.json` (Windows) hoặc `~/.gemini/config/mcp_config.json` (macOS/Linux):

```json
{
  "mcpServers": {
    "sap-s4hana": {
      "command": "cmd.exe",
      "args": [
        "/c",
        "mcp-abap-adt",
        "--transport=stdio",
        "--env-path=d:\\PROJECTS\\SAPABAP\\.sap.env"
      ]
    }
  }
}
```

### 4.2. Cấu hình cho Claude Desktop
Chỉnh sửa file `claude_desktop_config.json`:
- **Windows**: `%APPDATA%\Claude\claude_desktop_config.json`
- **macOS**: `~/Library/Application Support/Claude/claude_desktop_config.json`

```json
{
  "mcpServers": {
    "sap-s4hana": {
      "command": "cmd.exe",
      "args": [
        "/c",
        "mcp-abap-adt",
        "--transport=stdio",
        "--env-path=d:\\PROJECTS\\SAPABAP\\.sap.env"
      ]
    }
  }
}
```
*(Trên macOS/Linux, thay `"cmd.exe"` và `"/c"` bằng trực tiếp lệnh `"mcp-abap-adt"`).*

### 4.3. Cấu hình cho Cursor IDE
Vào **Settings** -> **Features** -> **MCP Servers** -> **Add New MCP Server**:
- **Name**: `sap-s4hana`
- **Type**: `command`
- **Command**: `mcp-abap-adt --transport=stdio --env-path=d:\PROJECTS\SAPABAP\.sap.env`

---

## 5. Triển khai chương trình ABAP Z_AUTH_TEST

### Cách 1: Triển khai tự động qua MCP Server (Khuyên dùng)
Nếu MCP Server đã kết nối thành công với AI Assistant, bạn chỉ cần yêu cầu AI Assistant:
> *"Tạo và kích hoạt chương trình Z_AUTH_TEST từ file src/z_auth_test.prog.abap"*

Trợ lý AI sẽ tự động gọi tool `UpdateProgram` / `CreateProgram` và `ActivateProgram` để deploy trực tiếp lên SAP.

### Cách 2: Triển khai thủ công qua SAP GUI
1. Đăng nhập SAP GUI vào đúng Client phát triển.
2. Mở giao dịch **SE38** (ABAP Editor).
3. Nhập tên chương trình: `Z_AUTH_TEST` -> Bấm **Create**.
4. Chọn Title: `SU53 Authorization Trace and Simulator`, Type: `Executable program` -> Bấm **Save**.
5. Chọn Package: `$TMP` (Local Object) hoặc Package phát triển tương ứng.
6. Sao chép toàn bộ nội dung từ file [`src/z_auth_test.prog.abap`](src/z_auth_test.prog.abap) dán vào editor.
7. Bấm **Check Syntax** (`Ctrl + F2`) và **Activate** (`Ctrl + F3`).
8. *(Tùy chọn)*: Tạo Transaction Code bằng **SE93**:
   - TCode: `ZAT`
   - Short text: `SU53 Role Assignment Simulator`
   - Program: `Z_AUTH_TEST`

---

## 6. Hướng dẫn đưa dự án lên GitHub

Dưới đây là các bước chuẩn xác để khởi tạo Git và đẩy mã nguồn lên GitHub một cách an toàn.

### Bước 1: Khởi tạo Git repository tại thư mục dự án
Mở Terminal / PowerShell tại thư mục `d:\PROJECTS\SAPABAP`:
```bash
git init
```

### Bước 2: Kiểm tra trạng thái Git và đảm bảo bảo mật
Chạy lệnh kiểm tra:
```bash
git status
```
> ✅ **Kiểm tra**: Chắc chắn rằng file `.sap.env` **KHÔNG** xuất hiện trong danh sách `Untracked files`. Chỉ có `.gitignore`, `.sap.env.example`, `mcp-config.example.json`, `README.md`, và `src/` được hiển thị!

### Bước 3: Thêm files và tạo commit đầu tiên
```bash
git add .
git commit -m "feat: initial commit for SAP ADT MCP server setup and Z_AUTH_TEST tool"
```

### Bước 4: Tạo Repository mới trên GitHub
1. Truy cập [github.com/new](https://github.com/new).
2. Đặt tên repository (ví dụ: `sap-abap-mcp-auth-test`).
3. Chọn chế độ: **Public** hoặc **Private** tùy nhu cầu.
4. **Không** tích chọn *"Add a README file"*, *"Add .gitignore"* (vì chúng ta đã tạo sẵn tại local).
5. Bấm **Create repository**.

### Bước 5: Liên kết Remote và Push code lên GitHub
Sao chép URL repository vừa tạo và chạy các lệnh:
```bash
# Đổi tên nhánh mặc định thành main
git branch -M main

# Thêm remote origin (thay URL bên dưới bằng URL repo GitHub của bạn)
git remote add origin https://github.com/<your-username>/sap-abap-mcp-auth-test.git

# Đẩy code lên GitHub
git push -u origin main
```

---

## 7. Bảo mật & Lưu ý quan trọng

1. **Thông tin xác thực (Credentials)**:
   - Tuyệt đối không commit file chứa mật khẩu thực tế (`.sap.env`).
   - Luôn sử dụng `.sap.env.example` làm tài liệu hướng dẫn mẫu.
2. **Quyền hạn tài khoản SAP**:
   - Trong môi trường Production, nên giới hạn quyền của tài khoản kết nối MCP ở mức Read-Only hoặc chỉ cấp quyền sửa đổi trên các package thử nghiệm.
3. **Mạng & SSL**:
   - Khi kết nối qua mạng Internet công cộng, khuyến nghị kích hoạt VPN hoặc thiết lập HTTPS chứng chỉ hợp lệ (thay vì tắt kiểm tra SSL bằng `NODE_TLS_REJECT_UNAUTHORIZED=0`).
