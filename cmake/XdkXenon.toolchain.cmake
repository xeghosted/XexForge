# Xbox 360 (Xenon / PowerPC, big-endian) — official XDK toolchain for CMake.
set(CMAKE_SYSTEM_NAME      Generic)
set(CMAKE_SYSTEM_PROCESSOR ppcbe)

if(NOT DEFINED ENV{XEDK})
    message(FATAL_ERROR "XEDK is not set. Install the Xbox 360 XDK or set the XEDK environment variable to its root.")
endif()

file(TO_CMAKE_PATH "$ENV{XEDK}" XDK_ROOT)
set(_xdk_bin "${XDK_ROOT}/bin/win32")

set(CMAKE_C_COMPILER   "${_xdk_bin}/cl.exe")
set(CMAKE_CXX_COMPILER "${_xdk_bin}/cl.exe")
set(CMAKE_AR           "${_xdk_bin}/lib.exe")
set(CMAKE_LINKER       "${_xdk_bin}/link.exe")
set(XDK_IMAGEXEX       "${_xdk_bin}/imagexex.exe" CACHE FILEPATH "XEX packager")

# The 2010-era Xenon cl.exe confuses CMake's compiler identification/ABI probe.
# Don't attempt to link a test executable during identification, and force the id.
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)
set(CMAKE_C_COMPILER_ID   MSVC)
set(CMAKE_CXX_COMPILER_ID MSVC)
set(CMAKE_C_COMPILER_FORCED   TRUE)
set(CMAKE_CXX_COMPILER_FORCED TRUE)

# XDK headers / import libs.
include_directories(SYSTEM "${XDK_ROOT}/include/xbox")
link_directories("${XDK_ROOT}/lib/xbox")

# Compile flags — matched to the proven xstd_test.vcxproj.
# Note: redefining _MSC_VER emits CL C4005 warnings — expected (mirrors the proven XDK vcxproj); not an error.
add_compile_definitions(_XBOX NDEBUG _MSC_VER=1300)
add_compile_options(/MT /O1 /GL /EHs-c-)

# Find host programs normally; resolve libs/includes only under the XDK roots.
set(CMAKE_FIND_ROOT_PATH "${XDK_ROOT}")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)

# NOTE: The Generic platform (CMakeGenericSystem.cmake) applies GNU naming
# conventions and forces TARGET_SUPPORTS_SHARED_LIBS FALSE *after* this toolchain
# runs, clobbering anything set here. The MSVC library naming, shared-lib support,
# and the explicit link.exe/lib.exe build rules therefore live in cmake/XdkXex.cmake,
# which is include()d from the generated CMakeLists AFTER project() — too late to be
# clobbered. See that file for the MSVC conventions + rules.
