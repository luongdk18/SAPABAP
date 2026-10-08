# Z_AUTH_TEST_N — hỗ trợ test role

Chạy bằng SE38/SA38. Bản cải tiến nằm trong package `$TMP`; `Z_AUTH_TEST` giữ nguyên.

## Thao tác

1. Chọn user và single role đích.
2. Thực hiện nghiệp vụ trong phiên user test, dùng **Refresh from SU53** để lấy lỗi quyền mới. Trace lặp giống nhau được gom và đếm số lần ở HITS.
3. Chọn các dòng cần bổ sung, dùng **Add to Role**. Select All/Deselect All hỗ trợ chọn nhanh.
4. Sau Add, chương trình cập nhật coverage, trạng thái generate/comparison và giá trị user ngay trên ALV hiện có. Không đọc lại SU53, không xóa hoặc tự ẩn dòng đã Add; dòng được bao phủ chuyển xanh. Chỉ Refresh from SU53 mới tải lại nguồn trace.

Đã bỏ Start Test, Preview/Edit, Missing/All, Retry Generate, Complete Open và Operation Log khỏi giao diện. Thông báo lỗi nằm trong trạng thái kết quả trên ALV hoặc thanh thông báo SAP; nếu generate thất bại, kiểm tra field open và generate trong PFCG.

## Tự tính toán và gộp node

Chương trình đọc lại role đã khóa, hoàn thiện đầy đủ field của object từ TOBJ, bỏ qua check đã được bao phủ, rồi kết hợp các check selected với authorization hiện có.

- Ưu tiên node hiện có, giữ các giá trị của nó và bổ sung giá trị cần thiết.
- Hai node gộp được khi toàn bộ tập giá trị của các field giống nhau, ngoại trừ tối đa một field. Field khác nhau nhận hợp các giá trị, không ghi đè và không tự chuyển các giá trị rời rạc thành khoảng rộng hơn.
- Lặp việc gộp đến khi không còn cặp phù hợp giữa node mới và node khác. Chỉ loại bỏ node tạm tạo trong lần Add; không xóa authorization đã tồn tại của role.
- Khi hai field khác nhau và gộp có thể tạo tổ hợp quyền chưa có, giữ node riêng. So sánh toàn bộ tập giá trị, không chỉ một giá trị trùng nhau.
- Node thiếu field hoặc có field open không được dùng làm đích gộp. Authorization deleted không được tái kích hoạt.
- Org variable được resolve trước khi so sánh. Khi gộp node, giá trị bổ sung được maintain riêng cho node đó. Luồng Add Tcode có bước hoàn thiện org level open của toàn role như mô tả dưới đây.

Ví dụ: năm check có `ACTVT = '03'`, các field khác giống nhau và SIMG_VIEW lần lượt AUTHORIZED, SCOPED, SCOPEABLE, INSTALLED, ACTIVATED sẽ có một node với ACTVT 03 và năm giá trị SIMG_VIEW.

Ngược lại, `(ACTVT 03, SIMG_VIEW A)` và `(ACTVT 02, SIMG_VIEW B)` vẫn là hai node vì gộp sẽ tạo thêm `(03,B)` và `(02,A)`. Nếu cả bốn tổ hợp đã có trong dữ liệu cần bổ sung, chương trình có thể gộp thành một node.

Đây là cách gộp bảo toàn tổ hợp theo từng cặp; không cam kết tìm số node tối thiểu toàn cục cho mọi cấu trúc dữ liệu hoặc mọi biểu diễn wildcard/range tương đương.

## Field trống và transaction

- Mỗi instance mới có đầy đủ field trong TOBJ. Field thiếu/trống trong trace được maintain bằng `*`, hiển thị ở AUTO_VALUES. Đây là mở rộng quyền có chủ đích, không coi field trống là giá trị nghiệp vụ cụ thể.
- S_TCODE phải là transaction cụ thể tồn tại trong TSTC, được bổ sung qua menu role và merge chuẩn SAP.
- Khi Add Tcode, menu merge và generate bật `fill_fields_with_star` và `fill_orgs_with_star` như `Z_AUTH_TEST`. Tất cả field/org level open của role, kể cả có sẵn trước khi Add, được hoàn thiện bằng `*` trước khi generate. Field TOBJ còn thiếu trong authorization active cũng được bổ sung đầy đủ. Giá trị và khoảng đã maintain được giữ nguyên; authorization deleted không được tái kích hoạt. Việc hoàn thiện org level open có thể ảnh hưởng nhiều authorization trong role.
- Kiểm tra quyền sửa role, khóa role, lưu, generate và user comparison. Chỉ hỗ trợ single role độc lập, không hỗ trợ composite/derived role.

## Xác minh và giới hạn

21 ABAP Unit test HARMLESS bao gồm sáu ca gộp: năm giá trị cùng ACTVT vào node hiện có, hai tổ hợp chéo giữ riêng, lưới đủ 2×2 gộp một node, node hiện có nhiều ACTVT không phát sinh quyền ngoài yêu cầu, gộp không mở rộng org variable toàn role và node open không dùng làm đích gộp. Ba ca hoàn thiện trước generate kiểm tra field/org level open có sẵn, giữ giá trị đã maintain và tính lặp lại, không sửa authorization deleted, bổ sung field TOBJ/org variable thiếu. Các ca còn lại kiểm tra coverage, wildcard/range, TOBJ và giá trị trống.

Chạy lại bằng `npm run test:auth:n`, kết quả tại `tests/z_auth_test_n.abapunit.xml`. Triển khai bằng `npm run deploy:auth:n`; dùng cấu hình SAP hiện có trong `.sap.env`.

Chưa kiểm thử giao diện SAP GUI hoặc Add/generate trên role thật. Cần đối chiếu các tình huống trên trong PFCG bằng role test riêng trước khi sử dụng rộng rãi.

Màu xanh là role đích bao phủ check, không bảo đảm phiên user hiện tại đã nhận quyền mới; test lại trong phiên đăng nhập mới sau comparison. SU53 không phải trace đầy đủ mọi AUTHORITY-CHECK. Các FM chuẩn có thể commit nhiều bước, nên menu đã lưu có thể còn lại nếu bước sau thất bại. `$TMP` chưa có transport sang hệ thống khác.
