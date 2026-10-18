/*
 * FireflyVPN NAPI 桥接
 *
 * Go/sing-box 内核以 libfireflycore.so 形式打包在同一应用 lib 目录。
 * 这里用 dlopen 延迟加载：内核缺失或 ABI 不匹配时只返回错误字符串，
 * 不会让 ArkTS 侧崩溃，也不会创建黑洞 TUN。
 */
#include "napi/native_api.h"

#include <dlfcn.h>
#include <string>
#include <vector>

namespace {

constexpr const char *CORE_LIBRARY = "libfireflycore.so";

using FireflyStartFn = char *(*)(const char *, int);
using FireflyStopFn = char *(*)();
using FireflyVersionFn = char *(*)();
using FireflyFreeFn = void (*)(char *);

struct CoreApi {
    void *handle = nullptr;
    FireflyStartFn start = nullptr;
    FireflyStopFn stop = nullptr;
    FireflyVersionFn version = nullptr;
    FireflyFreeFn release = nullptr;
    std::string error;
};

CoreApi &coreApi()
{
    static CoreApi api;
    static bool initialized = false;
    if (initialized) {
        return api;
    }
    initialized = true;
    api.handle = dlopen(CORE_LIBRARY, RTLD_NOW | RTLD_LOCAL);
    if (api.handle == nullptr) {
        const char *reason = dlerror();
        api.error = reason != nullptr ? reason : "dlopen failed";
        return api;
    }
    api.start = reinterpret_cast<FireflyStartFn>(dlsym(api.handle, "FireflyStart"));
    api.stop = reinterpret_cast<FireflyStopFn>(dlsym(api.handle, "FireflyStop"));
    api.version = reinterpret_cast<FireflyVersionFn>(dlsym(api.handle, "FireflyVersion"));
    api.release = reinterpret_cast<FireflyFreeFn>(dlsym(api.handle, "FireflyFree"));
    if (api.start == nullptr || api.stop == nullptr || api.version == nullptr || api.release == nullptr) {
        api.error = "symbol lookup failed";
    }
    return api;
}

napi_value makeString(napi_env env, const std::string &value)
{
    napi_value result = nullptr;
    napi_create_string_utf8(env, value.c_str(), value.size(), &result);
    return result;
}

std::string readString(napi_env env, napi_value value)
{
    size_t length = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok) {
        return {};
    }
    std::vector<char> buffer(length + 1, '\0');
    if (napi_get_value_string_utf8(env, value, buffer.data(), buffer.size(), &length) != napi_ok) {
        return {};
    }
    return std::string(buffer.data(), length);
}

std::string takeResult(CoreApi &api, char *raw)
{
    if (raw == nullptr) {
        return {};
    }
    std::string value(raw);
    if (api.release != nullptr) {
        api.release(raw);
    }
    return value;
}

napi_value Start(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    CoreApi &api = coreApi();
    if (api.start == nullptr) {
        return makeString(env, "core unavailable: " + api.error);
    }
    std::string config = readString(env, args[0]);
    int32_t fd = -1;
    napi_get_value_int32(env, args[1], &fd);
    return makeString(env, takeResult(api, api.start(config.c_str(), static_cast<int>(fd))));
}

napi_value Stop(napi_env env, napi_callback_info info)
{
    CoreApi &api = coreApi();
    if (api.stop == nullptr) {
        return makeString(env, "core unavailable: " + api.error);
    }
    return makeString(env, takeResult(api, api.stop()));
}

napi_value Version(napi_env env, napi_callback_info info)
{
    CoreApi &api = coreApi();
    if (api.version == nullptr) {
        return makeString(env, "unavailable (" + api.error + ")");
    }
    return makeString(env, takeResult(api, api.version()));
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        {"start", nullptr, Start, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stop", nullptr, Stop, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"version", nullptr, Version, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module fireflyModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "firefly",
    .nm_priv = ((void *)0),
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterFireflyModule(void)
{
    napi_module_register(&fireflyModule);
}

} // namespace
