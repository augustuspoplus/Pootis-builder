#include "ai/MaterialSuggest.h"

#include <algorithm>
#include <cctype>

#include "net/Json.h"

namespace pb::ai {
namespace {

std::string lower(std::string s) {
    for (char& c : s) c = static_cast<char>(std::tolower((unsigned char)c));
    return s;
}

std::vector<std::string> words(const std::string& s) {
    std::vector<std::string> out;
    std::string cur;
    for (char c : lower(s)) {
        if (std::isalnum((unsigned char)c)) {
            cur += c;
        } else if (!cur.empty()) {
            out.push_back(cur);
            cur.clear();
        }
    }
    if (!cur.empty()) out.push_back(cur);
    // Drop filler that would match everything.
    static const char* kStop[] = {"a", "an", "the", "and", "with", "of", "for",
                                  "some", "make", "it", "look", "like", "very"};
    out.erase(std::remove_if(out.begin(), out.end(),
                             [](const std::string& w) {
                                 if (w.size() < 3) return true;
                                 for (const char* s : kStop)
                                     if (w == s) return true;
                                 return false;
                             }),
              out.end());
    return out;
}

// Materials that are never useful on brushwork.
bool junk(const std::string& m) {
    static const char* kBad[] = {"vgui/",   "hud/",     "backpack/", "console/",
                                 "effects/", "particle", "models/",   "signs/",
                                 "overlays/", "decals/",  "sprites/",  "editor/"};
    for (const char* b : kBad)
        if (m.rfind(b, 0) == 0 || m.find(b) != std::string::npos) return true;
    return false;
}

}  // namespace

std::vector<std::string> buildPool(const std::vector<std::string>& all,
                                   const std::string& mood, size_t maxN) {
    const std::vector<std::string> keys = words(mood);

    std::vector<std::pair<int, const std::string*>> scored;
    scored.reserve(all.size() / 4);
    for (const auto& m : all) {
        if (junk(m)) continue;
        const std::string lm = lower(m);
        int score = 0;
        for (const auto& k : keys)
            if (lm.find(k) != std::string::npos) score += 10;
        // Shallow, plainly-named materials beat deep variant paths.
        score -= static_cast<int>(std::count(lm.begin(), lm.end(), '/'));
        if (score > 0) scored.emplace_back(score, &m);
    }
    std::stable_sort(scored.begin(), scored.end(),
                     [](const auto& a, const auto& b) { return a.first > b.first; });

    std::vector<std::string> pool;
    for (const auto& [sc, m] : scored) {
        if (pool.size() >= maxN * 3 / 4) break;
        pool.push_back(*m);
    }

    // Always give the model a spread of ordinary construction materials, so a
    // mood with no keyword hits still has something buildable to choose from.
    static const char* kStaples[] = {"concrete/", "brick/",  "metal/",
                                     "wood/",     "plaster/", "tile/",
                                     "nature/",   "glass/"};
    for (const char* fam : kStaples) {
        size_t added = 0;
        for (const auto& m : all) {
            if (pool.size() >= maxN || added >= 6) break;
            if (junk(m)) continue;
            const std::string lm = lower(m);
            if (lm.rfind(fam, 0) != 0) continue;
            if (std::find(pool.begin(), pool.end(), m) != pool.end()) continue;
            pool.push_back(m);
            ++added;
        }
    }
    if (pool.size() > maxN) pool.resize(maxN);
    return pool;
}

MaterialPick suggestMaterials(const Config& cfg, const std::string& mood,
                              const std::vector<std::string>& pool,
                              std::string* err) {
    MaterialPick pick;
    if (pool.empty()) {
        if (err) *err = "No candidate materials to choose from.";
        return pick;
    }

    std::string list;
    for (const auto& m : pool) {
        list += m;
        list += '\n';
    }

    const std::string system =
        "You dress Team Fortress 2 map geometry. You are given a list of "
        "material names that exist in the game. Choose materials that read well "
        "together at TF2's cartoon-realist scale.\n"
        "Reply with ONLY a JSON object, no prose, no code fence:\n"
        "{\"floor\":\"...\",\"wall\":\"...\",\"ceiling\":\"...\","
        "\"trim\":\"...\",\"accent\":\"...\",\"note\":\"short reason\"}\n"
        "Every material value MUST be copied exactly from the list. If nothing "
        "in the list suits a slot, use an empty string for it.";

    const std::string user = "Mood: " + mood +
                             "\n\nAvailable materials:\n" + list;

    const Result r = chat(cfg, system, user, /*jsonMode=*/true);
    if (!r.ok) {
        if (err) *err = r.error;
        return pick;
    }

    // Models sometimes wrap JSON in a fence or add a sentence; take the object.
    std::string body = r.text;
    const size_t open = body.find('{');
    const size_t close = body.rfind('}');
    if (open == std::string::npos || close == std::string::npos || close < open) {
        if (err) *err = "The model did not return a JSON object.";
        return pick;
    }
    body = body.substr(open, close - open + 1);

    std::string perr;
    const json::Value v = json::parse(body, &perr);
    if (!perr.empty()) {
        if (err) *err = "Could not read the reply: " + perr;
        return pick;
    }

    // Only accept names that really exist — a hallucinated path would just
    // render as a missing-texture checker in game.
    auto take = [&](const char* key) -> std::string {
        const std::string want = v[key].asString();
        if (want.empty()) return {};
        for (const auto& m : pool)
            if (m == want) return m;
        const std::string lw = lower(want);
        for (const auto& m : pool)
            if (lower(m) == lw) return m;
        return {};
    };
    pick.floor = take("floor");
    pick.wall = take("wall");
    pick.ceiling = take("ceiling");
    pick.trim = take("trim");
    pick.accent = take("accent");
    pick.note = v["note"].asString();

    if (!pick.any() && err)
        *err = "The model picked nothing that exists in the game's materials.";
    return pick;
}

}  // namespace pb::ai
