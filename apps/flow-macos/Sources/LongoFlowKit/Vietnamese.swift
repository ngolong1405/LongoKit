/// Vietnamese strings, keyed by the English text passed to `L()` (including LongoKitUI's own strings).
enum Vietnamese {
    static let strings: [String: String] = [
        // Window & tabs
        "Macs": "Máy Mac",
        "General": "Chung",
        "About": "Giới thiệu",
        "Quit": "Thoát",
        "Settings…": "Cài đặt…",
        "Cancel": "Huỷ",
        "Close window (keeps running in the menu bar)": "Đóng cửa sổ (app vẫn chạy trên menu bar)",
        "Minimize": "Thu nhỏ",
        "This window has a fixed size": "Cửa sổ có kích thước cố định",
        "Coming soon": "Sắp có",
        "Off": "Tắt",
        "Esc three times brings the mouse back": "Bấm Esc 3 lần để lấy chuột về",

        // Status
        "On %@": "Đang ở %@",
        "%@ is using this Mac": "%@ đang dùng máy này",
        "1 Mac connected": "1 máy Mac đã kết nối",
        "%d Macs connected": "%d máy Mac đã kết nối",
        "Status": "Trạng thái",
        "Push the pointer past the edge toward a paired Mac to use it with this keyboard and mouse.":
            "Đẩy con trỏ qua mép màn hình về phía máy Mac đã ghép đôi để dùng máy đó bằng bàn phím và chuột này.",
        "Off: the pointer stays on this Mac, and other Macs can't use it.": "Đang tắt: con trỏ ở yên máy này, máy khác cũng không điều khiển được máy này.",

        // Macs
        "Accessibility": "Trợ năng",
        "Needed on both Macs: to take the mouse and keyboard over, and to move the pointer here.":
            "Cần bật trên cả hai máy: để chuyển chuột và bàn phím sang máy kia, và để điều khiển con trỏ ở máy này.",
        "Allow Accessibility to start": "Cấp quyền Trợ năng để bắt đầu",
        "Paired Macs": "Máy đã ghép đôi",
        "None yet": "Chưa có",
        "Pair with a Mac below: it shows a code to type here, once.": "Ghép đôi với một máy bên dưới: máy đó hiện một mã để nhập ở đây, chỉ một lần.",
        "Nearby": "Ở gần",
        "Nearby (%d)": "Ở gần (%d)",
        "No other Macs found": "Chưa thấy máy Mac nào khác",
        "Open Longo Flow on the other Mac, on the same Wi-Fi or network.": "Mở Longo Flow trên máy Mac kia, cùng Wi-Fi hoặc cùng mạng.",
        "Pair": "Ghép đôi",
        "Unpair": "Bỏ ghép đôi",
        "Connected": "Đã kết nối",
        "Not around now": "Đang không ở gần",
        "The mouse and keyboard are there now": "Chuột và bàn phím đang ở máy này",
        "This Mac": "Máy này",
        "Left": "Trái",
        "Right": "Phải",
        "Above": "Trên",
        "Below": "Dưới",
        "%@ of this Mac": "Bên %@ máy này",
        "No paired Macs yet. Open Settings to pair one.": "Chưa ghép đôi máy nào. Mở Cài đặt để ghép đôi.",

        // Pairing
        "Asking %@…": "Đang hỏi %@…",
        "Type the code %@ shows": "Nhập mã đang hiện trên %@",
        "That wasn't it. It shows a new code now.": "Sai mã. Máy kia vừa hiện mã mới.",
        "%@ wants to pair. Type this code there:": "%@ muốn ghép đôi. Nhập mã này trên máy đó:",
        "Only pair with your own Macs: a paired Mac can control this one.": "Chỉ ghép đôi với máy của bạn: máy đã ghép đôi điều khiển được máy này.",
        "Paired with %@. Push the pointer past the edge toward it.": "Đã ghép đôi với %@. Đẩy con trỏ qua mép màn hình về phía máy đó.",

        // General
        "Sharing": "Chia sẻ",
        "Share the clipboard": "Dùng chung clipboard",
        "What you copy goes over with the pointer: text and pictures.": "Thứ bạn copy đi theo con trỏ sang máy kia: chữ và ảnh.",
        "Where the mouse is, from the menu bar.": "Xem chuột đang ở máy nào ngay trên thanh menu.",

        // App settings (LongoKitUI)
        "App": "Ứng dụng",
        "Language": "Ngôn ngữ",
        "Appearance": "Giao diện",
        "System": "Hệ thống",
        "Dark": "Tối",
        "Light": "Sáng",
        "Theme: dark": "Giao diện: tối",
        "Theme: light": "Giao diện: sáng",
        "Theme: follow macOS": "Giao diện: theo macOS",
        "Start at Login": "Mở cùng máy",
        "Show icon in menu bar": "Hiện icon trên thanh menu",
        "Grant Access…": "Cấp quyền…",
        "Granted": "Đã cấp",
        "Move %@ to Applications?": "Chuyển %@ vào Applications?",
        "It's running from the disk image. In Applications it stays installed, and opens from Launchpad and Spotlight.":
            "App đang chạy từ file cài đặt. Ở trong Applications thì app được cài hẳn, mở được từ Launchpad và Spotlight.",
        "Move to Applications": "Chuyển vào Applications",
        "Not Now": "Để sau",
        "Couldn't move %@ to Applications": "Không chuyển được %@ vào Applications",
        "Drag it into Applications from the disk image instead.": "Hãy kéo app vào Applications từ file cài đặt.",
        "%@ is installed": "Đã cài %@",
        "Delete the installer? It isn't needed any more.": "Xoá file cài đặt? Không cần nó nữa.",
        "Move to Trash": "Bỏ vào Thùng rác",
        "Keep": "Giữ lại",

        // About
        "One keyboard and mouse for your Macs: push the pointer past the edge and it's on the next Mac, with the clipboard.":
            "Một bộ bàn phím và chuột cho các máy Mac của bạn: đẩy con trỏ qua mép màn hình là sang máy bên cạnh, mang theo cả clipboard.",
        "Part of LongoKit · Crafted by %@": "Thuộc LongoKit · Do %@ làm",
        // Arrangement
        "Arrange this Mac's displays…": "Xếp màn hình của máy này…",
        "Away": "Vắng",
        "Drag a Mac's screens to where it sits on your desk. The pointer goes over where they touch.": "Kéo màn hình của máy Mac kia tới đúng chỗ nó đặt trên bàn. Con trỏ sang máy kia ở đoạn hai màn hình chạm nhau.",
        "Drag to where %@ sits": "Kéo tới chỗ %@ đang đặt",
        "This Mac's displays are arranged in System Settings › Displays": "Màn hình của máy này được xếp trong Cài đặt hệ thống › Màn hình",
        "Your displays, as macOS arranges them. Paired Macs show up beside them.": "Các màn hình của bạn, đúng như macOS đang xếp. Máy Mac đã ghép đôi hiện ra bên cạnh.",
        "Drag a Mac to where it sits on your desk": "Kéo máy Mac tới chỗ nó đặt trên bàn",
        "The pointer goes over here": "Chuột sang máy kia ở đây",
        "Display %d": "Màn hình %d",
        "Pair a Mac below to place it here": "Ghép đôi một máy bên dưới để đặt nó vào đây",
        "Drag displays to arrange them, as in System Settings. Paired Macs show up beside them.":
            "Kéo các màn hình để sắp xếp, như trong Cài đặt hệ thống. Máy Mac đã ghép đôi hiện ra bên cạnh.",
        "Drag displays to arrange them, as in System Settings, and another Mac's to where it sits.":
            "Kéo các màn hình để sắp xếp, như trong Cài đặt hệ thống; kéo màn hình của máy kia tới chỗ nó đặt.",
    ]
}
