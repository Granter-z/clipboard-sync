#include "clipboard_monitor.h"
#include <shlobj.h>
#include <algorithm>
#include <sstream>

ClipboardMonitor::ClipboardMonitor(flutter::BinaryMessenger* messenger)
    : hwnd_(nullptr), nextViewer_(nullptr), isMonitoring_(false) {

    channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        messenger, "com.clipsync/clipboard",
        &flutter::StandardMethodCodec::GetInstance());

    channel_->SetMethodCallHandler([this](const auto& call, auto result) {
        const auto& method = call.method_name();

        if (method == "startMonitoring") {
            StartMonitoring();
            result->Success();
        }
        else if (method == "stopMonitoring") {
            StopMonitoring();
            result->Success();
        }
        else if (method == "readText") {
            auto text = ReadText();
            result->Success(flutter::EncodableValue(text));
        }
        else if (method == "writeText") {
            auto text = std::get<std::string>(*call.arguments());
            WriteText(text);
            result->Success();
        }
        else if (method == "readImage") {
            auto image = ReadImage();
            result->Success(flutter::EncodableValue(image));
        }
        else if (method == "writeImage") {
            auto data = std::get<std::string>(*call.arguments());
            WriteImage(data);
            result->Success();
        }
        else {
            result->NotImplemented();
        }
    });

    // Register hidden window class for clipboard monitoring
    WNDCLASS wc = {0};
    wc.lpfnWndProc = ClipboardMonitor::WndProc;
    wc.hInstance = GetModuleHandle(nullptr);
    wc.lpszClassName = L"ClipboardMonitorWindow";
    RegisterClass(&wc);

    hwnd_ = CreateWindowEx(
        0, L"ClipboardMonitorWindow", L"ClipboardMonitor",
        0, 0, 0, 0, 0,
        HWND_MESSAGE, nullptr, GetModuleHandle(nullptr), this);

    if (hwnd_) {
        SetWindowLongPtr(hwnd_, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(this));
    }
}

ClipboardMonitor::~ClipboardMonitor() {
    StopMonitoring();
    if (hwnd_) {
        DestroyWindow(hwnd_);
        hwnd_ = nullptr;
    }
}

void ClipboardMonitor::StartMonitoring() {
    if (isMonitoring_ || !hwnd_) return;
    nextViewer_ = SetClipboardViewer(hwnd_);
    isMonitoring_ = true;
}

void ClipboardMonitor::StopMonitoring() {
    if (!isMonitoring_) return;
    if (hwnd_ && nextViewer_) {
        ChangeClipboardChain(hwnd_, nextViewer_);
    }
    nextViewer_ = nullptr;
    isMonitoring_ = false;
}

LRESULT CALLBACK ClipboardMonitor::WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    auto* self = reinterpret_cast<ClipboardMonitor*>(GetWindowLongPtr(hwnd, GWLP_USERDATA));

    switch (msg) {
        case WM_DRAWCLIPBOARD: {
            if (self) {
                self->OnClipboardChange();
            }
            // Pass to next viewer
            if (self && self->nextViewer_) {
                SendMessage(self->nextViewer_, msg, wParam, lParam);
            }
            return 0;
        }
        case WM_CHANGECBCHAIN: {
            if (self && self->nextViewer_ == reinterpret_cast<HWND>(wParam)) {
                self->nextViewer_ = reinterpret_cast<HWND>(lParam);
            }
            else if (self && self->nextViewer_) {
                SendMessage(self->nextViewer_, msg, wParam, lParam);
            }
            return 0;
        }
    }
    return DefWindowProc(hwnd, msg, wParam, lParam);
}

void ClipboardMonitor::OnClipboardChange() {
    if (!isMonitoring_) return;

    if (HasClipboardImage()) {
        auto base64Image = GetClipboardImageAsBase64();
        if (!base64Image.empty()) {
            flutter::EncodableMap event;
            event[flutter::EncodableValue("type")] = flutter::EncodableValue("image");
            event[flutter::EncodableValue("data")] = flutter::EncodableValue(base64Image);
            channel_->InvokeMethod("onClipboardChanged",
                std::make_unique<flutter::EncodableValue>(event));
        }
    }
    else {
        auto text = GetClipboardText();
        if (!text.empty()) {
            flutter::EncodableMap event;
            event[flutter::EncodableValue("type")] = flutter::EncodableValue("text");
            event[flutter::EncodableValue("data")] = flutter::EncodableValue(text);
            channel_->InvokeMethod("onClipboardChanged",
                std::make_unique<flutter::EncodableValue>(event));
        }
    }
}

