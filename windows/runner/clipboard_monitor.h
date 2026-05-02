#pragma once

#include <windows.h>
#include <flutter/method_channel.h>
#include <flutter/binary_messenger.h>
#include <flutter/standard_method_codec.h>
#include <string>
#include <memory>
#include <chrono>

class ClipboardMonitor {
public:
    explicit ClipboardMonitor(flutter::BinaryMessenger* messenger);
    ~ClipboardMonitor();

    void StartMonitoring();
    void StopMonitoring();

    void WriteText(const std::string& text);
    std::string ReadText();
    std::string ReadImage();
    void WriteImage(const std::string& base64Data);

private:
    static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam);

    HWND hwnd_;
    bool isMonitoring_;
    bool gdiplusInitialized_;
    std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;

    // Dedup state
    std::string lastText_;
    std::string lastImage_;
    std::chrono::steady_clock::time_point lastEventTime_;

    void OnClipboardChange();
    std::string GetClipboardText();
    bool HasClipboardImage();
    std::string GetClipboardImageAsBase64();
    void SetClipboardTextInternal(const std::string& text);
    void SetClipboardImageInternal(const std::string& base64Data);
};
