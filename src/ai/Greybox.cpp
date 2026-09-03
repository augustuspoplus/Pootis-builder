#include "ai/Greybox.h"

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

float clampCoord(double v, int grid) {
    if (!std::isfinite(v)) return 0.0f;
    double c = std::max(-static_cast<double>(kMaxCoord),
                        std::min(static_cast<double>(kMaxCoord), v));
    if (grid > 0) c = std::round(c / grid) * grid;
    return static_cast<float>(c);
}

}  // namespace

Plan validatePlan(const std::string& reply, const std::vector<std::string>& kit,
                  int gridSize) {
    Plan plan;

    // Models like to wrap JSON in prose or a code fence; take the outer object.
    const size_t open = reply.find('{');
    const size_t close = reply.rfind('}');
    if (open == std::string::npos || close == std::string::npos || close < open) {
        plan.rejected.push_back("reply was not JSON");
        return plan;
    }
    std::string err;
    const json::Value v =
        json::parse(reply.substr(open, close - open + 1), &err);
    if (!err.empty()) {
        plan.rejected.push_back("unreadable JSON: " + err);
        return plan;
    }

    plan.note = v["note"].asString();
    for (const auto& e : v["pieces"].elements()) {
        if (plan.items.size() >= kMaxPieces) {
            plan.rejected.push_back("plan was longer than " +
                                    std::to_string(kMaxPieces) + " pieces");
            break;
        }
        const std::string want = e["piece"].asString();
        if (want.empty()) continue;

        // The name must be a real kit piece — anything invented is dropped
        // rather than silently doing nothing at placePiece().
        const std::string lw = lower(want);
        const std::string* match = nullptr;
        for (const auto& k : kit)
            if (lower(k) == lw) { match = &k; break; }
        if (!match) {
            plan.rejected.push_back(want);
            continue;
        }

        PlanItem it;
        it.piece = *match;
        it.pos = {clampCoord(e["x"].asNumber(), gridSize),
                  clampCoord(e["y"].asNumber(), gridSize),
                  clampCoord(e["z"].asNumber(), gridSize)};
        it.size = static_cast<float>(
            std::max(0.0, std::min(4096.0, e["size"].asNumber())));
        it.height = static_cast<float>(
            std::max(0.0, std::min(4096.0, e["height"].asNumber())));
        it.steps = static_cast<int>(
            std::max(0.0, std::min(40.0, e["steps"].asNumber())));
        plan.items.push_back(std::move(it));
    }
    return plan;
}

Plan requestGreybox(const Config& cfg, const std::string& brief,
                    const std::vector<std::string>& kit, int gridSize,
                    std::string* err) {
    Plan plan;
    if (kit.empty()) {
        if (err) *err = "No kit pieces available.";
        return plan;
    }

    std::string list;
    for (const auto& k : kit) {
        list += "  ";
        list += k;
        list += '\n';
    }

    const std::string system =
        "You lay out greybox geometry for Team Fortress 2 maps, using only a "
        "fixed kit of pieces.\n"
        "Scale: 1 unit = ~1 inch. A player is 64 tall and 32 wide. Corridors "
        "read well at 192-256 wide and 192 tall; a fight room wants 768-1536 "
        "across. Keep everything within +-8000 of the origin.\n"
        "Z is up. Place floors at the height you want people to stand on.\n"
        "Reply with ONLY a JSON object, no prose and no code fence:\n"
        "{\"pieces\":[{\"piece\":\"Room\",\"x\":0,\"y\":0,\"z\":0,\"size\":512}],"
        "\"note\":\"one short line\"}\n"
        "\"piece\" MUST be copied exactly from the kit list. Optional numbers: "
        "size, height, steps. Use at most 40 pieces. Space things apart so they "
        "do not overlap unless you mean them to connect.";

    const std::string user =
        "Brief: " + brief + "\n\nKit pieces you may use:\n" + list;

    const Result r = chat(cfg, system, user, /*jsonMode=*/true);
    if (!r.ok) {
        if (err) *err = r.error;
        return plan;
    }
    plan = validatePlan(r.text, kit, gridSize);
    if (plan.items.empty() && err)
        *err = plan.rejected.empty()
                   ? "The model returned no usable pieces."
                   : ("Nothing usable — first rejection: " + plan.rejected.front());
    return plan;
}

}  // namespace pb::ai
