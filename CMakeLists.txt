cmake_minimum_required(VERSION 3.14)

# C++11
set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED True)
# export commands for Linux
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

project(AccRT)

if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -g -Wall -O2")
endif()

# use glew static library
add_definitions(-DGLEW_STATIC)

# configure OpenGL
find_package(OpenGL REQUIRED)
# configure GLEW
option(glew-cmake_BUILD_SHARED "Build the shared glew library" OFF)
add_subdirectory(${CMAKE_SOURCE_DIR}/external/glew-cmake)
# configure GLFW
option(GLFW_BUILD_EXAMPLES "Build the GLFW example programs" OFF)
option(GLFW_BUILD_TESTS "Build the GLFW test programs" OFF)
option(GLFW_BUILD_DOCS "Build the GLFW documentation" OFF)
option(GLFW_INSTALL "Generate installation target" OFF)
add_subdirectory(${CMAKE_SOURCE_DIR}/external/glfw)
# configure ImGui
file(GLOB IMGUI_SRC
    ${CMAKE_SOURCE_DIR}/external/imgui/*.cpp
    ${CMAKE_SOURCE_DIR}/external/imgui/*.h
    ${CMAKE_SOURCE_DIR}/external/imgui/backends/imgui_impl_opengl3.h
    ${CMAKE_SOURCE_DIR}/external/imgui/backends/imgui_impl_opengl3.cpp
    ${CMAKE_SOURCE_DIR}/external/imgui/backends/imgui_impl_glfw.h
    ${CMAKE_SOURCE_DIR}/external/imgui/backends/imgui_impl_glfw.cpp
)
add_library(ImGui ${IMGUI_SRC})
target_include_directories(ImGui PRIVATE
    ${CMAKE_SOURCE_DIR}/external/glew-cmake/include
    ${CMAKE_SOURCE_DIR}/external/glfw/include
    ${CMAKE_SOURCE_DIR}/external/imgui
    ${CMAKE_SOURCE_DIR}/external/imgui/backends
)

# define executable
file(GLOB_RECURSE SRC_FILES "${CMAKE_SOURCE_DIR}/src/**.cpp" "${CMAKE_SOURCE_DIR}/src/**.hpp")
add_executable(accelerate ${SRC_FILES})

# define compile properties
set_target_properties(accelerate
    PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_SOURCE_DIR}/bin
    RUNTIME_OUTPUT_DIRECTORY_RELEASE ${CMAKE_SOURCE_DIR}/bin
    RUNTIME_OUTPUT_DIRECTORY_DEBUG ${CMAKE_SOURCE_DIR}/bin
)
target_include_directories(accelerate PRIVATE
    ${CMAKE_SOURCE_DIR}/src
    ${CMAKE_SOURCE_DIR}/external/glew-cmake/include
    ${CMAKE_SOURCE_DIR}/external/glfw/include
    ${CMAKE_SOURCE_DIR}/external/imgui
    ${CMAKE_SOURCE_DIR}/external/imgui/backends
)
target_link_libraries(accelerate PRIVATE
    libglew_static
    glfw
    ImGui
    OpenGL::GL
)

# auto copy shaders
add_custom_target(copy_shaders
    COMMAND ${CMAKE_COMMAND} -E copy_directory ${CMAKE_SOURCE_DIR}/shaders ${CMAKE_SOURCE_DIR}/bin/shaders
)
add_dependencies(accelerate copy_shaders)
