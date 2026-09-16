# 煽り将棋: やねうら王（NNUE halfkp_256x2-32-32）＋ FFI ブリッジを libyaneuraou.so としてビルドする。
# SPDX-License-Identifier: GPL-3.0-or-later
cmake_minimum_required(VERSION 3.10)
project(yaneuraou_ffi_library LANGUAGES CXX)

get_filename_component(NATIVE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../native" ABSOLUTE)
set(YO "${NATIVE_DIR}/yaneuraou/source")

set(YO_SOURCES
  main.cpp types.cpp bitboard.cpp misc.cpp movegen.cpp position.cpp usi.cpp
  usioption.cpp thread.cpp tt.cpp movepick.cpp timeman.cpp memory.cpp engine.cpp
  search.cpp score.cpp benchmark.cpp tune.cpp
  book/book.cpp book/apery_book.cpp book/policybook.cpp book/makebook.cpp book/makebook2025.cpp
  extra/bitop.cpp extra/long_effect.cpp extra/sfen_packer.cpp
  mate/mate.cpp mate/mate1ply_without_effect.cpp mate/mate1ply_with_effect.cpp mate/mate_solver.cpp
  eval/evaluate_bona_piece.cpp eval/evaluate.cpp eval/evaluate_io.cpp
  eval/evaluate_mir_inv_tools.cpp eval/material/evaluate_material.cpp
  testcmd/unit_test.cpp testcmd/mate_test_cmd.cpp testcmd/normal_test_cmd.cpp
  eval/nnue/evaluate_nnue.cpp eval/nnue/nnue_test_command.cpp
  eval/nnue/features/k.cpp eval/nnue/features/p.cpp eval/nnue/features/a2.cpp
  eval/nnue/features/half_kp.cpp eval/nnue/features/half_ka1.cpp eval/nnue/features/half_ka_hm1.cpp
  eval/nnue/features/half_ka2.cpp eval/nnue/features/half_ka_hm2.cpp eval/nnue/features/half_kp_vm.cpp
  eval/nnue/features/half_relative_kp.cpp eval/nnue/features/half_kpe9.cpp eval/nnue/features/pe9.cpp
  engine/yaneuraou-engine/yaneuraou-search.cpp
)
list(TRANSFORM YO_SOURCES PREPEND "${YO}/")

add_library(yaneuraou_ffi SHARED ${YO_SOURCES} "${NATIVE_DIR}/bridge/engine_bridge.cpp")
set_target_properties(yaneuraou_ffi PROPERTIES OUTPUT_NAME "yaneuraou" CXX_STANDARD 17)
target_include_directories(yaneuraou_ffi PRIVATE "${YO}" "${NATIVE_DIR}/bridge")
target_compile_definitions(yaneuraou_ffi PRIVATE
  NDEBUG UNICODE NO_EXCEPTIONS USE_MAKEFILE YANEURAOU_ENGINE_NNUE
  ENGINE_NAME_FROM_MAKEFILE=YaneuraOu_NNUE TARGET_CPU="${ANDROID_ABI}")
# デバッグビルドでも探索は最適化する（-O0 だと極端に弱く遅い）。
target_compile_options(yaneuraou_ffi PRIVATE -O3 -fno-exceptions -fno-rtti -fpermissive -w)

if (ANDROID_ABI STREQUAL "arm64-v8a")
  target_compile_definitions(yaneuraou_ffi PRIVATE IS_64BIT USE_NEON=8)
elseif (ANDROID_ABI STREQUAL "x86_64")
  target_compile_definitions(yaneuraou_ffi PRIVATE IS_64BIT USE_SSE42)
  target_compile_options(yaneuraou_ffi PRIVATE -msse4.2 -mpopcnt)
endif()

if (ANDROID)
  target_link_libraries(yaneuraou_ffi PRIVATE log)
  # Android 15 の 16KB ページサイズ対応
  target_link_options(yaneuraou_ffi PRIVATE "-Wl,-z,max-page-size=16384")
endif()
