cmake_minimum_required(VERSION 3.20)
project(msl VERSION 1.0.0 LANGUAGES C)

set(CMAKE_OSX_DEPLOYMENT_TARGET "14.0")
set(CMAKE_C_STANDARD 17)

find_library(VIRT_FW Virtualization REQUIRED)
find_library(FOUNDATION_FW Foundation REQUIRED)

add_executable(msl
    src/main.c
    src/daemon.m
    src/vm.m
    src/console.m
    src/setup.m
    src/state.m
    src/ipc.m
    src/runtime.h
    src/daemon.h
    src/vm.h
    src/console.h
    src/setup.h
    src/state.h
    src/ipc.h
)

target_link_libraries(msl PRIVATE
    ${VIRT_FW}
    ${FOUNDATION_FW}
)

target_include_directories(msl PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)

add_custom_command(TARGET msl POST_BUILD
    COMMAND codesign --entitlements "${CMAKE_SOURCE_DIR}/Resources/msl.entitlements" -f -s - "$<TARGET_FILE:msl>"
    COMMENT "Code-signing msl with virtualization entitlement"
)
