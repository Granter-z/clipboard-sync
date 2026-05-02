#include "clipboard_monitor.h"
#include <shlobj.h>
#include <algorithm>
#include <sstream>
#include <vector>
#include <gdiplus.h>

#pragma comment(lib, "gdiplus.lib")

static ULONG_PTR g_gdiplusToken = 0;

ClipboardMonitor::ClipboardMonitor(flutter::BinaryMessenger* messenger)
    : hwnd_(nullptr), isMonitoring_(false), gdiplusInitialized_(false) {

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

    WNDCLASS wc = {0};
    wc.lpfnWndProc = ClipboardMonitor::WndProc;
    wc.hInstance = GetModuleHandle(nullptr);
    wc.lpszClassName = L"ClipboardMonitorWindow";
    RegisterClass(&wc);

    hwnd_ = CreateWindowEx(
        WS_EX_TOOLWINDOW, L"ClipboardMonitorWindow", L"ClipboardMonitor",
        WS_POPUP, 0, 0, 0, 0,
        nullptr, nullptr, GetModuleHandle(nullptr), this);

    if (hwnd_) {
        SetWindowLongPtr(hwnd_, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(this));
    }

    Gdiplus::GdiplusStartupInput gdiplusStartupInput;
    if (Gdiplus::GdiplusStartup(&g_gdiplusToken, &gdiplusStartupInput, nullptr) == Gdiplus::Ok) {
        gdiplusInitialized_ = true;
    }
}

ClipboardMonitor::~ClipboardMonitor() {
    StopMonitoring();
    if (hwnd_) {
        DestroyWindow(hwnd_);
        hwnd_ = nullptr;
    }
    if (gdiplusInitialized_ && g_gdiplusToken) {
        Gdiplus::GdiplusShutdown(g_gdiplusToken);
        g_gdiplusToken = 0;
        gdiplusInitialized_ = false;
    }
}

void ClipboardMonitor::StartMonitoring() {
    if (isMonitoring_ || !hwnd_) return;
    AddClipboardFormatListener(hwnd_);
    isMonitoring_ = true;
}

void ClipboardMonitor::StopMonitoring() {
    if (!isMonitoring_ || !hwnd_) return;
    RemoveClipboardFormatListener(hwnd_);
    isMonitoring_ = false;
}

LRESULT CALLBACK ClipboardMonitor::WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    auto* self = reinterpret_cast<ClipboardMonitor*>(GetWindowLongPtr(hwnd, GWLP_USERDATA));

    switch (msg) {
        case WM_CLIPBOARDUPDATE: {
            if (self) {
                self->OnClipboardChange();
            }
            return 0;
        }
    }
    return DefWindowProc(hwnd, msg, wParam, lParam);
}

