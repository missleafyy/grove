cmake_minimum_required(VERSION 3.20)
project(Grove C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

# ---- Jolt Physics ----------------------------------------------------------
set(TARGET_UNIT_TESTS OFF CACHE BOOL "" FORCE)
set(TARGET_HELLO_WORLD OFF CACHE BOOL "" FORCE)
set(TARGET_PERFORMANCE_TEST OFF CACHE BOOL "" FORCE)
set(TARGET_SAMPLES OFF CACHE BOOL "" FORCE)
set(TARGET_VIEWER OFF CACHE BOOL "" FORCE)
set(ENABLE_ALL_WARNINGS OFF CACHE BOOL "" FORCE)
set(INTERPROCEDURAL_OPTIMIZATION OFF CACHE BOOL "" FORCE)
set(FLOATING_POINT_EXCEPTIONS_ENABLED OFF CACHE BOOL "" FORCE)
set(DEBUG_RENDERER_IN_DEBUG_AND_RELEASE OFF CACHE BOOL "" FORCE)
set(PROFILER_IN_DEBUG_AND_RELEASE OFF CACHE BOOL "" FORCE)
set(ENABLE_OBJECT_STREAM OFF CACHE BOOL "" FORCE)
set(ENABLE_INSTALL OFF CACHE BOOL "" FORCE)
set(GENERATE_DEBUG_SYMBOLS OFF CACHE BOOL "" FORCE)
add_subdirectory(third_party/jolt/Build jolt_build EXCLUDE_FROM_ALL)

# ---- Third-party C code ----------------------------------------------------
add_library(grove_thirdparty STATIC
  third_party/glad/src/gl.c
  src/thirdparty_impl.c)
target_include_directories(grove_thirdparty PUBLIC
  third_party/glad/include third_party/stb third_party)
target_compile_options(grove_thirdparty PRIVATE -O2 -w)

# ---- LuaJIT (prebuilt static lib) -----------------------------------------
# Windows cross builds (tools/windows/build.sh) pass GROVE_WIN_DEPS: a folder holding the
# Windows libluajit.a and a static GLFW install (include/, lib/libglfw3.a).
if(WIN32)
  set(LUAJIT_LIB ${GROVE_WIN_DEPS}/libluajit.a)
else()
  set(LUAJIT_LIB ${CMAKE_SOURCE_DIR}/third_party/luajit/src/libluajit.a)
endif()
add_library(luajit STATIC IMPORTED)
set_target_properties(luajit PROPERTIES
  IMPORTED_LOCATION ${LUAJIT_LIB}
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_SOURCE_DIR}/third_party/luajit/src)

if(WIN32)
  add_library(glfw_win STATIC IMPORTED)
  set_target_properties(glfw_win PROPERTIES
    IMPORTED_LOCATION ${GROVE_WIN_DEPS}/glfw/lib/libglfw3.a
    INTERFACE_INCLUDE_DIRECTORIES ${GROVE_WIN_DEPS}/glfw/include)
  set(GROVE_PLATFORM_LIBS glfw_win opengl32 gdi32 user32 shell32 winmm ole32)
else()
  find_package(PkgConfig REQUIRED)
  pkg_check_modules(GLFW REQUIRED IMPORTED_TARGET glfw3)
  set(GROVE_PLATFORM_LIBS PkgConfig::GLFW dl m pthread)
endif()

# ---- Engine ----------------------------------------------------------------
add_executable(grove
  src/main.cpp
  src/renderer.cpp
  src/canvas.cpp
  src/physics.cpp
  src/audio.cpp
  src/input.cpp
  src/meshload.cpp)
target_include_directories(grove PRIVATE src)
target_link_libraries(grove PRIVATE grove_thirdparty Jolt luajit ${GROVE_PLATFORM_LIBS})
target_compile_options(grove PRIVATE -O2 -Wall -Wno-unused-function -Wno-missing-field-initializers)
# Export symbols so LuaJIT's FFI (ffi.C) can see the engine's C API.
set_target_properties(grove PROPERTIES ENABLE_EXPORTS ON
  RUNTIME_OUTPUT_DIRECTORY ${CMAKE_SOURCE_DIR}/bin)
if(WIN32)
  # ffi.C on Windows looks the gr_* functions up in the .exe's export table, so export every
  # function api.h declares through a generated .def file. Static runtimes keep it to one grove.exe.
  file(READ ${CMAKE_SOURCE_DIR}/engine/api.h GROVE_API)
  string(REGEX MATCHALL "gr_[a-z0-9_]+[ ]*\\(" GROVE_FUNCS "${GROVE_API}")
  set(GROVE_DEF "EXPORTS\n")
  foreach(f ${GROVE_FUNCS})
    string(REGEX REPLACE "[ (]" "" f "${f}")
    string(APPEND GROVE_DEF "  ${f}\n")
  endforeach()
  file(WRITE ${CMAKE_BINARY_DIR}/grove.def "${GROVE_DEF}")
  set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${CMAKE_SOURCE_DIR}/engine/api.h)
  target_link_options(grove PRIVATE ${CMAKE_BINARY_DIR}/grove.def -static)
  set_target_properties(grove PROPERTIES RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
endif()
