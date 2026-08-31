#pragma once
#include <string>

#include <glm/glm.hpp>

#include "gpu/Gl.h"

namespace pb {

class Shader {
public:
    Shader() = default;
    ~Shader();
    Shader(const Shader&) = delete;
    Shader& operator=(const Shader&) = delete;

    // Compiles from source strings. Returns false and logs on error.
    bool compile(const char* vertSrc, const char* fragSrc, const char* name = "shader");
    bool compileFromFiles(const std::string& vertPath, const std::string& fragPath);

    void use() const { glUseProgram(program_); }
    GLuint id() const { return program_; }
    bool valid() const { return program_ != 0; }

    void set(const char* n, int v) const { glUniform1i(loc(n), v); }
    void set(const char* n, float v) const { glUniform1f(loc(n), v); }
    void set(const char* n, const glm::vec2& v) const { glUniform2fv(loc(n), 1, &v.x); }
    void set(const char* n, const glm::vec3& v) const { glUniform3fv(loc(n), 1, &v.x); }
    void set(const char* n, const glm::vec4& v) const { glUniform4fv(loc(n), 1, &v.x); }
    void set(const char* n, const glm::mat4& m) const {
        glUniformMatrix4fv(loc(n), 1, GL_FALSE, &m[0][0]);
    }

private:
    GLint loc(const char* n) const { return glGetUniformLocation(program_, n); }
    GLuint program_ = 0;
};

}  // namespace pb
