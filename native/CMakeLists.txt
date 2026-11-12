cmake_minimum_required(VERSION 3.18)

project(tt_audio C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_POSITION_INDEPENDENT_CODE ON)

set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(OPUS_BUILD_SHARED_LIBRARY OFF CACHE BOOL "" FORCE)
set(OPUS_BUILD_PROGRAMS OFF CACHE BOOL "" FORCE)
set(OPUS_BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(OPUS_INSTALL_PKG_CONFIG_MODULE OFF CACHE BOOL "" FORCE)
set(OPUS_INSTALL_CMAKE_CONFIG_MODULE OFF CACHE BOOL "" FORCE)
set(OPUS_DEEP_PLC ON CACHE BOOL "" FORCE)
set(OPUS_DRED ON CACHE BOOL "" FORCE)
set(OPUS_OSCE ON CACHE BOOL "" FORCE)
if(ANDROID AND ANDROID_ABI STREQUAL "armeabi-v7a")
  set(OPUS_PRESUME_NEON ON CACHE BOOL "" FORCE)
endif()

option(TT_SANITIZE "Build with AddressSanitizer and UndefinedBehaviorSanitizer" OFF)
if(TT_SANITIZE)
  if(MSVC)
    message(FATAL_ERROR "TT_SANITIZE needs GCC or Clang")
  endif()
  add_compile_options(-fsanitize=address,undefined -fno-sanitize-recover=all
    -fno-omit-frame-pointer -g)
  add_link_options(-fsanitize=address,undefined)
endif()

include(FetchContent)
find_package(Git REQUIRED)

FetchContent_Declare(
  opus
  URL https://downloads.xiph.org/releases/opus/opus-1.6.1.tar.gz
  URL_HASH SHA256=6ffcb593207be92584df15b32466ed64bbec99109f007c82205f0194572411a1
  DOWNLOAD_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../build/native-downloads
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE
)

FetchContent_Declare(
  rnnoise
  URL https://github.com/xiph/rnnoise/releases/download/v0.2/rnnoise-0.2.tar.gz
  URL_HASH SHA256=90fce4b00b9ff24c08dbfe31b82ffd43bae383d85c5535676d28b0a2b11c0d37
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE
  PATCH_COMMAND ${CMAKE_COMMAND} -E env
    GIT_CEILING_DIRECTORIES=${FETCHCONTENT_BASE_DIR}
    ${GIT_EXECUTABLE} apply
    ${CMAKE_CURRENT_SOURCE_DIR}/patches/rnnoise-0.2-fix-compilation.patch
)

FetchContent_Declare(
  sonic
  URL https://github.com/waywardgeek/sonic/archive/b93885dcb70aae50c6f76b0fe4e0868f029a077e.tar.gz
  URL_HASH SHA256=b76d832649306b53e716c271014c0b8f89f6bcefc43e5068a2eca3cf1946324c
  DOWNLOAD_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../build/native-downloads
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE
)

FetchContent_Declare(
  speex
  URL https://downloads.xiph.org/releases/speex/speex-1.2.1.tar.gz
  URL_HASH SHA256=4b44d4f2b38a370a2d98a78329fefc56a0cf93d1c1be70029217baae6628feea
  DOWNLOAD_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../build/native-downloads
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE
)

FetchContent_MakeAvailable(opus rnnoise sonic speex)
target_compile_definitions(opus PRIVATE ENABLE_OSCE_BWE)

set(SPEEX_SRC ${speex_SOURCE_DIR}/libspeex)
set(SPEEX_GEN ${CMAKE_CURRENT_BINARY_DIR}/speex-gen)
file(WRITE ${SPEEX_GEN}/speex_config_types.h
"#ifndef __SPEEX_TYPES_H__
#define __SPEEX_TYPES_H__
#include <stdint.h>
typedef int16_t spx_int16_t;
typedef uint16_t spx_uint16_t;
typedef int32_t spx_int32_t;
typedef uint32_t spx_uint32_t;
#endif
")
add_library(speex STATIC
  ${SPEEX_SRC}/bits.c
  ${SPEEX_SRC}/cb_search.c
  ${SPEEX_SRC}/exc_10_16_table.c
  ${SPEEX_SRC}/exc_10_32_table.c
  ${SPEEX_SRC}/exc_20_32_table.c
  ${SPEEX_SRC}/exc_5_256_table.c
  ${SPEEX_SRC}/exc_5_64_table.c
  ${SPEEX_SRC}/exc_8_128_table.c
  ${SPEEX_SRC}/filters.c
  ${SPEEX_SRC}/gain_table.c
  ${SPEEX_SRC}/gain_table_lbr.c
  ${SPEEX_SRC}/hexc_10_32_table.c
  ${SPEEX_SRC}/hexc_table.c
  ${SPEEX_SRC}/high_lsp_tables.c
  ${SPEEX_SRC}/lpc.c
  ${SPEEX_SRC}/lsp.c
  ${SPEEX_SRC}/lsp_tables_nb.c
  ${SPEEX_SRC}/ltp.c
  ${SPEEX_SRC}/modes.c
  ${SPEEX_SRC}/modes_wb.c
  ${SPEEX_SRC}/nb_celp.c
  ${SPEEX_SRC}/quant_lsp.c
  ${SPEEX_SRC}/sb_celp.c
  ${SPEEX_SRC}/speex.c
  ${SPEEX_SRC}/speex_callbacks.c
  ${SPEEX_SRC}/speex_header.c
  ${SPEEX_SRC}/stereo.c
  ${SPEEX_SRC}/vbr.c
  ${SPEEX_SRC}/vq.c
  ${SPEEX_SRC}/window.c
)
target_include_directories(speex
  PUBLIC ${speex_SOURCE_DIR}/include ${SPEEX_GEN}
  PRIVATE ${SPEEX_SRC}
)
target_compile_definitions(speex PRIVATE FLOATING_POINT USE_ALLOCA EXPORT=
  DISABLE_NOTIFICATIONS DISABLE_WARNINGS)
if(MSVC)
  target_compile_definitions(speex PRIVATE _USE_MATH_DEFINES _CRT_SECURE_NO_WARNINGS)
else()
  target_compile_definitions(speex PRIVATE HAVE_ALLOCA_H)
  target_link_libraries(speex PRIVATE m)
endif()

add_library(sonic STATIC ${sonic_SOURCE_DIR}/sonic.c)
target_include_directories(sonic PUBLIC ${sonic_SOURCE_DIR})
if(MSVC)
  target_compile_definitions(sonic PRIVATE _USE_MATH_DEFINES _CRT_SECURE_NO_WARNINGS)
else()
  target_link_libraries(sonic PRIVATE m)
endif()

if(ANDROID)
  FetchContent_Declare(
    oboe
    URL https://github.com/google/oboe/archive/b115f47593969fd67a21e9f63640ffef749b5067.tar.gz
    URL_HASH SHA256=1694a9756d6b3f9385c57ef6e67e516dfd519accc3c42f3834c8f95f6c3a0301
    DOWNLOAD_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../build/native-downloads
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
  )
  FetchContent_MakeAvailable(oboe)
endif()

set(RNNOISE_SRC ${rnnoise_SOURCE_DIR}/src)
add_library(rnnoise STATIC
  ${RNNOISE_SRC}/celt_lpc.c
  ${RNNOISE_SRC}/denoise.c
  ${RNNOISE_SRC}/kiss_fft.c
  ${RNNOISE_SRC}/nnet.c
  ${RNNOISE_SRC}/nnet_default.c
  ${RNNOISE_SRC}/parse_lpcnet_weights.c
  ${RNNOISE_SRC}/pitch.c
  ${RNNOISE_SRC}/rnn.c
  ${RNNOISE_SRC}/rnnoise_data.c
  ${RNNOISE_SRC}/rnnoise_tables.c
)
target_include_directories(rnnoise
  PUBLIC ${rnnoise_SOURCE_DIR}/include
  PRIVATE ${RNNOISE_SRC}
)
if(MSVC)
  target_compile_definitions(rnnoise PRIVATE _USE_MATH_DEFINES)
else()
  target_link_libraries(rnnoise PRIVATE m)
endif()

if(MSVC)
  set(TT_DSP_OPTIMIZE /O2)
else()
  set(TT_DSP_OPTIMIZE -O2)
endif()
foreach(dsp opus rnnoise sonic speex)
  target_compile_options(${dsp} PRIVATE ${TT_DSP_OPTIMIZE})
endforeach()

set(TT_AUDIO_SOURCES
  opus_wrapper.c
  rnnoise_wrapper.c
  silero_vad.c
  speex_wrapper.c
  stretch_wrapper.c
  tt_engine.cpp
  engine/engine_core.cpp
)
if(ANDROID)
  list(APPEND TT_AUDIO_SOURCES engine/device_streams.cpp media_decoder.c)
endif()

add_library(tt_audio SHARED ${TT_AUDIO_SOURCES})
target_compile_options(tt_audio PRIVATE ${TT_DSP_OPTIMIZE})
if(ANDROID)
  target_link_libraries(tt_audio PRIVATE oboe log mediandk)
endif()

target_include_directories(tt_audio PRIVATE ${opus_SOURCE_DIR}/include)
target_link_libraries(tt_audio PRIVATE opus rnnoise sonic speex)
