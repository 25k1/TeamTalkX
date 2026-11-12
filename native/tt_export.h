#ifndef TT_EXPORT_H
#define TT_EXPORT_H

#if defined(_WIN32)
#define TT_EXPORT __declspec(dllexport)
#else
#define TT_EXPORT __attribute__((visibility("default")))
#endif

#endif
