#ifndef SHADER_PATH_H
#define SHADER_PATH_H

// Runtime resolution of the src/shaders directory.
//
// The original CMake build passed an absolute path via -DSHADERS_DIR=...
// (see src/CMakeLists.txt). Under mcpp the binary lives in
// target/<triple>/<fingerprint>/ and no such absolute path exists at manifest
// time, so the shaders directory is found at runtime instead: relative to the
// executable, walking up towards the project root, then relative to the CWD.
// A SHADERS_DIR define (if the CMake build still provides one) wins.

#include <string>
#include <cstdio>
#include <cstdlib>
#include <sys/stat.h>
#if defined(__APPLE__)
#include <mach-o/dyld.h>
#elif defined(__linux__)
#include <unistd.h>
#elif defined(_WIN32)
#include <windows.h>
#endif

inline bool shader_dir_exists(const std::string& p) {
    struct stat s;
    return !p.empty() && stat(p.c_str(), &s) == 0 && (s.st_mode & S_IFDIR);
}

inline std::string shader_executable_dir() {
#if defined(__APPLE__)
    uint32_t size = 0;
    _NSGetExecutablePath(nullptr, &size);
    std::string buf(size, '\0');
    if (_NSGetExecutablePath(buf.data(), &size) != 0) return ".";
    std::string path(buf.data()); // stop at the first NUL: size may over-report
    auto pos = path.find_last_of('/');
    return pos == std::string::npos ? "." : path.substr(0, pos);
#elif defined(__linux__)
    char buf[4096];
    ssize_t n = readlink("/proc/self/exe", buf, sizeof(buf) - 1);
    if (n <= 0) return ".";
    buf[n] = '\0';
    std::string path(buf);
    auto pos = path.find_last_of('/');
    return pos == std::string::npos ? "." : path.substr(0, pos);
#elif defined(_WIN32)
    char buf[MAX_PATH];
    DWORD n = GetModuleFileNameA(nullptr, buf, MAX_PATH);
    if (n == 0 || n >= MAX_PATH) return ".";
    std::string path(buf, n);
    auto pos = path.find_last_of("/\\");
    return pos == std::string::npos ? "." : path.substr(0, pos);
#else
    return ".";
#endif
}

inline std::string find_shader_dir() {
#ifdef SHADERS_DIR
    return SHADERS_DIR;
#else
    // target/<triple>/<fingerprint>/exe  ->  3 levels up reaches the project
    // root; allow a few more for deeper layouts.
    std::string dir = shader_executable_dir();
    const bool debug = std::getenv("BH_SHADER_DEBUG") != nullptr;
    if (debug) std::fprintf(stderr, "SHADER: exe_dir=[%s]\n", dir.c_str());
    for (int i = 0; i < 6; ++i) {
        std::string cand = dir + "/src/shaders";
        if (shader_dir_exists(cand)) {
            if (debug) std::fprintf(stderr, "SHADER: found [%s]\n", cand.c_str());
            return cand;
        }
        if (debug) std::fprintf(stderr, "SHADER: miss  [%s]\n", cand.c_str());
        // Windows paths come back from GetModuleFileNameA with backslashes;
        // splitting on '/' alone stops the walk on the first iteration and
        // lands on the CWD fallback, which is how the shaders went missing.
        auto pos = dir.find_last_of("/\\");
        if (pos == std::string::npos || pos == 0) break;
        dir = dir.substr(0, pos);
    }
    if (debug) std::fprintf(stderr, "SHADER: fallback [src/shaders]\n");
    // Fall back to the working directory (e.g. `mcpp run` from project root).
    if (shader_dir_exists("src/shaders")) return "src/shaders";
    return "src/shaders"; // let the shader loader report the failure
#endif
}

#endif
