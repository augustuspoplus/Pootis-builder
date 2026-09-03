#include "ai/MaterialSuggest.h"

#include <algorithm>
#include <cctype>
#include <cmath>

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
                              const std::vector<std::string>& skies,
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

    std::string skyList;
    for (const auto& sk : skies) {
        skyList += "  ";
        skyList += sk;
        skyList += '\n';
    }

    const std::string system =
        "You art-direct Team Fortress 2 maps. Given lists of materials and "
        "skyboxes that exist in the game, choose a set that reads well together "
        "at TF2's cartoon-realist scale, plus fog and sunlight that match.\n"
        "Reply with ONLY a JSON object, no prose, no code fence:\n"
        "{\"floor\":\"...\",\"wall\":\"...\",\"ceiling\":\"...\","
        "\"trim\":\"...\",\"accent\":\"...\",\"skyname\":\"...\","
        "\"fog\":[r,g,b],\"fog_start\":512,\"fog_end\":4096,"
        "\"sun\":[r,g,b],\"sun_pitch\":-45,\"sun_yaw\":210,"
        "\"note\":\"short reason\"}\n"
        "Material and skyname values MUST be copied exactly from the lists. Use "
        "an empty string for any slot nothing suits. Colours are 0-255. "
        "sun_pitch is negative for a sun above the horizon (-90 is straight "
        "down). Fog should sit inside the map's scale: start 256-1024, end "
        "2048-8192.";

    const std::string user = "Mood: " + mood +
                             "\n\nAvailable materials:\n" + list +
                             "\nAvailable skyboxes:\n" + skyList;

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

    // Sky must be one the game actually ships, or the map won't light right.
    {
        const std::string lw = lower(v["skyname"].asString());
        for (const auto& sk : skies)
            if (lower(sk) == lw) { pick.skyname = sk; break; }
    }
    auto chan = [](const json::Value& a, size_t i) {
        const double d = a[i].asNumber(-1.0);
        if (d < 0.0) return -1;
        return static_cast<int>(std::max(0.0, std::min(255.0, d)));
    };
    if (v["fog"].size() >= 3) {
        pick.fogR = chan(v["fog"], 0);
        pick.fogG = chan(v["fog"], 1);
        pick.fogB = chan(v["fog"], 2);
    }
    if (v["sun"].size() >= 3) {
        pick.sunR = chan(v["sun"], 0);
        pick.sunG = chan(v["sun"], 1);
        pick.sunB = chan(v["sun"], 2);
    }
    const double fs = v["fog_start"].asNumber(-1.0);
    const double fe = v["fog_end"].asNumber(-1.0);
    if (fs >= 0.0 && fe > fs) {
        pick.fogStart = static_cast<float>(std::min(fs, 8192.0));
        pick.fogEnd = static_cast<float>(std::min(fe, 32768.0));
    }
    if (v.has("sun_pitch")) {
        const double p = v["sun_pitch"].asNumber(1e9);
        if (p < 1e8)
            pick.sunPitch = static_cast<float>(std::max(-90.0, std::min(90.0, p)));
    }
    if (v.has("sun_yaw")) {
        const double y = v["sun_yaw"].asNumber(1e9);
        if (y < 1e8)
            pick.sunYaw =
                static_cast<float>(std::fmod(std::fmod(y, 360.0) + 360.0, 360.0));
    }


    if (!pick.any() && err)
        *err = "The model picked nothing that exists in the game's content.";
    return pick;
}

}  // namespace pb::ai
