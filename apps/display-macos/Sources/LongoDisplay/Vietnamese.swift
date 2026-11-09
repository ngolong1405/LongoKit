/// Vietnamese strings, keyed by the English text passed to `L()` (including LongoKitUI's own strings).
enum Vietnamese {
    static let strings: [String: String] = [
        // Window & tabs
        "General": "Chung",
        "Displays": "Màn hình",
        "About": "Giới thiệu",
        "Restore Defaults": "Khôi phục mặc định",
        "Restore defaults?": "Khôi phục mặc định?",
        "Brightness, limits and dimming go back to the defaults for every display.":
            "Độ sáng, giới hạn và làm tối của mọi màn hình sẽ về mặc định.",
        "Cancel": "Huỷ",
        "Crafted by ": "Thực hiện bởi ",
        "Quit": "Thoát",
        "Close window (keeps running in the menu bar)": "Đóng cửa sổ (app vẫn chạy trên menu bar)",
        "Minimize": "Thu nhỏ",
        "This window has a fixed size": "Cửa sổ có kích thước cố định",
        "Coming soon": "Sắp có",

        // Modes
        "Manual": "Thủ công",
        "Sync": "Đồng bộ",
        "Each display keeps its own brightness": "Mỗi màn hình giữ độ sáng riêng",
        "External displays follow the built-in display": "Màn hình ngoài theo màn hình MacBook",

        // General tab
        "Brightness Mode": "Chế độ độ sáng",
        "How external displays get their brightness.": "Cách màn hình ngoài lấy độ sáng.",
        "Sync needs a built-in display. On this Mac, external displays keep their own brightness.":
            "Đồng bộ cần màn hình tích hợp. Trên máy này, màn hình ngoài giữ độ sáng riêng.",
        "External displays follow the built-in display, within each display's minimum and maximum.":
            "Màn hình ngoài sáng/tối theo màn hình MacBook, trong khoảng tối thiểu – tối đa của từng màn.",
        "Each display keeps the brightness you set.": "Mỗi màn hình giữ độ sáng bạn đặt.",
        "Brightness Keys": "Phím độ sáng",
        "Use the brightness keys on the display under the pointer.": "Phím độ sáng điều khiển màn hình đang có con trỏ chuột.",
        "Needs Accessibility permission to catch the brightness keys.": "Cần quyền Trợ năng để nhận phím độ sáng.",
        "Grant Access…": "Cấp quyền…",
        "Brightness keys work on external displays.": "Phím độ sáng đã dùng được cho màn hình ngoài.",
        "Brightness keys only change the built-in display.": "Phím độ sáng chỉ đổi màn hình MacBook.",
        "Startup & Behavior": "Khởi động & Hành vi",
        "Language, look, and how %@ starts.": "Ngôn ngữ, giao diện và cách %@ khởi động.",
        "Language": "Ngôn ngữ",
        "Language used throughout the app.": "Ngôn ngữ hiển thị trong toàn bộ ứng dụng.",
        "Appearance": "Giao diện",
        "Follow macOS, or always use dark or light.": "Theo macOS, hoặc luôn dùng nền tối hay sáng.",
        "System": "Hệ thống",
        "Light": "Sáng",
        "Dark": "Tối",
        "Theme: follow macOS": "Giao diện: theo macOS",
        "Theme: dark": "Giao diện: tối",
        "Theme: light": "Giao diện: sáng",
        "Start at Login": "Mở cùng máy",
        "Launch %@ in the background when your Mac starts up.": "Tự chạy %@ ở chế độ nền khi bật máy.",
        "Show icon in menu bar": "Hiện icon trên thanh menu",
        "Quick brightness controls from the menu bar.": "Chỉnh độ sáng nhanh từ thanh menu.",

        // Displays
        "Built-in Display": "Màn hình MacBook",
        "Connected displays": "Màn hình đang kết nối",
        "Connect an external display to control its brightness.": "Cắm màn hình ngoài để chỉnh độ sáng cho nó.",
        "Customize": "Tuỳ chỉnh",
        "Native": "Gốc",
        "Software": "Phần mềm",
        "Controlled by macOS": "Do macOS điều khiển",
        "Hardware brightness over the cable": "Độ sáng phần cứng qua dây cáp",
        "No DDC: dimmed in software": "Không có DDC: làm tối bằng phần mềm",
        "Min brightness": "Sáng tối thiểu",
        "Max brightness": "Sáng tối đa",
        "In Sync mode this display moves between its minimum and maximum as the built-in display changes.":
            "Ở chế độ Đồng bộ, màn hình này đổi độ sáng trong khoảng tối thiểu – tối đa theo màn hình MacBook.",
        "Extra Dimming": "Làm tối thêm",
        "Darker than the lowest brightness, for late nights. Done in software.":
            "Tối hơn mức thấp nhất, cho những đêm khuya. Làm bằng phần mềm.",
        "Reset this display": "Đặt lại màn hình này",

        // Menu bar
        "No displays found.": "Không tìm thấy màn hình.",
        "All": "Tất cả",
        "Set every display to %d%%": "Đặt mọi màn hình ở %d%%",
        "Preferences…": "Mở cài đặt…",
        "Follows the built-in display in Sync mode": "Theo màn hình MacBook ở chế độ Đồng bộ",

        // DDC control
        "External displays follow the built-in display. Choose Manual to set each one yourself.":
            "Màn ngoài đang chạy theo màn MacBook. Chọn Thủ công để chỉnh riêng từng màn.",
        "Not answering DDC: if its brightness doesn't change, use Software dimming on its page.":
            "Màn không trả lời DDC: nếu độ sáng không đổi, hãy chọn Phần mềm trong trang của màn này.",
        "Not answering DDC": "Không trả lời DDC",
        "Brightness Control": "Cách chỉnh độ sáng",
        "Hardware changes the monitor's backlight; Software darkens the picture.":
            "Phần cứng đổi đèn nền của màn; Phần mềm làm tối hình ảnh.",
        "Hardware (DDC)": "Phần cứng (DDC)",
        "This monitor takes DDC commands but doesn't report its brightness back (common on a MacBook's HDMI port), so the app can't read where it starts. If moving the slider doesn't change it, choose Software.":
            "Màn này nhận lệnh DDC nhưng không báo lại độ sáng (thường gặp với cổng HDMI của MacBook), nên app không đọc được mức ban đầu. Nếu kéo thanh trượt mà độ sáng không đổi, hãy chọn Phần mềm.",
        "Brightness": "Độ sáng",
        "Speaker volume": "Âm lượng loa",
        "Mac volume": "Âm lượng của Mac",
        "Running": "Đang chạy",
        "Paused": "Tạm dừng",
        "Pause %@: displays keep their brightness, Sync, keys and software dimming stop":
            "Tạm dừng %@: màn hình giữ nguyên độ sáng, ngừng Đồng bộ, phím độ sáng và làm tối bằng phần mềm",
        "Turn %@ back on": "Bật lại %@",
        "Up 5%": "Tăng 5%",
        "Down 5%": "Giảm 5%",
        "This monitor isn't answering DDC. MacBook HDMI ports often don't pass it on: plug it into a USB-C port, turn on DDC/CI in the monitor's menu, or use Software.":
            "Màn này không trả lời DDC. Cổng HDMI của MacBook thường không truyền DDC: hãy cắm qua cổng USB-C, bật DDC/CI trong menu của màn, hoặc chọn Phần mềm.",

        // Display power
        "Off": "Tắt",
        "Turn this display off": "Tắt màn hình này",
        "Turn this display back on": "Bật lại màn hình này",
        "The last display that's on can't be turned off": "Không thể tắt màn hình cuối cùng đang bật",
        "Turned off: windows moved to your other displays": "Đã tắt: cửa sổ đã chuyển sang các màn hình khác",
        "Display Power": "Bật / tắt màn hình",
        "Off works like unplugging it: windows move to your other displays.":
            "Tắt giống như rút dây: cửa sổ chuyển sang các màn hình còn lại.",
        "You'll be asked to keep it off; with no answer it turns back on in %d seconds. ⌃⌥⌘B turns every display back on at any time.":
            "Sau khi tắt sẽ có hỏi xác nhận; không trả lời thì màn tự bật lại sau %d giây. Nhấn ⌃⌥⌘B bất cứ lúc nào để bật lại mọi màn hình.",
        "Keep %@ off?": "Giữ %@ ở trạng thái tắt?",
        "macOS wouldn't turn it off, so its picture is black instead.":
            "macOS không cho tắt màn này, nên hình ảnh được làm đen thay thế.",
        "It turns back on in %d seconds unless you keep it off.": "Màn hình sẽ tự bật lại sau %d giây nếu bạn không chọn giữ tắt.",
        "⌃⌥⌘B turns every display back on at any time.": "Nhấn ⌃⌥⌘B bất cứ lúc nào để bật lại mọi màn hình.",
        "Keep Off": "Giữ tắt",
        "Turn On Now": "Bật lại ngay",

        // About
        "Brightness for every display: external monitors over DDC/CI, software dimming for the rest, and Sync with your MacBook.":
            "Độ sáng cho mọi màn hình: màn ngoài qua DDC/CI, làm tối bằng phần mềm cho các màn còn lại, và đồng bộ với MacBook.",
        "License": "Giấy phép",
        "Part of LongoKit · Crafted by %@": "Thuộc bộ LongoKit · Thực hiện bởi %@",
    ]
}
