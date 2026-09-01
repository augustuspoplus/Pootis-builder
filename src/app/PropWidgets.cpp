#include "app/PropWidgets.h"

#include <algorithm>
#include <array>
#include <cstdio>
#include <cstdlib>
#include <cstring>

#include <imgui.h>

#include "app/Ui.h"

namespace pb::ui {
namespace {

// The label line above each field: "Display Name  key  (?)".
void fieldLabel(const fgd::Var& v) {
    ImGui::TextUnformatted(v.displayName.empty() ? v.key.c_str()
                                                : v.displayName.c_str());
    ImGui::SameLine(0, 6);
    ImGui::PushStyleColor(ImGuiCol_Text, col::faint);
    ImGui::Text("%s", v.key.c_str());
    if (!v.displayName.empty()) {
        ImGui::SameLine(0, 6);
        ImGui::TextUnformatted("(?)");
    }
    ImGui::PopStyleColor();
    if (ImGui::IsItemHovered() && !v.help.empty()) {
        ImGui::BeginTooltip();
        ImGui::PushTextWrapPos(360.0f);
        ImGui::TextUnformatted(v.help.c_str());
        ImGui::PopTextWrapPos();
        ImGui::EndTooltip();
    }
}

const char* label(const fgd::Var&) { return "##v"; }

std::array<float, 4> parseFloats(const std::string& s, int n) {
    std::array<float, 4> f{0, 0, 0, 0};
    std::sscanf(s.c_str(), "%f %f %f %f", &f[0], &f[1], &f[2], &f[3]);
    (void)n;
    return f;
}

bool comboText(const char* id, std::string& value,
               const std::vector<std::string>& opts) {
    bool changed = false;
    char buf[192];
    std::snprintf(buf, sizeof(buf), "%s", value.c_str());
    ImGui::SetNextItemWidth(-28.0f);
    if (ImGui::InputText(id, buf, sizeof(buf))) { value = buf; changed = true; }
    ImGui::SameLine(0, 4);
    ImGui::PushID(id);
    if (ImGui::BeginCombo("##pick", "", ImGuiComboFlags_NoPreview |
                                            ImGuiComboFlags_PopupAlignLeft)) {
        for (const auto& o : opts)
            if (!o.empty() && ImGui::Selectable(o.c_str(), o == value)) {
                value = o;
                changed = true;
            }
        ImGui::EndCombo();
    }
    ImGui::PopID();
    return changed;
}

}  // namespace

bool fgdFlags(const fgd::Var& sf, map::KvNode& kv, bool* committed) {
    if (sf.flags.empty()) return false;
    int mask = kv.getInt("spawnflags", 0);
    bool changed = false;
    ImGui::PushID("spawnflags");
    for (const auto& fb : sf.flags) {
        bool on = (mask & fb.bit) != 0;
        if (ImGui::CheckboxFlags(fb.label.c_str(), &mask, fb.bit)) {
            changed = true;
            if (committed) *committed = true;
        }
        (void)on;
    }
    ImGui::PopID();
    if (changed) kv.set("spawnflags", std::to_string(mask));
    return changed;
}

bool fgdField(const fgd::Var& var, map::KvNode& kv,
              const std::vector<std::string>& entityNames, bool* committed) {
    using fgd::VarType;
    const std::string cur = kv.get(var.key, var.defaultValue);
    bool changed = false;
    auto commit = [&] { if (committed && ImGui::IsItemDeactivatedAfterEdit()) *committed = true; };

    ImGui::PushID(var.key.c_str());
    if (var.type != VarType::Bool) fieldLabel(var);

    switch (var.type) {
        case VarType::Integer: {
            int v = std::atoi(cur.c_str());
            ImGui::SetNextItemWidth(-1);
            if (ImGui::InputInt(label(var), &v, 1, 10)) {
                kv.set(var.key, std::to_string(v));
                changed = true;
            }
            commit();
            break;
        }
        case VarType::Float: {
            float v = static_cast<float>(std::atof(cur.c_str()));
            ImGui::SetNextItemWidth(-1);
            if (ImGui::InputFloat(label(var), &v, 0.0f, 0.0f, "%.3f")) {
                char b[48];
                std::snprintf(b, sizeof(b), "%g", v);
                kv.set(var.key, b);
                changed = true;
            }
            commit();
            break;
        }
        case VarType::Bool: {
            bool v = cur == "1" || cur == "true" || cur == "Yes";
            const char* bl =
                var.displayName.empty() ? var.key.c_str() : var.displayName.c_str();
            if (ImGui::Checkbox(bl, &v)) {
                kv.set(var.key, v ? "1" : "0");
                changed = true;
                if (committed) *committed = true;
            }
            break;
        }
        case VarType::Choices: {
            int sel = -1;
            for (int i = 0; i < (int)var.choices.size(); ++i)
                if (var.choices[i].value == cur) sel = i;
            std::string preview =
                sel >= 0 ? var.choices[sel].label : (cur.empty() ? "(unset)" : cur);
            ImGui::SetNextItemWidth(-1);
            if (ImGui::BeginCombo(label(var), preview.c_str())) {
                for (int i = 0; i < (int)var.choices.size(); ++i) {
                    const auto& c = var.choices[i];
                    char row[192];
                    std::snprintf(row, sizeof(row), "%s   (%s)", c.label.c_str(),
                                  c.value.c_str());
                    if (ImGui::Selectable(row, i == sel)) {
                        kv.set(var.key, c.value);
                        changed = true;
                        if (committed) *committed = true;
                    }
                }
                ImGui::EndCombo();
            }
            break;
        }
        case VarType::Color255:
        case VarType::Color1: {
            auto f = parseFloats(cur, 4);
            const float sc = var.type == VarType::Color255 ? 1.0f / 255.0f : 1.0f;
            float col[3] = {f[0] * sc, f[1] * sc, f[2] * sc};
            const bool hasBright =
                var.type == VarType::Color255 && std::strchr(cur.c_str(), ' ') &&
                std::count(cur.begin(), cur.end(), ' ') >= 3;
            ImGui::SetNextItemWidth(-1);
            if (ImGui::ColorEdit3(label(var), col,
                                  ImGuiColorEditFlags_NoInputs |
                                      ImGuiColorEditFlags_NoLabel)) {
                char b[64];
                if (var.type == VarType::Color255) {
                    if (hasBright)
                        std::snprintf(b, sizeof(b), "%d %d %d %d", int(col[0] * 255),
                                      int(col[1] * 255), int(col[2] * 255), int(f[3]));
                    else
                        std::snprintf(b, sizeof(b), "%d %d %d", int(col[0] * 255),
                                      int(col[1] * 255), int(col[2] * 255));
                } else {
                    std::snprintf(b, sizeof(b), "%.3f %.3f %.3f", col[0], col[1], col[2]);
                }
                kv.set(var.key, b);
                changed = true;
                if (committed) *committed = true;
            }
            if (hasBright) {
                ImGui::SameLine(0, 8);
                int bright = int(f[3]);
                ImGui::SetNextItemWidth(-1);
                if (ImGui::DragInt("##bright", &bright, 1, 0, 100000, "bright %d")) {
                    char b[64];
                    std::snprintf(b, sizeof(b), "%d %d %d %d", int(col[0] * 255),
                                  int(col[1] * 255), int(col[2] * 255), bright);
                    kv.set(var.key, b);
                    changed = true;
                }
                commit();
            }
            break;
        }
        case VarType::Angle:
        case VarType::Vector:
        case VarType::Origin:
        case VarType::Axis: {
            auto f = parseFloats(cur, 3);
            float v[3] = {f[0], f[1], f[2]};
            ImGui::SetNextItemWidth(-1);
            if (ImGui::InputFloat3(label(var), v, "%.1f")) {
                char b[96];
                std::snprintf(b, sizeof(b), "%g %g %g", v[0], v[1], v[2]);
                kv.set(var.key, b);
                changed = true;
            }
            commit();
            break;
        }
        case VarType::TargetSource:
        case VarType::TargetDest:
        case VarType::NodeDest:
        case VarType::FilterClass: {
            std::string v = cur;
            if (comboText("##t", v, entityNames)) {
                kv.set(var.key, v);
                changed = true;
            }
            commit();
            break;
        }
        default: {  // String, Studio, Sprite, Material, Sound, Scene, Particle, ...
            char b[320];
            std::snprintf(b, sizeof(b), "%s", cur.c_str());
            ImGui::SetNextItemWidth(-1);
            if (ImGui::InputText(label(var), b, sizeof(b))) {
                kv.set(var.key, b);
                changed = true;
            }
            commit();
            break;
        }
    }
    ImGui::Dummy(ImVec2(0, 2));
    ImGui::PopID();
    if (changed && kv.find(var.key) == nullptr) kv.set(var.key, cur);
    return changed;
}

}  // namespace pb::ui
