#ifndef RUNTIME_H
#define RUNTIME_H

#include <objc/runtime.h>
#include <objc/message.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdint.h>
#include <stdbool.h>

#define msg(RECEIVER, SELECTOR_NAME, ...) \
    ((id(*)(id, SEL, ...))objc_msgSend)((id)(RECEIVER), sel_registerName(SELECTOR_NAME), ##__VA_ARGS__)

#define cls(CLASS_NAME) objc_getClass(CLASS_NAME)

static inline id nsstr(const char *cstr) {
    if (!cstr) return NULL;
    return msg(cls("NSString"), "stringWithUTF8String:", cstr);
}

static inline id nsurl(const char *path) {
    return msg(cls("NSURL"), "fileURLWithPath:", nsstr(path));
}

static inline const char *cstr(id obj) {
    if (!obj) return NULL;
    return (const char *)msg(obj, "UTF8String");
}

static inline const char *err_desc(id error) {
    if (!error) return "unknown error";
    id desc = msg(error, "localizedDescription");
    return cstr(desc) ? cstr(desc) : "unknown error";
}

#endif
