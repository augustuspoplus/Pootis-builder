#include "render/Shader.h"

#include <vector>

#include "core/File.h"
#include "core/Log.h"

namespace pb {

namespace {
GLuint compileStage(GLenum type, const char* src, const char* name) {
    GLuint s = glCreateShader(type);
    glShaderSource(s, 1, &src, nullptr);
    glCompileShader(s);
    GLint ok = 0;
    glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        GLint len = 0;
        glGetShaderiv(s, GL_INFO_LOG_LENGTH, &len);
        std::vector<char> log(len > 1 ? len : 1);
        glGetShaderInfoLog(s, len, nullptr, log.data());
        PB_ERROR("shader compile (%s / %s): %s", name,
                 type == GL_VERTEX_SHADER ? "vert" : "frag", log.data());
        glDeleteShader(s);
        return 0;
    }
    return s;
}
}  // namespace

Shader::~Shader() {
    if (program_) glDeleteProgram(program_);
}

bool Shader::compile(const char* vertSrc, const char* fragSrc, const char* name) {
    GLuint vs = compileStage(GL_VERTEX_SHADER, vertSrc, name);
    GLuint fs = compileStage(GL_FRAGMENT_SHADER, fragSrc, name);
    if (!vs || !fs) {
        if (vs) glDeleteShader(vs);
        if (fs) glDeleteShader(fs);
        return false;
    }
    GLuint p = glCreateProgram();
    glAttachShader(p, vs);
    glAttachShader(p, fs);
    glLinkProgram(p);
    glDeleteShader(vs);
    glDeleteShader(fs);
    GLint ok = 0;
    glGetProgramiv(p, GL_LINK_STATUS, &ok);
    if (!ok) {
        GLint len = 0;
        glGetProgramiv(p, GL_INFO_LOG_LENGTH, &len);
        std::vector<char> log(len > 1 ? len : 1);
        glGetProgramInfoLog(p, len, nullptr, log.data());
        PB_ERROR("shader link (%s): %s", name, log.data());
        glDeleteProgram(p);
        return false;
    }
    if (program_) glDeleteProgram(program_);
    program_ = p;
    return true;
}

bool Shader::compileFromFiles(const std::string& vertPath, const std::string& fragPath) {
    const std::string v = readTextFile(vertPath);
    const std::string f = readTextFile(fragPath);
    if (v.empty() || f.empty()) {
        PB_ERROR("shader: cannot read %s / %s", vertPath.c_str(), fragPath.c_str());
        return false;
    }
    return compile(v.c_str(), f.c_str(), vertPath.c_str());
}

}  // namespace pb
