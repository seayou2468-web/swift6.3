cmake_minimum_required(VERSION 3.24)
project(swiftlite LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

option(SWIFTLITE_ENABLE_SWIFT_FRONTEND_CORE "Enable direct Swift FrontendTool backend" OFF)
set(SWIFTLITE_SWIFT_FRONTEND_INCLUDE_DIR "" CACHE PATH "Path to swift/include for FrontendTool headers")
set(SWIFTLITE_SWIFT_FRONTEND_LIBS "" CACHE STRING "Semicolon-separated Swift frontend libraries")

add_library(swiftlite STATIC
  bridge/swiftlite_compiler.cpp
  core/SDKConfig.cpp
  core/ClangImporterConfigAdapter.cpp
  core/NativePipeline.cpp
  core/SwiftFrontendPipeline.cpp
)

target_include_directories(swiftlite
  PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)

if(SWIFTLITE_ENABLE_SWIFT_FRONTEND_CORE)
  if(SWIFTLITE_SWIFT_FRONTEND_INCLUDE_DIR STREQUAL "")
    message(FATAL_ERROR "SWIFTLITE_SWIFT_FRONTEND_INCLUDE_DIR must be set when SWIFTLITE_ENABLE_SWIFT_FRONTEND_CORE=ON")
  endif()
  target_include_directories(swiftlite PRIVATE ${SWIFTLITE_SWIFT_FRONTEND_INCLUDE_DIR})
  target_link_libraries(swiftlite PRIVATE ${SWIFTLITE_SWIFT_FRONTEND_LIBS})
endif()

target_compile_definitions(swiftlite
  PRIVATE SWIFTLITE_ENABLE_SWIFT_FRONTEND_CORE=$<BOOL:${SWIFTLITE_ENABLE_SWIFT_FRONTEND_CORE}>
)

# NOTE:
# SwiftSyntax + existing swift/lib/ASTGen bridge integration is intentionally
# split into a follow-up patch to keep MVP skeleton buildable first.
