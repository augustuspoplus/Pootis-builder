#pragma once
#include <string>
#include <vector>

namespace pb::ai {

// Two request shapes cover everything worth talking to. OpenAICompat is spoken
// by Ollama, LM Studio, llama.cpp's server, vLLM, LocalAI, OpenRouter and
// OpenAI itself; Anthropic needs its own body and headers.
enum class Style { OpenAICompat = 0, Anthropic = 1 };

struct Config {
    Style style = Style::OpenAICompat;
    std::string baseUrl;   // includes the version segment, e.g. ".../v1"
    std::string model;
    std::string apiKey;    // empty for a local server
    int timeoutMs = 120000;

    bool configured() const { return !baseUrl.empty() && !model.empty(); }
};

struct Result {
    bool ok = false;
    std::string text;   // the assistant's reply
    std::string error;  // transport / API / parse failure, ready to show
};

// One turn. `jsonMode` asks the provider to constrain output to a JSON object
// where it supports that (harmless when it doesn't). Blocking — call it off the
// UI thread.
Result chat(const Config& cfg, const std::string& system, const std::string& user,
            bool jsonMode = false);

// Model ids the endpoint reports, for the Options dropdown. Empty on failure.
std::vector<std::string> listModels(const Config& cfg, std::string* err = nullptr);

// A local server we found listening.
struct Local {
    std::string name;     // "Ollama" / "LM Studio"
    std::string baseUrl;  // ready to drop into Config::baseUrl
    std::vector<std::string> models;
};

// Probes the usual local ports. Cheap and safe to call when Options opens.
std::vector<Local> detectLocal(int timeoutMs = 1200);

// Presets shown in the Options provider dropdown.
struct Preset {
    const char* name;
    Style style;
    const char* baseUrl;
    bool needsKey;
};
const std::vector<Preset>& presets();

}  // namespace pb::ai
