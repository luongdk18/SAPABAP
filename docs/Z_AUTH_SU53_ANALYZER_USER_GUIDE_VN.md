# 📘 Hướng Dẫn Sử Dụng ZAT (Z_AUTH_SU53_ANALYZER)
## Dành Cho Đội Kiểm Thử Phân Quyền (Tester / Key User / UAT Team)

> **Mã giao dịch (TCode)**: `ZAT`  
> **Chương trình ABAP**: [`src/z_auth_su53_analyzer.prog.abap`](../src/z_auth_su53_analyzer.prog.abap)  
> **Bản PDF in ấn (Tiếng Việt)**: [📄 `Z_AUTH_SU53_ANALYZER_USER_GUIDE_VN.pdf`](./Z_AUTH_SU53_ANALYZER_USER_GUIDE_VN.pdf)  
> **Bản Tiếng Anh (English Version)**: [🌐 `Z_AUTH_SU53_ANALYZER_USER_GUIDE_EN.md`](./Z_AUTH_SU53_ANALYZER_USER_GUIDE_EN.md) \| [📄 PDF (EN)](./Z_AUTH_SU53_ANALYZER_USER_GUIDE_EN.pdf)  
> **Phiên bản**: v2.0 (Dual-Grid ALV Cockpit)

---

## 1. Giới Thiệu & Mục Đích Sử Dụng

Trong các đợt kiểm thử hệ thống SAP S/4HANA (Unit Test, Integration Test, UAT), người dùng thường gặp lỗi phân quyền (bị chặn truy cập giao dịch hoặc không có thẩm quyền thao tác dữ liệu chứng từ). 
Thông thường, Tester phải chụp ảnh màn hình giao dịch `SU53` gửi cho Quản trị viên (Security Admin) và mất thời gian chờ đợi xử lý thủ công qua `PFCG`.

Chương trình **`Z_AUTH_SU53_ANALYZER` (Mã giao dịch: `ZAT`)** là công cụ chuyên biệt giúp đội kiểm thử:
- **Quét toàn diện bộ đệm lỗi**: Thu thập toàn bộ lịch sử lỗi phân quyền phát sinh trong vòng **3 giờ gần nhất** (khác với SU53 chỉ lưu 1 lỗi duy nhất).
- **Đối chiếu vai trò (Role Coverage)**: Tự động kiểm tra đối tượng bị chặn đã có trong các Single Role của người dùng hay chưa (`@08@ [OK]` hoặc `@0A@ [ERR]`).
- **Khắc phục tức thì (1-Click Remediation)**: Cho phép Tester tự chọn quyền thiếu và nạp trực tiếp vào Single Role kiểm thử. Hệ thống **tự động sinh Profile ngầm** để người dùng tiếp tục kịch bản kiểm thử ngay lập tức!

### 📊 So Sánh Giữa Giao Dịch SU53 Chuẩn Và Tiện Ích ZAT

| Tiêu chí | Giao dịch tiêu chuẩn `SU53` | Tiện ích nâng cao `ZAT` |
| :--- | :--- | :--- |
| **Lịch sử ghi nhận lỗi** | Chỉ hiển thị duy nhất **01 lỗi cuối cùng**. Nếu thực hiện thao tác khác, lỗi trước đó sẽ bị xóa mất. | **Lưu trữ 3 giờ qua**: Quét toàn bộ lỗi phân quyền trong bộ đệm hệ thống qua hàm `SUSR_USER_SU53_READ`. |
| **Đối chiếu vai trò người dùng** | Không hiển thị thông tin Role. Người dùng không biết quyền đó thuộc Role nào. | Tự động phân tích các Single Role đang gán của User và hiển thị trực quan trạng thái tương ứng. |
| **Khả năng khắc phục lỗi** | Chỉ xem được thông tin. Phải báo IT Security phân tích và cấu hình thủ công trong PFCG. | **Tích hợp nút `[Add to Role]`**: Tự nạp TCode vào Menu, nạp Object đầy đủ trường từ bảng `TOBJ` và sinh Profile tự động. |

