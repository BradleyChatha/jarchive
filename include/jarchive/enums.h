#ifndef __JARCHIVE_ENUMS_H
#define __JARCHIVE_ENUMS_H

#include <stdint.h>

typedef uint8_t  JarcVersion;
typedef int32_t  JarcResult;
typedef uint16_t JarcFlags;
typedef int32_t  JarcReadWrite;

enum : JarcVersion
{
    JARC_VERSION_1 = 1,
    JARC_VERSION_LATEST = JARC_VERSION_1
};

enum : JarcResult
{
    JARC_OK             = 0,
    JARC_EOF            = 1000,
    JARC_BAD_DATA       = 1001,
    JARC_UNKNOWN_ERROR  = 1002,
    JARC_CANT_READ      = 1003,
    JARC_CANT_WRITE     = 1004,
    JARC_WRONG_MODE     = 1005,
    JARC_OOM            = 1006,
    JARC_NO_HANDLER     = 1007
};

enum : JarcFlags
{
    JARC_FLAG_NONE = 0,
    JARC_FLAG_COMPRESSED = 1 << 0
};

enum : JarcReadWrite
{
    JARC_READ = 1 << 0,
    JARC_WRITE = 1 << 1,
    JARC_READ_WRITE = JARC_READ | JARC_WRITE
}; 

#endif