/// Vietnamese strings, keyed by the English text passed to `L()` (including LongoKitUI's own strings).
enum Vietnamese {
    static let strings: [String: String] = [
        // Window & tabs
        "General": "Chung",
        "Shortcuts": "Phím tắt",
        "About": "Giới thiệu",
        "Ready": "Sẵn sàng",
        "Needs permission": "Cần cấp quyền",
        "Shortcuts are on and captures work": "Phím tắt đang bật và chụp được màn hình",
        "Allow Screen Recording to capture the screen": "Cho phép Ghi màn hình để chụp được màn hình",
        "Restore Defaults": "Khôi phục mặc định",
        "Restore defaults?": "Khôi phục mặc định?",
        "The save folder, what happens after a capture, and every shortcut go back to the defaults.":
            "Thư mục lưu, việc làm sau mỗi lần chụp và mọi phím tắt sẽ về mặc định.",
        "Cancel": "Huỷ",
        "Crafted by ": "Thực hiện bởi ",
        "Quit": "Thoát",
        "Quit %@: its shortcuts stop until it's opened again": "Thoát %@: phím tắt ngừng chạy cho tới khi mở lại app",
        "Close window (keeps running in the menu bar)": "Đóng cửa sổ (app vẫn chạy nền)",
        "Minimize": "Thu nhỏ",
        "This window has a fixed size": "Cửa sổ có kích thước cố định",
        "Coming soon": "Sắp có",
        "Close": "Đóng",
        "Close without changes": "Đóng, không thay đổi",
        "Selected": "Đang chọn",

        // Actions
        "Capture Area": "Chụp vùng",
        "Capture Window": "Chụp cửa sổ",
        "Capture Full Screen": "Chụp toàn màn hình",
        "Copy Text (OCR)": "Copy chữ (OCR)",
        "Record Screen": "Quay màn hình",
        "Copy Last Capture": "Copy ảnh vừa chụp",
        "Open Save Folder": "Mở thư mục lưu",
        "Open Settings": "Mở cài đặt",
        "Drag over the part of the screen to capture. Space switches to windows.":
            "Kéo chọn phần màn hình cần chụp. Nhấn Space để chọn cửa sổ.",
        "Click a window to capture it with its shadow.": "Bấm vào một cửa sổ để chụp, kèm cả bóng đổ.",
        "The whole screen under the pointer.": "Cả màn hình đang có con trỏ.",
        "Drag over text: it's read on this Mac and copied, ready to paste.":
            "Kéo chọn vùng có chữ: chữ được đọc ngay trên máy và copy sẵn để dán.",
        "Record the screen or a part of it, and stop with the same shortcut.":
            "Quay cả màn hình hoặc một phần, bấm lại phím tắt để dừng.",
        "Puts the last capture on the clipboard again.": "Copy lại ảnh vừa chụp vào clipboard.",
        "Shows the folder captures are saved in.": "Mở thư mục đang lưu ảnh chụp.",
        "Opens this window, even with the menu bar icon hidden.": "Mở cửa sổ này, kể cả khi đã ẩn icon trên thanh menu.",

        // Overlay & results
        "Drag to capture  ·  Space: pick a window  ·  Esc: cancel": "Kéo để chụp  ·  Space: chọn cửa sổ  ·  Esc: huỷ",
        "Click a window to capture it  ·  Space: drag an area  ·  Esc: cancel": "Bấm vào cửa sổ để chụp  ·  Space: kéo chọn vùng  ·  Esc: huỷ",
        "Drag over text to copy it  ·  Esc: cancel": "Kéo chọn vùng có chữ để copy  ·  Esc: huỷ",
        "Copied 1 line of text": "Đã copy 1 dòng chữ",
        "Copied %d lines of text": "Đã copy %d dòng chữ",
        "No text found": "Không thấy chữ",
        "Try a larger area, or text with more contrast.": "Thử chọn vùng rộng hơn, hoặc chữ rõ nét hơn.",
        "Couldn't read the text": "Không đọc được chữ",
        "Couldn't capture": "Không chụp được",
        "Couldn't save": "Không lưu được",
        "Nothing captured yet": "Chưa chụp ảnh nào",
        "Last capture copied": "Đã copy ảnh vừa chụp",
        "Screen recording is coming soon": "Quay màn hình sắp có",
        "It's the next part of %@ being built.": "Đây là phần tiếp theo của %@ đang được làm.",
        "Copy": "Copy",
        "Copied": "Đã copy",
        "Show in Finder": "Mở trong Finder",
        "Drag into another app": "Kéo thả sang app khác",
        "Drag into another app, or click to open": "Kéo thả sang app khác, hoặc bấm để mở",

        // General tab
        "Screen Recording": "Ghi màn hình",
        "macOS asks before an app can see the screen.": "macOS cần bạn cho phép thì app mới thấy được màn hình.",
        "Grant Access…": "Cấp quyền…",
        "Turn on %@ in System Settings › Privacy & Security › Screen & System Audio Recording. If macOS asks, quit and reopen the app.":
            "Bật %@ trong Cài đặt hệ thống › Quyền riêng tư & Bảo mật › Ghi màn hình & âm thanh hệ thống. Nếu macOS hỏi, hãy thoát rồi mở lại app.",
        "Captures": "Ảnh chụp",
        "Where captures are saved, and what happens after each one.": "Nơi lưu ảnh chụp, và việc làm sau mỗi lần chụp.",
        "Save location": "Thư mục lưu",
        "Change…": "Đổi…",
        "Choose": "Chọn",
        "Captures are saved in this folder.": "Ảnh chụp sẽ được lưu trong thư mục này.",
        "Save to the folder": "Lưu vào thư mục",
        "On: each capture is saved as a PNG file named with its date and time, and copied.":
            "Bật: mỗi ảnh chụp được lưu thành file PNG đặt tên theo ngày giờ, và copy vào clipboard.",
        "Off: captures only go to the clipboard, ready to paste. Nothing is saved.":
            "Tắt: ảnh chụp chỉ nằm trong clipboard để dán nhanh, không lưu file nào.",
        "Always on while captures aren't saved.": "Luôn bật khi không lưu ảnh vào thư mục.",
        "Saved and copied": "Lưu file và copy",
        "Clipboard only": "Chỉ copy vào clipboard",
        "Copy to the clipboard": "Copy vào clipboard",
        "Paste the capture straight into a chat, a document or Finder.": "Dán ảnh thẳng vào khung chat, tài liệu hay Finder.",
        "Show a preview": "Hiện ảnh xem nhanh",
        "A thumbnail in the corner to drag into another app, copy, or show in Finder.":
            "Ảnh nhỏ ở góc màn hình để kéo sang app khác, copy hoặc mở trong Finder.",
        "Play the capture sound": "Phát tiếng chụp",
        "The same sound as macOS screenshots.": "Giống tiếng chụp màn hình của macOS.",
        "Startup & Behavior": "Khởi động & Hoạt động",
        "Language, look, and how %@ starts.": "Ngôn ngữ, giao diện và cách %@ khởi động.",
        "Language": "Ngôn ngữ",
        "Language used throughout the app.": "Ngôn ngữ dùng trong toàn bộ app.",
        "Appearance": "Giao diện",
        "Follow macOS, or always use dark or light.": "Theo macOS, hoặc luôn tối hay luôn sáng.",
        "System": "Hệ thống",
        "Dark": "Tối",
        "Light": "Sáng",
        "Theme: follow macOS": "Giao diện: theo macOS",
        "Theme: dark": "Giao diện: tối",
        "Theme: light": "Giao diện: sáng",
        "Start at Login": "Mở cùng máy",
        "%@ waits in the background for its shortcuts from the moment your Mac starts.":
            "%@ chạy nền chờ phím tắt ngay từ lúc máy khởi động.",
        "Show icon in menu bar": "Hiện icon trên thanh menu",
        "Captures and settings from the menu bar.": "Chụp và mở cài đặt ngay từ menu bar.",
        "Hidden: press %@ or open %@ again to get back here.": "Đang ẩn: bấm %@ hoặc mở lại %@ để quay lại đây.",
        "Hidden: open %@ again to get back here.": "Đang ẩn: mở lại %@ để quay lại đây.",

        // Shortcuts tab
        "Click a shortcut, then press the keys you want. They work in every app, with no permission needed.":
            "Bấm vào ô phím tắt rồi nhấn tổ hợp phím muốn dùng. Phím tắt chạy trong mọi app, không cần cấp quyền.",
        "Reset": "Đặt lại",
        "Back to the default shortcuts": "Về phím tắt mặc định",
        "While recording: Esc cancels, ⌫ removes the shortcut.": "Khi đang ghi phím: Esc để huỷ, ⌫ để xoá phím tắt.",
        "Capture": "Chụp",
        "Quick access": "Truy cập nhanh",
        "Press keys…": "Nhấn phím…",
        "Record Shortcut": "Ghi phím tắt",
        "Click to record a new shortcut": "Bấm để ghi phím tắt mới",
        "Press the new shortcut · Esc cancels · ⌫ removes it": "Nhấn phím tắt mới · Esc để huỷ · ⌫ để xoá",
        "Remove this shortcut": "Xoá phím tắt này",
        "Add ⌘, ⌥, ⌃ or ⇧ to the key (F1–F19 work on their own).": "Thêm ⌘, ⌥, ⌃ hoặc ⇧ vào phím (riêng F1–F19 dùng một mình được).",
        "%@ already uses %@.": "%@ đã dùng %@.",
        "Another app already uses this shortcut, so it won't work here. Pick another one.":
            "Một app khác đã dùng phím tắt này nên nó không chạy ở đây. Hãy chọn phím khác.",
        "macOS uses this shortcut too. Turn it off in System Settings › Keyboard › Keyboard Shortcuts, or pick another one.":
            "macOS cũng dùng phím tắt này. Tắt nó trong Cài đặt hệ thống › Bàn phím › Phím tắt, hoặc chọn phím khác.",

        // Menu & About
        "Preferences…": "Mở cài đặt…",
        "Screenshots and text from the screen in one shortcut: saved to your folder, on the clipboard, ready to paste. Light, and quiet in the background.":
            "Chụp màn hình và lấy chữ trên màn hình chỉ với một phím tắt: lưu vào thư mục, có sẵn trong clipboard để dán. Nhẹ, chạy nền êm.",
        "License": "Giấy phép",
        "Part of LongoKit · Crafted by %@": "Thuộc LongoKit · Thực hiện bởi %@",

        // Compact General tab
        "Granted": "Đã cấp",
        "App": "Ứng dụng",
        "Permissions": "Quyền",
    ]
}
