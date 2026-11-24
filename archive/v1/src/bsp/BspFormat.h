#pragma once
#include <cstdint>

// Source Engine BSP on-disk structures (VBSP, versions 19-21; TF2 stock maps
// are version 20). Layout per the Valve Developer Community documentation.
namespace pb::bsp {

constexpr int kBspIdent = ('P' << 24) | ('S' << 16) | ('B' << 8) | 'V';  // "VBSP"
constexpr int kNumLumps = 64;
constexpr int kMaxLightmapStyles = 4;

enum Lump {
    LUMP_ENTITIES = 0,
    LUMP_PLANES = 1,
    LUMP_TEXDATA = 2,
    LUMP_VERTEXES = 3,
    LUMP_VISIBILITY = 4,
    LUMP_NODES = 5,
    LUMP_TEXINFO = 6,
    LUMP_FACES = 7,
    LUMP_LIGHTING = 8,
    LUMP_LEAFS = 10,
    LUMP_EDGES = 12,
    LUMP_SURFEDGES = 13,
    LUMP_MODELS = 14,
    LUMP_BRUSHES = 19,
    LUMP_BRUSHSIDES = 20,
    LUMP_DISPINFO = 26,
    LUMP_ORIGINALFACES = 27,
    LUMP_DISP_VERTS = 33,
    LUMP_GAME_LUMP = 35,
    LUMP_PAKFILE = 40,
    LUMP_TEXDATA_STRING_DATA = 43,
    LUMP_TEXDATA_STRING_TABLE = 44,
    LUMP_LIGHTING_HDR = 53,
    LUMP_FACES_HDR = 58,
};

// Surface flags carried on texinfo_t::flags.
enum SurfFlag : uint32_t {
    SURF_LIGHT = 0x0001,
    SURF_SKY2D = 0x0002,
    SURF_SKY = 0x0004,
    SURF_WARP = 0x0008,
    SURF_TRANS = 0x0010,
    SURF_NOPORTAL = 0x0020,
    SURF_TRIGGER = 0x0040,
    SURF_NODRAW = 0x0080,
    SURF_HINT = 0x0100,
    SURF_SKIP = 0x0200,
    SURF_NOLIGHT = 0x0400,
    SURF_BUMPLIGHT = 0x0800,
    SURF_NODECALS = 0x1000,
    SURF_NOCHOP = 0x2000,
    SURF_HITBOX = 0x4000,
};

#pragma pack(push, 1)

struct Lump_t {
    int32_t fileofs;
    int32_t filelen;
    int32_t version;
    char fourCC[4];  // non-zero -> LZMA compressed lump
};

struct Header_t {
    int32_t ident;
    int32_t version;
    Lump_t lumps[kNumLumps];
    int32_t mapRevision;
};

struct Vector_t {
    float x, y, z;
};

struct Edge_t {
    uint16_t v[2];
};

struct Plane_t {
    Vector_t normal;
    float dist;
    int32_t type;
};

struct Face_t {
    uint16_t planenum;
    uint8_t side;
    uint8_t onNode;
    int32_t firstedge;
    int16_t numedges;
    int16_t texinfo;
    int16_t dispinfo;
    int16_t surfaceFogVolumeID;
    uint8_t styles[kMaxLightmapStyles];
    int32_t lightofs;
    float area;
    int32_t lightmapMins[2];
    int32_t lightmapSize[2];
    int32_t origFace;
    uint16_t numPrims;
    uint16_t firstPrimID;
    uint32_t smoothingGroups;
};

struct TexInfo_t {
    float textureVecs[2][4];
    float lightmapVecs[2][4];
    int32_t flags;
    int32_t texdata;
};

struct TexData_t {
    Vector_t reflectivity;
    int32_t nameStringTableID;
    int32_t width, height;
    int32_t view_width, view_height;
};

struct Model_t {
    Vector_t mins, maxs;
    Vector_t origin;
    int32_t headnode;
    int32_t firstface, numfaces;
};

struct ColorRGBExp32 {
    uint8_t r, g, b;
    int8_t exponent;
};

struct GameLumpHeader_t {
    int32_t id;
    uint16_t flags;
    uint16_t version;
    int32_t fileofs;
    int32_t filelen;
};

// LUMP_DISP_VERTS entry (dDispVert). 20 bytes.
struct DispVert_t {
    Vector_t vec;   // unit direction of displacement
    float dist;     // distance along `vec`
    float alpha;    // per-vertex blend alpha
};

// LUMP_DISPINFO entry (ddispinfo_t) is 176 bytes with neighbour data we don't
// need; only the leading fields are declared and the rest is skipped by stride.
struct DispInfoHead_t {
    Vector_t startPosition;   // 0  : orients the grid against the base quad
    int32_t dispVertStart;    // 12 : first index into LUMP_DISP_VERTS
    int32_t dispTriStart;     // 16
    int32_t power;            // 20 : grid is (2^power + 1) per side
};
constexpr int kDispInfoSize = 176;

#pragma pack(pop)

}  // namespace pb::bsp
