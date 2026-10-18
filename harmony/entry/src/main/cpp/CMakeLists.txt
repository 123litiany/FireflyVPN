# FireflyVPN 原生桥接层
# 通过 dlopen 加载 Go/sing-box 内核 libfireflycore.so：
#   - 内核缺失时构建仍然成功，运行期明确返回 “不可用”
#   - 避免把未经验证的原生库变成硬依赖
cmake_minimum_required(VERSION 3.5.0)
project(firefly)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

include_directories(${NATIVERENDER_ROOT_PATH}
                    ${NATIVERENDER_ROOT_PATH}/include)

add_library(firefly SHARED napi_init.cpp)
target_link_libraries(firefly PUBLIC libace_napi.z.so)