std::string ClipboardMonitor::GetClipboardText() {
    if (!OpenClipboard(hwnd_)) return "";

    std::string result;
    HANDLE hData = GetClipboardData(CF_UNICODETEXT);
    if (hData) {
        auto* pText = static_cast<wchar_t*>(GlobalLock(hData));
        if (pText) {
            int sizeNeeded = WideCharToMultiByte(CP_UTF8, 0, pText, -1, nullptr, 0, nullptr, nullptr);
            if (sizeNeeded > 0) {
                result.resize(sizeNeeded - 1);
                WideCharToMultiByte(CP_UTF8, 0, pText, -1, &result[0], sizeNeeded, nullptr, nullptr);
            }
            GlobalUnlock(hData);
        }
    }
    CloseClipboard();
    return result;
}

bool ClipboardMonitor::HasClipboardImage() {
    if (!OpenClipboard(hwnd_)) return false;
    bool hasImage = (GetClipboardData(CF_DIB) != nullptr) ||
                    (GetClipboardData(CF_BITMAP) != nullptr);
    CloseClipboard();
    return hasImage;
}

std::string ClipboardMonitor::GetClipboardImageAsBase64() {
    if (!OpenClipboard(hwnd_)) return "";

    std::string result;
    HANDLE hData = GetClipboardData(CF_DIB);
    if (!hData) {
        hData = GetClipboardData(CF_BITMAP);
    }

    if (hData) {
        auto* pData = static_cast<BYTE*>(GlobalLock(hData));
        if (pData) {
            SIZE_T dataSize = GlobalSize(hData);
            
            // Convert DIB to PNG in memory using GDI+
            // For simplicity, just base64 encode the raw DIB data
            const char* b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
            std::string base64;
            int i = 0;
            while (i < (int)dataSize) {
                unsigned char b0 = pData[i++];
                unsigned char b1 = (i < (int)dataSize) ? pData[i++] : 0;
                unsigned char b2 = (i < (int)dataSize) ? pData[i++] : 0;
                base64 += b64chars[b0 >> 2];
                base64 += b64chars[((b0 & 0x03) << 4) | (b1 >> 4)];
                base64 += (i - 1 < (int)dataSize) ? b64chars[((b1 & 0x0F) << 2) | (b2 >> 6)] : '=';
                base64 += (i < (int)dataSize) ? b64chars[b2 & 0x3F] : '=';
            }
            result = base64;
            GlobalUnlock(hData);
        }
    }
    CloseClipboard();
    return result;
}

void ClipboardMonitor::WriteText(const std::string& text) {
    SetClipboardTextInternal(text);
}

void ClipboardMonitor::WriteImage(const std::string& base64Data) {
    SetClipboardImageInternal(base64Data);
}

std::string ClipboardMonitor::ReadText() {
    return GetClipboardText();
}

std::string ClipboardMonitor::ReadImage() {
    return GetClipboardImageAsBase64();
}

void ClipboardMonitor::SetClipboardTextInternal(const std::string& text) {
    if (!OpenClipboard(hwnd_)) return;
    EmptyClipboard();

    int wideLen = MultiByteToWideChar(CP_UTF8, 0, text.c_str(), -1, nullptr, 0);
    if (wideLen > 0) {
        HGLOBAL hGlobal = GlobalAlloc(GMEM_MOVEABLE, wideLen * sizeof(wchar_t));
        if (hGlobal) {
            auto* pWide = static_cast<wchar_t*>(GlobalLock(hGlobal));
            if (pWide) {
                MultiByteToWideChar(CP_UTF8, 0, text.c_str(), -1, pWide, wideLen);
                GlobalUnlock(hGlobal);
                SetClipboardData(CF_UNICODETEXT, hGlobal);
            }
        }
    }
    CloseClipboard();
}

void ClipboardMonitor::SetClipboardImageInternal(const std::string& base64Data) {
    // For V1, decoding base64 to bitmap and putting it on clipboard
    // is complex. We'll store the base64 string for now and rely on the
    // receiving device's ability to handle it via shared memory.
    // A full implementation would use GDI+ to decode PNG and set CF_DIB.
    
    // Simplified: We'll use CF_TEXT to store a marker, and the actual
    // image data flows through our WebSocket protocol, not native clipboard
    SetClipboardTextInternal("[clipboard_sync_image]");
}
