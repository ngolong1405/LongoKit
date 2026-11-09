/// Vietnamese strings, keyed by the English text passed to `L()` (including LongoKitUI's own strings).
enum Vietnamese {
    static let strings: [String: String] = [
        // Window & tabs
        "General": "Chung",
        "Keyboards": "Bàn phím",
        "Hyper": "Hyper",
        "About": "Giới thiệu",
        "Restore Defaults": "Khôi phục mặc định",
        "Restore defaults?": "Khôi phục mặc định?",
        "Every keyboard goes back to its own keys, and the Hyper layer to its defaults.":
            "Mọi bàn phím trở về phím gốc, và lớp Hyper về mặc định.",
        "Cancel": "Huỷ",
        "OK": "OK",
        "Crafted by ": "Thực hiện bởi ",
        "Quit": "Thoát",
        "Close window (keeps running in the menu bar)": "Đóng cửa sổ (app vẫn chạy trên menu bar)",
        "Minimize": "Thu nhỏ",
        "This window has a fixed size": "Cửa sổ có kích thước cố định",
        "Running": "Đang chạy",
        "Paused": "Tạm dừng",
        "Pause %@": "Tạm dừng %@",
        "Turn %@ back on": "Bật lại %@",
        "⌃⌥⌘K pauses or resumes LongoKeys from any app.": "Nhấn ⌃⌥⌘K ở bất kỳ app nào để tạm dừng hoặc bật lại LongoKeys.",

        // General tab
        "%@ is active": "%@ đang hoạt động",
        "%@ is paused": "%@ đang tạm dừng",
        "Your keyboards use the keys you set.": "Bàn phím đang dùng các phím bạn đã đặt.",
        "Every keyboard types as macOS does by itself.": "Mọi bàn phím gõ như macOS vốn làm.",
        "⌃⌥⌘K pauses or resumes it from any app.": "Nhấn ⌃⌥⌘K ở bất kỳ app nào để tạm dừng hoặc bật lại.",
        "Permissions": "Quyền",
        "Remapping keys needs no permission. The Hyper key needs Accessibility.":
            "Đổi phím không cần quyền gì. Phím Hyper cần quyền Trợ năng.",
        "Granted": "Đã cấp",
        "Needed for Hyper": "Cần cho Hyper",
        "Until it's granted, Caps Lock set to Hyper stays a normal Caps Lock.":
            "Chưa cấp quyền thì Caps Lock đặt làm Hyper vẫn là Caps Lock bình thường.",
        "Grant Access…": "Cấp quyền…",
        "In password fields macOS turns on Secure Input and hides keys from every app like this one: there the Hyper key waits until you leave the field. Remapped keys keep working.":
            "Trong ô mật khẩu, macOS bật Bảo mật nhập liệu và giấu phím khỏi mọi app như app này: ở đó phím Hyper tạm ngưng tới khi bạn rời ô. Các phím đã đổi vẫn hoạt động.",
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
        "Quick keyboard settings from the menu bar.": "Chỉnh nhanh bàn phím từ thanh menu.",

        // Keyboards tab
        "All keyboards": "Mọi bàn phím",
        "Shared settings, used by every keyboard without its own": "Cài đặt chung, dùng cho mọi bàn phím không có cài đặt riêng",
        "Connected keyboards": "Bàn phím đang kết nối",
        "Built-in Keyboard": "Bàn phím MacBook",
        "Own settings": "Cài đặt riêng",
        "Shared settings": "Cài đặt chung",
        "No keyboard found.": "Không tìm thấy bàn phím.",
        "%d remaps": "%d phím đổi",
        "Customize": "Tuỳ chỉnh",
        "Unchanged": "Gốc",
        "Built-in": "Tích hợp",
        "Wired": "Có dây",
        "Caps Lock works as usual.": "Caps Lock hoạt động như bình thường.",
        "Caps Lock is a second Esc.": "Caps Lock thành thêm một phím Esc.",
        "Caps Lock is a Control key, easier to reach.": "Caps Lock thành phím Control, dễ với tới hơn.",
        "Tap: Esc. Hold: Hyper (⌃⌥⇧⌘) and the Hyper layer.": "Nhấn nhanh: Esc. Giữ: Hyper (⌃⌥⇧⌘) và lớp Hyper.",
        "Caps Lock": "Caps Lock",
        "Hyper needs Accessibility permission (General tab); until then Caps Lock stays as it is.":
            "Hyper cần quyền Trợ năng (tab Chung); trước đó Caps Lock giữ nguyên.",
        "Remap keys": "Đổi phím",
        "Click a key to choose what it sends. Works everywhere, even in password fields.":
            "Bấm vào một phím để chọn phím nó gửi đi. Chạy ở mọi nơi, kể cả ô mật khẩu.",
        "Swap ⌘ ⌥": "Đổi ⌘ ⌥",
        "Unswap ⌘ ⌥": "Bỏ đổi ⌘ ⌥",
        "For keyboards made for Windows, where ⊞ and Alt sit the other way round.":
            "Cho bàn phím Windows, nơi phím ⊞ và Alt nằm ngược chỗ.",
        "Remove": "Xoá",
        "Set Caps Lock in the card above.": "Chỉnh Caps Lock ở thẻ phía trên.",
        "As it is": "Giữ nguyên",
        "Keys": "Phím",
        "Modifiers": "Phím bổ trợ",
        "Navigation": "Điều hướng",
        "Extra F keys": "Phím F thêm",
        "This keyboard uses the shared settings. Turn on Own settings to change them just for it.":
            "Bàn phím này dùng cài đặt chung. Bật Cài đặt riêng để chỉnh riêng cho nó.",
        "Try your keys": "Thử phím",
        "Shows what apps receive, after remaps and Hyper.": "Hiện phím mà các app nhận được, sau khi đổi phím và Hyper.",
        "Listen": "Nghe",
        "Stop": "Dừng",
        "Press any key…": "Nhấn một phím bất kỳ…",
        "Click Listen, then press keys.": "Bấm Nghe rồi nhấn phím.",

        // Keep / refuse
        "Keep these keys?": "Giữ các phím này?",
        "Try a few keys. Your keys go back to how they were in %d seconds unless you keep them.":
            "Thử gõ vài phím. Bàn phím sẽ tự trở lại như cũ sau %d giây nếu bạn không chọn giữ.",
        "⌃⌥⌘K pauses LongoKeys at any time.": "Nhấn ⌃⌥⌘K bất cứ lúc nào để tạm dừng LongoKeys.",
        "Keep": "Giữ",
        "Undo": "Hoàn tác",
        "That would leave a keyboard without %@": "Thay đổi này làm bàn phím mất phím %@",
        "Esc, Return, ⌘, ⌃, ⌥ and K must always come from some key, so the keyboard stays usable and ⌃⌥⌘K can pause LongoKeys.":
            "Esc, Return, ⌘, ⌃, ⌥ và K luôn phải có trên một phím nào đó, để bàn phím vẫn dùng được và ⌃⌥⌘K vẫn tạm dừng được LongoKeys.",

        // Hyper tab
        "Hyper Layer": "Lớp Hyper",
        "Hyper layer": "Lớp Hyper",
        "Hold Caps Lock and press a key. Keys without an action send ⌃⌥⇧⌘ + the key, free for any app's shortcuts.":
            "Giữ Caps Lock rồi nhấn một phím. Phím chưa gán hành động sẽ gửi ⌃⌥⇧⌘ + phím đó, để dùng làm phím tắt cho app bất kỳ.",
        "In use": "Đang dùng",
        "Use Caps Lock as Hyper": "Dùng Caps Lock làm Hyper",
        "No keyboard has Caps Lock set to Hyper yet: this sets it for every keyboard that uses the shared settings.":
            "Chưa bàn phím nào đặt Caps Lock làm Hyper: nút này đặt cho mọi bàn phím dùng cài đặt chung.",
        "Hyper needs Accessibility permission (General tab).": "Hyper cần quyền Trợ năng (tab Chung).",
        "Click a key to set its action": "Bấm vào một phím để gán hành động",
        "Input source": "Nguồn nhập",
        "KEYS": "PHÍM",
        "MORE": "KHÁC",
        "Next input source": "Đổi nguồn nhập",
        "Open an app…": "Mở một app…",
        "Record shortcut…": "Ghi phím tắt…",
        "Press keys…": "Nhấn phím…",
        "No action: send ⌃⌥⇧⌘ + %@": "Không gán: gửi ⌃⌥⇧⌘ + %@",

        // Menu bar
        "Caps Lock on all keyboards": "Caps Lock trên mọi bàn phím",
        "A password field is active: Hyper waits until you leave it.": "Đang ở ô mật khẩu: Hyper tạm ngưng tới khi bạn rời ô.",
        "Preferences…": "Mở cài đặt…",

        // About
        "Remap keys for each keyboard, turn Caps Lock into Esc and Hyper, and give Hyper a layer of arrows, apps and shortcuts.":
            "Đổi phím cho từng bàn phím, biến Caps Lock thành Esc và Hyper, cùng lớp Hyper cho phím mũi tên, mở app và phím tắt.",
        "License": "Giấy phép",
        "Part of LongoKit · Crafted by %@": "Thuộc bộ LongoKit · Thực hiện bởi %@",
    ]
}
