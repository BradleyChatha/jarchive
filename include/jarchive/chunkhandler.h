#ifndef __JARCHIVE_CHUNKHANDLER_H
#define __JARCHIVE_CHUNKHANDLER_H

#include <stdint.h>
#include "binarystream.h"
#include "enums.h"

typedef JarcResult (*ChunkHandlerWriteAttributes)(JarcBinaryStream*, void*);
typedef JarcResult (*ChunkHandlerWriteBody)(JarcBinaryStream*, void*);
typedef JarcResult (*ChunkHandlerReadAttributes)(JarcBinaryStream*, void*);
typedef JarcResult (*ChunkHandlerReadBody)(JarcBinaryStream*, void*);

struct JarcChunkHandler
{
    const char* typeName;
    size_t typeNameLength;
    ChunkHandlerReadAttributes funcReadAttributes;
    ChunkHandlerReadBody funcReadBody;
    ChunkHandlerWriteAttributes funcWriteAttributes;
    ChunkHandlerWriteBody funcWriteBody;
};

#endif