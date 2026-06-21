cmake_minimum_required(VERSION 3.21)
project(hello_xex CXX)

# In-repo sample: reference the repo's real cmake/ (not a copy).
list(APPEND CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/../../cmake")
include(XdkXex)

add_xex(hello_dll
    TYPE    DLL
    ENTRY   GtampEntryPoint
    CONFIG  "${CMAKE_SOURCE_DIR}/Application_dll.xml"
    SOURCES src/plugin.cpp src/entry.cpp)

add_xex(hello_exe
    TYPE    EXE
    CONFIG  "${CMAKE_SOURCE_DIR}/Application_exe.xml"
    SOURCES src/main.cpp)
