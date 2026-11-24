#include "ai/AiBackend.h"

#include "net/Http.h"
#include "net/Json.h"

namespace pb::ai {
namespace {

std::string join(const std::string& base, const char* leaf) {
    std::string b = base;
    while (!b.empty() && b.back() == '/') b.pop_back();
    return b + leaf;
}

// Pull a human-readable message out of an error body, whatever shape it is.
std::string apiError(long status, const std::string& body) {
    std::string msg;
    const json::Value v = json::parse(body);
    if (!v["error"]["message"].asString().empty())
        msg = v["error"]["message"].asString();
    else if (!v["error"].asString().empty())
        msg = v["error"].asString();
    else if (!v["message"].asString().empty())
        msg = v["message"].asString();
    if (msg.empty()) {
        msg = body.substr(0, 300);
        if (msg.empty()) msg = "no response body";
    }
    return "HTTP " + std::to_string(status) + ": " + msg;
}

}  // namespace

const std::vector<Preset>& presets() {
    static const std::vector<Preset> kPresets = {
        {"Ollama (local)", Style::OpenAICompat, "http://127.0.0.1:11434/v1", false},
        {"LM Studio (local)", Style::OpenAICompat, "http://127.0.0.1:1234/v1", false},
        {"llama.cpp server (local)", Style::OpenAICompat, "http://127.0.0.1:8080/v1",
         false},
        {"Anthropic", Style::Anthropic, "https://api.anthropic.com/v1", true},
        {"OpenAI", Style::OpenAICompat, "https://api.openai.com/v1", true},
        {"OpenRouter", Style::OpenAICompat, "https://openrouter.ai/api/v1", true},
        {"Custom (OpenAI-compatible)", Style::OpenAICompat, "", false},
    };
    return kPresets;
}

Result chat(const Config& cfg, const std::string& system, const std::string& user,
            bool jsonMode) {
    Result out;
    if (!cfg.configured()) {
        out.error = "No model configured — set one in Options > AI.";
        return out;
    }

    net::Headers headers = {{"Content-Type", "application/json"}};
    json::Value body = json::Value::object();
    body.set("model", json::Value::str(cfg.model));
    std::string url;

    if (cfg.style == Style::Anthropic) {
        url = join(cfg.baseUrl, "/messages");
        headers.push_back({"x-api-key", cfg.apiKey});
        headers.push_back({"anthropic-version", "2023-06-01"});
        body.set("max_tokens", json::Value::number(4096));
        if (!system.empty()) body.set("system", json::Value::str(system));
        json::Value m = json::Value::object();
        m.set("role", json::Value::str("user"));
        m.set("content", json::Value::str(user));
        json::Value msgs = json::Value::array();
        msgs.push(m);
        body.set("messages", msgs);
    } else {
        url = join(cfg.baseUrl, "/chat/completions");
        if (!cfg.apiKey.empty())
            headers.push_back({"Authorization", "Bearer " + cfg.apiKey});
        json::Value msgs = json::Value::array();
        if (!system.empty()) {
            json::Value s = json::Value::object();
            s.set("role", json::Value::str("system"));
            s.set("content", json::Value::str(system));
            msgs.push(s);
        }
        json::Value u = json::Value::object();
        u.set("role", json::Value::str("user"));
        u.set("content", json::Value::str(user));
        msgs.push(u);
        body.set("messages", msgs);
        body.set("stream", json::Value::boolean(false));
        if (jsonMode) {
            json::Value rf = json::Value::object();
            rf.set("type", json::Value::str("json_object"));
            body.set("response_format", rf);
        }
    }

    const net::Response r = net::post(url, body.dump(), headers, cfg.timeoutMs);
    if (!r.error.empty()) {
        out.error = r.error;
        return out;
    }
    if (r.status < 200 || r.status >= 300) {
        out.error = apiError(r.status, r.body);
        return out;
    }

    std::string perr;
    const json::Value v = json::parse(r.body, &perr);
    if (!perr.empty()) {
        out.error = "Could not read the reply: " + perr;
        return out;
    }
    out.text = cfg.style == Style::Anthropic
                   ? v["content"][0]["text"].asString()
                   : v["choices"][0]["message"]["content"].asString();
    if (out.text.empty()) {
        out.error = "The reply had no text content.";
        return out;
    }
    out.ok = true;
    return out;
}

std::vector<std::string> listModels(const Config& cfg, std::string* err) {
    std::vector<std::string> out;
    if (cfg.baseUrl.empty()) {
        if (err) *err = "No base URL set.";
        return out;
    }
    net::Headers headers;
    if (!cfg.apiKey.empty()) {
        if (cfg.style == Style::Anthropic) {
            headers.push_back({"x-api-key", cfg.apiKey});
            headers.push_back({"anthropic-version", "2023-06-01"});
        } else {
            headers.push_back({"Authorization", "Bearer " + cfg.apiKey});
        }
    }
    const net::Response r = net::get(join(cfg.baseUrl, "/models"), headers, 8000);
    if (!r.error.empty()) {
        if (err) *err = r.error;
        return out;
    }
    if (r.status < 200 || r.status >= 300) {
        if (err) *err = apiError(r.status, r.body);
        return out;
    }
    const json::Value v = json::parse(r.body);
    // OpenAI-compatible and Anthropic both answer { "data": [ { "id": ... } ] }.
    for (const auto& e : v["data"].elements()) {
        const std::string id = e["id"].asString();
        if (!id.empty()) out.push_back(id);
    }
    // Ollama's native shape, in case someone points at /api instead of /v1.
    for (const auto& e : v["models"].elements()) {
        const std::string id = e["name"].asString();
        if (!id.empty()) out.push_back(id);
    }
    if (out.empty() && err) *err = "The endpoint listed no models.";
    return out;
}

std::vector<Local> detectLocal(int timeoutMs) {
    std::vector<Local> found;
    struct Candidate { const char* name; const char* baseUrl; };
    static const Candidate kCandidates[] = {
        {"Ollama", "http://127.0.0.1:11434/v1"},
        {"LM Studio", "http://127.0.0.1:1234/v1"},
        {"llama.cpp", "http://127.0.0.1:8080/v1"},
    };
    for (const auto& c : kCandidates) {
        Config probe;
        probe.style = Style::OpenAICompat;
        probe.baseUrl = c.baseUrl;
        probe.timeoutMs = timeoutMs;
        const net::Response r =
            net::get(join(probe.baseUrl, "/models"), {}, timeoutMs);
        if (!r.ok()) continue;
        Local l;
        l.name = c.name;
        l.baseUrl = c.baseUrl;
        const json::Value v = json::parse(r.body);
        for (const auto& e : v["data"].elements()) {
            const std::string id = e["id"].asString();
            if (!id.empty()) l.models.push_back(id);
        }
        found.push_back(std::move(l));
    }
    return found;
}

}  // namespace pb::ai