---

## 2. Cách Khởi Động Chương Trình

Người dùng có thể khởi chạy chương trình bằng 1 trong 2 cách sau trên SAP GUI:

1. **Cách 1 (Nhanh nhất)**: Gõ trực tiếp mã lệnh `ZAT` hoặc `/nZAT` vào ô lệnh (Command Field) ở góc trái thanh công cụ rồi nhấn `Enter`.
2. **Cách 2**: Vào giao dịch `SE38` hoặc `SA38`, nhập tên chương trình `Z_AUTH_SU53_ANALYZER` và nhấn **Execute (F8)**.

---

## 3. Màn Hình Chọn Dữ Liệu (Selection Screen)

```
┌────────────────────────────────────────────────────────────────────────┐
│  SAP GUI: Z_AUTH_SU53_ANALYZER - SU53 Authorization Analyzer & Cockpit │
├────────────────────────────────────────────────────────────────────────┤
│ [Execute (F8)]   [Cancel]                                              │
├────────────────────────────────────────────────────────────────────────┤
│ ┌─ 1. User Selection ────────────────────────────────────────────────┐ │
│ │ User Name:                 [TEST_USER01     ]                      │ │
│ └────────────────────────────────────────────────────────────────────┘ │
│ ┌─ 2. Filter Options ────────────────────────────────────────────────┐ │
│ │ [X] Active Single Roles Only                                       │ │
│ └────────────────────────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────────────────────┘
```

- **`User Name`**: Mặc định là tài khoản SAP của người đang đăng nhập. Có thể nhập user khác nếu bạn là Test Lead cần hỗ trợ tester khác.
- **`Active Single Roles Only`**: Tự động lọc các Single Role còn hạn sử dụng, tự động loại trừ các Composite Role để tránh xung đột cấu trúc.

---

## 4. Giao Diện Làm Việc Kép (Dual-Grid Cockpit)

Sau khi nhấn **F8**, hệ thống hiển thị màn hình chia làm 2 khu vực trực quan:

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│ 1. ASSIGNED SINGLE ROLES OF USER (CLICK RADIO ICON TO SELECT TARGET ROLE)              │
│ [➕ Add to Role]   [☑️ Select All]   [⬜ Deselect All]   [🔄 Refresh from SU53]        │
├─────────┬──────────────────────┬──────────────────────────────────────────┬────────────┤
│ Target  │ Single Role Name     │ Role Description                         │ Valid To   │
├─────────┼──────────────────────┼──────────────────────────────────────────┼────────────┤
│ 🔘 (Chọn)│ Z_FI_GL_ACCOUNT      │ Kế toán Tổng hợp - Ghi sổ & Báo cáo GL   │ 31.12.9999 │
│ ⚪      │ Z_MM_PURCHASER       │ Mua hàng - Quản lý Đơn mua & Nhập kho PO │ 31.12.9999 │
│ ⚪      │ Z_PS_PROJECT_MGR     │ Quản lý Dự án - Điều phối WBS Element    │ 31.12.9999 │
└─────────┴──────────────────────┴──────────────────────────────────────────┴────────────┘
                                            ▼ (So khớp thời gian thực)