void ClipboardMonitor::OnClipboardChange() {
    if (!isMonitoring_) return;

    // Debounce: ignore events within 100ms of the last one
    auto now = std::chrono::steady_clock::now();
    auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(now - lastEventTime_).count();
    if (elapsed < 100) return;

    // Retry reading clipboard - OpenClipboard can fail if another process holds the lock
    for (int retry = 0; retry < 5; retry++) {
        if (HasClipboardImage()) {
            auto base64Image = GetClipboardImageAsBase64();
            if (!base64Image.empty() && base64Image != lastImage_) {
                lastImage_ = base64Image;
                lastText_.clear();
                lastEventTime_ = now;
                flutter::EncodableMap event;
                event[flutter::EncodableValue("type")] = flutter::EncodableValue("image");
                event[flutter::EncodableValue("data")] = flutter::EncodableValue(base64Image);
                channel_->InvokeMethod("onClipboardChanged",
                    std::make_unique<flutter::EncodableValue>(event));
                return;
            }
            if (!base64Image.empty()) return; // Same image, skip
        }
        else {
            auto text = GetClipboardText();
            if (!text.empty() && text != lastText_) {
                lastText_ = text;
                lastImage_.clear();
                lastEventTime_ = now;
                flutter::EncodableMap event;
                event[flutter::EncodableValue("type")] = flutter::EncodableValue("text");
                event[flutter::EncodableValue("data")] = flutter::EncodableValue(text);
                channel_->InvokeMethod("onClipboardChanged",
                    std::make_unique<flutter::EncodableValue>(event));
                return;
            }
            if (!text.empty()) return; // Same text, skip
        }
        // Clipboard read failed (likely locked), wait and retry
        Sleep(10);
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
    UINT pngFormat = RegisterClipboardFormatA("PNG");
    bool hasImage = (pngFormat && IsClipboardFormatAvailable(pngFormat)) ||
                    IsClipboardFormatAvailable(CF_DIB) ||
                    IsClipboardFormatAvailable(CF_BITMAP);
    CloseClipboard();
    return hasImage;
}

std::string ClipboardMonitor::GetClipboardImageAsBase64() {
    if (!OpenClipboard(hwnd_)) return "";

    std::string result;

    UINT pngFormat = RegisterClipboardFormatA("PNG");
    HANDLE hData = nullptr;
    bool isPng = false;

    if (pngFormat && IsClipboardFormatAvailable(pngFormat)) {
        hData = GetClipboardData(pngFormat);
        isPng = true;
    }
    if (!hData) {
        hData = GetClipboardData(CF_DIB);
        isPng = false;
    }

    if (hData) {
        auto* pData = static_cast<BYTE*>(GlobalLock(hData));
        if (pData) {
            SIZE_T dataSize = GlobalSize(hData);

            if (isPng) {
                size_t b64Size = ((dataSize + 2) / 3) * 4;
                result.resize(b64Size);
                const char* b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
                size_t i = 0, j = 0;
                while (i < dataSize) {
                    unsigned char b0 = pData[i++];
                    unsigned char b1 = (i < (int)dataSize) ? pData[i++] : 0;
                    unsigned char b2 = (i < (int)dataSize) ? pData[i++] : 0;
                    result[j++] = b64chars[b0 >> 2];
                    result[j++] = b64chars[((b0 & 0x03) << 4) | (b1 >> 4)];
                    result[j++] = (i - 1 < (int)dataSize) ? b64chars[((b1 & 0x0F) << 2) | (b2 >> 6)] : '=';
                    result[j++] = (i < (int)dataSize) ? b64chars[b2 & 0x3F] : '=';
                }
            } else if (gdiplusInitialized_) {
                BITMAPINFOHEADER* bih = reinterpret_cast<BITMAPINFOHEADER*>(pData);
                int width = bih->biWidth;
                int height = abs(bih->biHeight);
                int bpp = bih->biBitCount;

                Gdiplus::PixelFormat pf;
                switch (bpp) {
                    case 32: pf = PixelFormat32bppARGB; break;
                    case 24: pf = PixelFormat24bppRGB; break;
                    default: pf = PixelFormat32bppARGB; break;
                }

                Gdiplus::Bitmap bmp(width, height, pf);
                Gdiplus::Rect rect(0, 0, width, height);
                Gdiplus::BitmapData bmpData;
                if (bmp.LockBits(&rect, Gdiplus::ImageLockModeWrite, pf, &bmpData) == Gdiplus::Ok) {
                    BYTE* srcPtr = pData + bih->biSize;
                    BYTE* dstPtr = static_cast<BYTE*>(bmpData.Scan0);
                    int srcStride = ((width * bpp + 31) / 32) * 4;
                    for (int y = 0; y < height; y++) {
                        memcpy(dstPtr + y * bmpData.Stride, srcPtr + y * srcStride, srcStride);
                    }
                    bmp.UnlockBits(&bmpData);

                    IStream* stream = nullptr;
                    if (CreateStreamOnHGlobal(nullptr, TRUE, &stream) == S_OK) {
                        CLSID pngClsid;
                        CLSIDFromString(L"{557CF406-1A04-11D3-9A73-0000F81EF32E}", &pngClsid);
                        if (bmp.Save(stream, &pngClsid, nullptr) == Gdiplus::Ok) {
                            STATSTG stat;
                            stream->Stat(&stat, STATFLAG_NONAME);
                            ULONG pngSize = static_cast<ULONG>(stat.cbSize.LowPart);

                            LARGE_INTEGER zero = {};
                            stream->Seek(zero, STREAM_SEEK_SET, nullptr);

                            std::vector<BYTE> pngData(pngSize);
                            ULONG bytesRead = 0;
                            stream->Read(pngData.data(), pngSize, &bytesRead);

                            int b64Size = ((bytesRead + 2) / 3) * 4;
                            result.resize(b64Size);
                            const char* b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
                            size_t ii = 0, jj = 0;
                            while (ii < bytesRead) {
                                unsigned char b0 = pngData[ii++];
                                unsigned char b1 = (ii < bytesRead) ? pngData[ii++] : 0;
                                unsigned char b2 = (ii < bytesRead) ? pngData[ii++] : 0;
                                result[jj++] = b64chars[b0 >> 2];
                                result[jj++] = b64chars[((b0 & 0x03) << 4) | (b1 >> 4)];
                                result[jj++] = (ii - 1 < bytesRead) ? b64chars[((b1 & 0x0F) << 2) | (b2 >> 6)] : '=';
                                result[jj++] = (ii < bytesRead) ? b64chars[b2 & 0x3F] : '=';
                            }
                        }
                        stream->Release();
                    }
                }
            }
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
    if (!gdiplusInitialized_) return;

    std::vector<BYTE> pngBytes;
    const std::string chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    size_t inputLen = base64Data.length();
    size_t i = 0;
    while (i < inputLen) {
        size_t a = chars.find(base64Data[i++]);
        size_t b = (i < inputLen) ? chars.find(base64Data[i++]) : 0;
        size_t c = (i < inputLen) ? chars.find(base64Data[i++]) : 0;
        size_t d = (i < inputLen) ? chars.find(base64Data[i++]) : 0;
        if (a == std::string::npos) a = 0;
        if (b == std::string::npos) b = 0;
        if (c == std::string::npos) c = 0;
        if (d == std::string::npos) d = 0;
        pngBytes.push_back(static_cast<BYTE>((a << 2) | (b >> 4)));
        if (base64Data[i - 2] != '=') pngBytes.push_back(static_cast<BYTE>(((b & 0x0F) << 4) | (c >> 2)));
        if (base64Data[i - 1] != '=') pngBytes.push_back(static_cast<BYTE>(((c & 0x03) << 6) | d));
    }

    HGLOBAL hMem = GlobalAlloc(GMEM_MOVEABLE, pngBytes.size());
    if (!hMem) return;
    void* pMem = GlobalLock(hMem);
    memcpy(pMem, pngBytes.data(), pngBytes.size());
    GlobalUnlock(hMem);

    IStream* stream = nullptr;
    if (CreateStreamOnHGlobal(hMem, TRUE, &stream) != S_OK) {
        GlobalFree(hMem);
        return;
    }

    Gdiplus::Bitmap* bmp = Gdiplus::Bitmap::FromStream(stream);
    if (!bmp || bmp->GetLastStatus() != Gdiplus::Ok) {
        delete bmp;
        stream->Release();
        return;
    }

    int width = bmp->GetWidth();
    int height = bmp->GetHeight();

    BITMAPINFOHEADER bih = {};
    bih.biSize = sizeof(BITMAPINFOHEADER);
    bih.biWidth = width;
    bih.biHeight = -height;
    bih.biPlanes = 1;
    bih.biBitCount = 32;
    bih.biCompression = BI_RGB;
    int stride = ((width * 32 + 31) / 32) * 4;
    int dibSize = sizeof(BITMAPINFOHEADER) + stride * height;

    HGLOBAL hDib = GlobalAlloc(GMEM_MOVEABLE, dibSize);
    if (!hDib) {
        delete bmp;
        stream->Release();
        return;
    }

    auto* pDib = static_cast<BYTE*>(GlobalLock(hDib));
    memcpy(pDib, &bih, sizeof(BITMAPINFOHEADER));

    Gdiplus::BitmapData bmpData;
    Gdiplus::Rect rect(0, 0, width, height);
    if (bmp->LockBits(&rect, Gdiplus::ImageLockModeRead, PixelFormat32bppARGB, &bmpData) == Gdiplus::Ok) {
        BYTE* src = static_cast<BYTE*>(bmpData.Scan0);
        BYTE* dst = pDib + sizeof(BITMAPINFOHEADER);
        for (int y = 0; y < height; y++) {
            memcpy(dst + y * stride, src + y * bmpData.Stride, width * 4);
        }
        bmp->UnlockBits(&bmpData);
    }
    GlobalUnlock(hDib);

    delete bmp;
    stream->Release();

    UINT pngFormat = RegisterClipboardFormatA("PNG");
    if (OpenClipboard(hwnd_)) {
        EmptyClipboard();
        HGLOBAL hPng = GlobalAlloc(GMEM_MOVEABLE, pngBytes.size());
        if (hPng) {
            void* pPng = GlobalLock(hPng);
            memcpy(pPng, pngBytes.data(), pngBytes.size());
            GlobalUnlock(hPng);
            SetClipboardData(pngFormat, hPng);
        }
        SetClipboardData(CF_DIB, hDib);
        CloseClipboard();
    } else {
        GlobalFree(hDib);
    }
}
