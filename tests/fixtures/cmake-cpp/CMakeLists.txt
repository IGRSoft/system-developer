cmake_minimum_required(VERSION 3.20)
project(fixture_cpp LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Default build is warning-clean; the planted defect is gated behind a flag so
# the happy path (`cmake --build` + `ctest`) stays green.
add_compile_options(-Wall -Wextra)

option(ENABLE_BUG "Compile the planted heap-buffer-overflow path" OFF)
if(ENABLE_BUG)
  add_compile_definitions(ENABLE_BUG)
endif()

# --- Library under test -----------------------------------------------------
add_library(ringbuffer STATIC src/ringbuffer.cpp)
target_include_directories(ringbuffer PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)

# --- GoogleTest via FetchContent -------------------------------------------
include(FetchContent)
FetchContent_Declare(
  googletest
  GIT_REPOSITORY https://github.com/google/googletest.git
  GIT_TAG v1.15.2 # pinned; verify against your toolchain
)
# Prevent GoogleTest from overriding the parent project's compiler/linker.
set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(googletest)

enable_testing()

add_executable(ringbuffer_test tests/ringbuffer_test.cpp)
target_link_libraries(ringbuffer_test PRIVATE ringbuffer GTest::gtest_main)

include(GoogleTest)
gtest_discover_tests(ringbuffer_test)
