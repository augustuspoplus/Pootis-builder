#include "net/Http.h"

#if defined(_WIN32)
#include <windows.h>
#include <winhttp.h>
#endif

#include <vector>

namespace pb::net {
namespace {

#if defined(_WIN32)

std::wstring widen(const std::string& s) {
    if (s.empty()) return {};
    const int n = MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), nullptr, 0);
    std::wstring w(n, L'\0');
    MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), w.data(), n);
    return w;
}

std::string narrow(const std::wstring& w) {
    if (w.empty()) return {};
    const int n = WideCharToMultiByte(CP_UTF8, 0, w.data(), (int)w.size(), nullptr, 0,
                                      nullptr, nullptr);
    std::string s(n, '\0');
    WideCharToMultiByte(CP_UTF8, 0, w.data(), (int)w.size(), s.data(), n, nullptr,
                        nullptr);
    return s;
}

// RAII for the three WinHTTP handle kinds (all closed the same way).
struct Handle {
    HINTERNET h = nullptr;
    ~Handle() { if (h) WinHttpCloseHandle(h); }
    explicit operator bool() const { return h != nullptr; }
};

std::string lastError(const char* what) {
    return std::string(what) + " failed (win32 " + std::to_string(GetLastError()) + ")";
}

Response request(const char* verb, const std::string& url, const std::string& body,
                 const Headers& headers, int timeoutMs) {
    Response r;
    const std::wstring wurl = widen(url);

    URL_COMPONENTS uc{};
    uc.dwStructSize = sizeof(uc);
    wchar_t host[256] = {0}, path[4096] = {0};
    uc.lpszHostName = host;      uc.dwHostNameLength = 255;
    uc.lpszUrlPath = path;       uc.dwUrlPathLength = 4095;
    if (!WinHttpCrackUrl(wurl.c_str(), 0, 0, &uc)) {
        r.error = "bad URL: " + url;
        return r;
    }
    const bool https = uc.nScheme == INTERNET_SCHEME_HTTPS;

    Handle session{WinHttpOpen(L"PootisBuilder/1.0",
                               WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY,
                               WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0)};
    if (!session) { r.error = lastError("WinHttpOpen"); return r; }
    WinHttpSetTimeouts(session.h, timeoutMs, timeoutMs, timeoutMs, timeoutMs);

    Handle conn{WinHttpConnect(session.h, host, uc.nPort, 0)};
    if (!conn) { r.error = lastError("WinHttpConnect"); return r; }

    Handle req{WinHttpOpenRequest(conn.h, widen(verb).c_str(), path, nullptr,
                                  WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES,
                                  https ? WINHTTP_FLAG_SECURE : 0)};
    if (!req) { r.error = lastError("WinHttpOpenRequest"); return r; }

    std::wstring hdr;
    for (const auto& [k, v] : headers) hdr += widen(k + ": " + v + "\r\n");
    if (!hdr.empty())
        WinHttpAddRequestHeaders(req.h, hdr.c_str(), (DWORD)-1,
                                 WINHTTP_ADDREQ_FLAG_ADD |
                                     WINHTTP_ADDREQ_FLAG_REPLACE);

    if (!WinHttpSendRequest(req.h, WINHTTP_NO_ADDITIONAL_HEADERS, 0,
                            body.empty() ? WINHTTP_NO_REQUEST_DATA
                                         : (LPVOID)body.data(),
                            (DWORD)body.size(), (DWORD)body.size(), 0)) {
        r.error = lastError("WinHttpSendRequest");
        return r;
    }
    if (!WinHttpReceiveResponse(req.h, nullptr)) {
        r.error = lastError("WinHttpReceiveResponse");
        return r;
    }

    DWORD code = 0, len = sizeof(code);
    WinHttpQueryHeaders(req.h,
                        WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                        WINHTTP_HEADER_NAME_BY_INDEX, &code, &len,
                        WINHTTP_NO_HEADER_INDEX);
    r.status = (long)code;

    for (;;) {
        DWORD avail = 0;
        if (!WinHttpQueryDataAvailable(req.h, &avail)) {
            r.error = lastError("WinHttpQueryDataAvailable");
            return r;
        }
        if (avail == 0) break;
        std::vector<char> buf(avail);
        DWORD got = 0;
        if (!WinHttpReadData(req.h, buf.data(), avail, &got)) {
            r.error = lastError("WinHttpReadData");
            return r;
        }
        r.body.append(buf.data(), got);
    }
    return r;
}

#else  // non-Windows: the editor is Windows-only today, so fail loudly.

Response request(const char*, const std::string&, const std::string&, const Headers&,
                 int) {
    Response r;
    r.error = "HTTP is only implemented on Windows (WinHTTP)";
    return r;
}

#endif

}  // namespace

Response get(const std::string& url, const Headers& headers, int timeoutMs) {
    return request("GET", url, {}, headers, timeoutMs);
}

Response post(const std::string& url, const std::string& body, const Headers& headers,
              int timeoutMs) {
    return request("POST", url, body, headers, timeoutMs);
}

}  // namespace pb::net
