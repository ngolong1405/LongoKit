/// Vietnamese strings, keyed by the English text passed to `L()`. The modules bring their own tables.
enum Vietnamese {
    static let strings: [String: String] = [
        // Window
        "General": "Chung",
        "About": "Giới thiệu",
        "Modules": "Module",
        "%d of %d on": "Bật %d/%d",
        "Open as its own app": "Đang mở dưới dạng app riêng",
        "Quit": "Thoát",
        "Quit LongoKit: every module stops until it's opened again": "Thoát LongoKit: mọi module dừng cho tới khi mở lại",

        // General
        "Buttons, gestures & smooth scrolling": "Nút, cử chỉ & cuộn mượt",
        "Brightness & volume for every display": "Độ sáng & âm lượng cho mọi màn hình",
        "Key remapping & the Hyper layer": "Đổi phím & lớp phím Hyper",
        "Screenshots, recording & copying text on screen": "Chụp, quay màn hình & copy chữ trên màn hình",
        "Files between your devices, nearby": "Gửi file giữa các máy ở gần",
        "Open %@": "Mở %@",
        "Run Here": "Chạy ở đây",
        "%@ is open as its own app. Quit it so LongoKit runs it instead.":
            "%@ đang mở dưới dạng app riêng. Thoát app đó để LongoKit chạy thay.",
        "Every module's quick controls, from one icon in the menu bar.":
            "Điều khiển nhanh của mọi module, từ một icon trên thanh menu.",

        // A module that isn't running
        "This module is off: it takes no memory and asks for no permissions.":
            "Module này đang tắt: không tốn RAM và không xin quyền gì.",
        "Turn On": "Bật",
        "Quit %@": "Thoát %@",

        // Turning modules off, and their own apps
        "Cancel": "Huỷ",
        "%@ is also open on its own": "%@ cũng đang mở riêng",
        "LongoKit already runs %@. Both at once would act on everything twice.":
            "LongoKit đã chạy %@. Mở cả hai cùng lúc thì mọi thao tác sẽ bị xử lý hai lần.",
        "Keep Both": "Giữ cả hai",

        // About
        "Longo Mouse, Display, Keys, Shot and Share in one menu bar app. Turn on the ones you need: the others take no memory and ask for nothing.":
            "Longo Mouse, Display, Keys, Shot và Share trong một app trên thanh menu. Bật module bạn cần: các module còn lại không tốn RAM và không xin quyền gì.",
        "Website": "Website",
        "License": "Giấy phép",
        "Crafted by %@": "Thực hiện bởi %@",

        // Menu
        "Settings…": "Cài đặt…",
        "%@ (off)": "%@ (đang tắt)",
        "Needs permission": "Cần cấp quyền",
        "%@ · needs permission": "%@ · cần cấp quyền",
        "%@ (open on its own)": "%@ (đang mở riêng)",
        "Off": "Đang tắt",
        "%@ · open as its own app": "%@ · đang mở dưới dạng app riêng",
    ]
}
