module jarchive.lzma;

import core.stdc.config, core.stdc.stdlib;

struct CLzmaEncProps
{
  int level;       /* 0 <= level <= 9 */
  uint dictSize; /* (1 << 12) <= dictSize <= (1 << 27) for 32-bit version
                      (1 << 12) <= dictSize <= (3 << 29) for 64-bit version
                      default = (1 << 24) */
  int lc;          /* 0 <= lc <= 8, default = 3 */
  int lp;          /* 0 <= lp <= 4, default = 0 */
  int pb;          /* 0 <= pb <= 4, default = 2 */
  int algo;        /* 0 - fast, 1 - normal, default = 1 */
  int fb;          /* 5 <= fb <= 273, default = 32 */
  int btMode;      /* 0 - hashChain Mode, 1 - binTree mode - normal, default = 1 */
  int numHashBytes; /* 2, 3 or 4, default = 4 */
  uint mc;       /* 1 <= mc <= (1 << 30), default = 32 */
  uint writeEndMark;  /* 0 - do not write EOPM, 1 - write EOPM, default = 0 */
  int numThreads;  /* 1 or 2, default = 2 */

  ulong reduceSize; /* estimated size of data that will be compressed. default = (UInt64)(Int64)-1.
                        Encoder uses this value to reduce dictionary size */
}

struct ICompressProgress
{
  extern(C) SRes function(const ICompressProgress*, uint, uint) Progress;
    /* Returns: result. (result != SZ_OK) means break.
       Value (UInt64)(Int64)-1 for size means unknown value. */
}

struct ISzAlloc
{
  extern(C) void* function(ISzAllocPtr, size_t) Alloc;
  extern(C) void function(ISzAllocPtr, void*) Free; /* address can be 0 */
}

alias const ISzAlloc* ISzAllocPtr;

ISzAlloc g_defaultLzmaAlloc = ISzAlloc((_, amount) => malloc(amount), (_, ptr) => free(ptr));
ICompressProgress g_defaultLzmaProgress = ICompressProgress((_, __, ___) => SZ_OK);

extern(C) @nogc nothrow:

alias SRes = int;
enum : SRes
{
    SZ_OK = 0,
    SZ_ERROR_OUTPUT_EOF = 7
}

alias ELzmaFinishMode = int;
enum : ELzmaFinishMode
{
  LZMA_FINISH_ANY,   /* finish at any point */
  LZMA_FINISH_END    /* block must be finished at the end */
};

alias ELzmaStatus = int;
enum : ELzmaStatus
{
  LZMA_STATUS_NOT_SPECIFIED,               /* use main error code instead */
  LZMA_STATUS_FINISHED_WITH_MARK,          /* stream was finished with end mark. */
  LZMA_STATUS_NOT_FINISHED,                /* stream was not finished */
  LZMA_STATUS_NEEDS_MORE_INPUT,            /* you must provide more input bytes */
  LZMA_STATUS_MAYBE_FINISHED_WITHOUT_MARK  /* there is probability that stream was finished without end mark */
}

void LzmaEncProps_Init(CLzmaEncProps* p);
SRes LzmaEncode(
    ubyte*                  dest, 
    size_t*                 destLen, 
    const ubyte*            src, 
    size_t                  srcLen,
    const CLzmaEncProps*    props, 
    ubyte*                  propsEncoded, 
    size_t*                 propsSize, 
    int                     writeEndMark,
    ICompressProgress*      progress, 
    ISzAllocPtr             alloc, 
    ISzAllocPtr             allocBig
);

SRes LzmaDecode(
    ubyte* dest, 
    size_t* destLen, 
    const ubyte* src, 
    size_t* srcLen,
    const ubyte* propData, 
    uint propSize, 
    ELzmaFinishMode finishMode,
    ELzmaStatus* status, 
    ISzAllocPtr alloc
);