┌────────────────────────────────────────────────────────────────────────────────────────┐
│ 2. FAILED AUTHORIZATION CHECKS (SELECT ITEMS VIA CHECKBOX TO ADD TO TARGET ROLE)       │
├────┬───────────┬──────┬──────────┬──────────────────────┬──────────────────────────────┤
│Sel │Status     │TCode │Object    │Object Description    │Checked Fields & Values       │
├────┼───────────┼──────┼──────────┼──────────────────────┼──────────────────────────────┤
│ ☑  │ @0A@ [ERR]│FB01  │F_BKPF_BUK│Accounting Document   │ACTVT = '01', BUKRS = '1000'  │
│ ☑  │ @0A@ [ERR]│FS00  │S_TCODE   │Transaction Code Check│TCD = 'FS00'                  │
│ ☐  │ @08@ [OK] │FB03  │F_BKPF_BUK│Accounting Document   │ACTVT = '03', BUKRS = '1000'  │
└────┴───────────┴──────┴──────────┴──────────────────────┴──────────────────────────────┘
```

### 🎛️ Chi Tiết Các Nút Chức Năng Trên Thanh Công Cụ

| Nút bấm / Thao tác | Phím tắt / Icon | Chức năng thực hiện |
| :--- | :--- | :--- |
| **`[Add to Role]`** | `➕` | Nạp toàn bộ các quyền và TCode được tích chọn ở bảng dưới vào Role đang chọn ở bảng trên, tự sinh Profile ngay lập tức. |
| **`[Select All]`** | `☑️` | Tự động tích chọn tất cả các dòng lỗi còn thiếu (`@0A@ [ERR]`). Các dòng đã có quyền (`@08@ [OK]`) sẽ tự động bị bỏ qua. |
| **`[Deselect All]`** | `⬜` | Hủy bỏ toàn bộ lựa chọn trong cột Checkbox. |
| **`[Refresh from SU53]`** | `🔄` (F8) | Đọc lại bộ nhớ đệm lỗi của hệ thống khi Tester vừa thử nghiệm một nghiệp vụ mới trên cửa sổ khác. |
| **Click biểu tượng Radio** | Cột `Target Role` | Chuyển đổi Role kiểm thử mục tiêu. Khi chuyển, hệ thống tự động so khớp lại toàn bộ danh sách lỗi phía dưới theo Role mới. |

---

## 5. Quy Trình 5 Bước Khắc Phục Lỗi Dành Cho Tester

Khi gặp thông báo lỗi phân quyền trong lúc kiểm thử, Tester thực hiện theo trình tự 5 bước chuẩn hóa sau:

1. **Bước 1 - Phát hiện lỗi không có quyền trong giao dịch nghiệp vụ**:
   - Khi bạn thực hiện thao tác (ví dụ chạy `FB01`, `ME21N`, `FS00`), hệ thống chặn lại và báo lỗi ở thanh trạng thái màu đỏ:  
     `You are not authorized to use transaction FB01` hoặc `No authorization for Company Code 1000 (Object F_BKPF_BUK)`.
2. **Bước 2 - Mở nhanh tiện ích ZAT trên cửa sổ mới**:
   - Mở cửa sổ SAP mới bằng lệnh `/oZAT` (giữ nguyên màn hình làm việc hiện tại).
   - Kiểm tra User Name và nhấn phím **F8** để nạp danh sách lỗi.
3. **Bước 3 - Chọn Single Role mục tiêu ở Tầng 1 (Grid Trên)**:
   - Nhấp vào biểu tượng hình tròn `Target Role` tương ứng với vai trò bạn đang kiểm thử (ví dụ: `Z_FI_GL_ACCOUNT`).
   - Danh sách lỗi ở Tầng 2 bên dưới sẽ lập tức được so khớp xem quyền đó đã có hay chưa.
4. **Bước 4 - Tích chọn các quyền còn thiếu ở Tầng 2 (Grid Dưới)**:
   - Tích chọn vào các ô Checkbox ở cột `Select` đối với các dòng có đèn màu đỏ `@0A@ [ERR]`.
   - Bạn cũng có thể bấm nút **`[Select All]`** để chọn nhanh toàn bộ lỗi hợp lệ.
5. **Bước 5 - Bấm nút [Add to Role] để hoàn tất tự động**:
   - Bấm nút **`[Add to Role]`** ở thanh công cụ Tầng 1. Hệ thống tự động:
     - Nạp TCode vào Menu của Role (nếu là `S_TCODE`).
     - Bổ sung Object và điền đầy đủ 100% các Field bắt buộc từ từ điển chuẩn SAP (`TOBJ`).
     - Mở giá trị `*` cho các cấp tổ chức (Org Levels) còn trống phục vụ test.
     - Tự động biên dịch lại Profile phân quyền ngầm (`SUPRN_DARK_MANIPULATE_PROFILE`).
   - Thanh trạng thái báo thông báo xanh:  
     `1 transaction(s) added to menu. 1 object(s) added/updated. Profile regenerated. Data refreshed.`
   - **Kết quả**: Tester quay lại giao dịch nghiệp vụ ban đầu (`FB01`) và bấm `Enter` để tiếp tục kịch bản ngay mà không cần liên hệ IT Security!

---

## 6. Ý Nghĩa Các Mã Trạng Thái & Thao Tác Nâng Cao

### 🚦 Bảng Tra Cứu Mã Trạng Thái ALV

| Mã Trạng Thái | Biểu Tượng | Ý Nghĩa Kỹ Thuật | Hành Động Khuyến Nghị |
| :--- | :--- | :--- | :--- |
| **`@08@ [OK]`** | 🟢 Xanh | Đối tượng và toàn bộ giá trị trường **đã có đầy đủ** trong Role đang chọn. Checkbox tự động bị khóa. | Không cần xử lý thêm. Lỗi có thể do User thiếu ở vai trò khác hoặc đã được cấp trước đó. |
| **`@0A@ [ERR]`** | 🔴 Đỏ | Đối tượng hoặc giá trị trường **hoàn toàn chưa có** trong Role đang chọn. Đây là nguyên nhân trực tiếp gây chặn lỗi. | Tích chọn Checkbox và nhấn nút **`[Add to Role]`** để bổ sung ngay. |
| **`@09@ [WARN]`** | 🟡 Vàng | Trùng khớp một phần; hoặc bộ đệm SU53 hiện tại không ghi nhận lỗi nào phát sinh trong 3 giờ qua. | Thực hiện lại thao tác nghiệp vụ để sinh lỗi mới, sau đó bấm **`[Refresh from SU53]`**. |

### 🔍 Các Thao Tác Tiện Ích Bổ Sung

- **Tra cứu chi tiết Authorization Object (SU03 Jump)**: Nhấp đúp chuột (Double-Click) vào bất kỳ ô nào ở cột `Auth Object` (ví dụ: `F_BKPF_BUK`). Hệ thống sẽ tự động mở giao dịch `SU03` hiển thị đầy đủ tài liệu giải thích chức năng của đối tượng.
- **Xuất danh sách ra file Excel**: Trên thanh công cụ ALV, bấm tổ hợp phím `Ctrl + Shift + F7` hoặc vào Menu `List ➔ Export ➔ Spreadsheet`. Các mã trạng thái đã được chuẩn hóa kèm text tag (`@08@ [OK]`, `@0A@ [ERR]`), giúp người dùng lọc báo cáo trên Excel dễ dàng.

---

## 7. Câu Hỏi Thường Gặp (FAQ)

> **Q1: Bấm [Add to Role] bị báo lỗi: "Role is locked (Edit mode)"?**  
> **Trả lời:** Role đó đang được mở ở chế độ Chỉnh sửa (Change Mode) trong giao dịch `PFCG`. Hãy thoát khỏi màn hình `PFCG` (gõ `/n`), quay lại `ZAT` và bấm lại nút `[Add to Role]`.

> **Q2: Tại sao tôi không thấy giao dịch mới nạp trong SAP Easy Access Menu?**  
> **Trả lời:** Tiện ích `ZAT` đã nạp TCode vào Menu kỹ thuật của Role và sinh Profile phân quyền. Để cây Menu ngoài màn hình chính cập nhật, Tester chỉ cần gõ lệnh `/n` để làm mới session hoặc chạy trực tiếp mã lệnh từ ô Command Field.

> **Q3: Sau khi bổ sung quyền, quyền có bị mất khi chạy lại kịch bản khác không?**  
> **Trả lời:** Không. Dữ liệu đã được ghi vĩnh viễn vào các bảng chuẩn của SAP (`AGR_1250`, `AGR_1251`, `AGR_1252`) và biên dịch thành Profile của Role đó. Quyền sẽ duy trì cho đến khi Admin có đợt cập nhật lớn tiếp theo.
