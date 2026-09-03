#pragma once
#include <string>
#include <utility>
#include <vector>

namespace pb::net {

struct Response {
    long status = 0;        // HTTP status, 0 when the request never completed
    std::string body;
    std::string error;      // non-empty on a transport failure
    bool ok() const { return error.empty() && status >= 200 && status < 300; }
};

using Headers = std::vector<std::pair<std::string, std::string>>;

// Blocking HTTP over WinHTTP. `url` is a full http(s):// URL. Call these off
// the UI thread — a model call can take many seconds.
Response get(const std::string& url, const Headers& headers = {},
             int timeoutMs = 15000);
Response post(const std::string& url, const std::string& body,
              const Headers& headers = {}, int timeoutMs = 120000);

}  // namespace pb::net
