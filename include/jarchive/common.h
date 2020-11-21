#pragma once

enum
{
    JARC_OK             = 0,
    JARC_EOF            = 1000,
    JARC_BAD_DATA       = 1001,
    JARC_UNKNOWN_ERROR  = 1002,
    JARC_CANT_READ      = 1003,
    JARC_CANT_WRITE     = 1004,
    JARC_WRONG_MODE     = 1005,
    JARC_OOM            = 1006
};
typedef int JarcResult;

enum
{
    JARC_READ       = 1 << 0,
    JARC_WRITE      = 1 << 1,
    JARC_READ_WRITE = JARC_READ | JARC_WRITE
};
typedef int JarcReadWrite;