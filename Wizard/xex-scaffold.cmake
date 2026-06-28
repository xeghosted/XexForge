# Usage: cmake -DNAME=MyPlugin -DTYPE=dll|exe -DTARGET_DIR=. -DTOOLKIT_ROOT=/xdk -P create-project.cmake
# Optional: -DENTRY_SYMBOL=GtampEntryPoint -DUSE_XKELIB=OFF -DXKELIB_DIR=

cmake_minimum_required(VERSION 3.21)

foreach(_req NAME TYPE TARGET_DIR TOOLKIT_ROOT)
    if(NOT DEFINED ${_req} OR "${${_req}}" STREQUAL "")
        message(FATAL_ERROR
            "Usage: cmake -DNAME=<n> -DTYPE=dll|exe -DTARGET_DIR=<d> -DTOOLKIT_ROOT=<k> -P create-project.cmake")
    endif()
endforeach()

if(NOT NAME MATCHES "^[A-Za-z][A-Za-z0-9_]*$")
    message(FATAL_ERROR "Invalid project name '${NAME}' (letter then letters/digits/_).")
endif()

string(TOLOWER "${TYPE}" _type_lower)
string(TOUPPER "${TYPE}" _type_upper)

if(NOT _type_lower STREQUAL "dll" AND NOT _type_lower STREQUAL "exe")
    message(FATAL_ERROR "TYPE must be dll or exe.")
endif()

# configure_file variables
set(PROJECT_NAME   "${NAME}")
set(XEX_TYPE       "${_type_upper}")
set(ENTRY_SYMBOL   "${ENTRY_SYMBOL}")
set(USE_XKELIB     "${USE_XKELIB}")
set(XKELIB_DIR     "${XKELIB_DIR}")
set(GENERATOR      "Ninja")
set(MAKE_PROGRAM_BLOCK "")

if(NOT ENTRY_SYMBOL)
    set(ENTRY_SYMBOL "GtampEntryPoint")
    set(PROJECT_NAME "${NAME}")  # re-set so ENTRY_SYMBOL is in scope for configure_file
endif()
if(NOT USE_XKELIB)
    set(USE_XKELIB "OFF")
endif()

if(_type_lower STREQUAL "dll")
    set(ENTRY_SOURCES " src/entry.cpp")
else()
    set(ENTRY_SOURCES "")
endif()

set(_proj_dir "${TARGET_DIR}/${NAME}")
if(EXISTS "${_proj_dir}")
    message(FATAL_ERROR "Target already exists: ${_proj_dir}")
endif()

set(_tmpl "${TOOLKIT_ROOT}/template")

file(MAKE_DIRECTORY "${_proj_dir}/src")

configure_file("${_tmpl}/CMakeLists.txt.in"    "${_proj_dir}/CMakeLists.txt"    @ONLY)
configure_file("${_tmpl}/CMakePresets.json.in" "${_proj_dir}/CMakePresets.json" @ONLY)

if(_type_lower STREQUAL "dll")
    configure_file("${_tmpl}/Application_dll.xml.in" "${_proj_dir}/Application.xml"  @ONLY)
    configure_file("${_tmpl}/src/main_dll.cpp.in"    "${_proj_dir}/src/main.cpp"     @ONLY)
    configure_file("${_tmpl}/src/entry.cpp.in"       "${_proj_dir}/src/entry.cpp"    @ONLY)
else()
    configure_file("${_tmpl}/Application_exe.xml.in" "${_proj_dir}/Application.xml"  @ONLY)
    configure_file("${_tmpl}/src/main_exe.cpp.in"    "${_proj_dir}/src/main.cpp"     @ONLY)
endif()

file(COPY "${TOOLKIT_ROOT}/cmake" DESTINATION "${_proj_dir}")

if(EXISTS "${_proj_dir}/cmake/wine")
    file(GLOB _wrappers "${_proj_dir}/cmake/wine/*")
    foreach(_w IN LISTS _wrappers)
        file(CHMOD "${_w}" PERMISSIONS
            OWNER_READ OWNER_WRITE OWNER_EXECUTE
            GROUP_READ GROUP_EXECUTE
            WORLD_READ WORLD_EXECUTE)
    endforeach()
endif()

message("Created XEX-${_type_upper} project: ${_proj_dir}")
message("")
message("To build on Windows:")
message("  cd ${NAME} && cmake --preset xdk && cmake --build build")
message("")
message("To build on Linux (via Wine):")
message("  cd ${NAME} && cmake --preset xdk-wine && cmake --build build")
