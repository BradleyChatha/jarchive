#ifndef __JARCHIVE_WRITER_H
#define __JARCHIVE_WRITER_H

#include <stdint.h>
#include "binarystream.h"
#include "chunkhandler.h"
#include "enums.h"

typedef void JarcWriter;

JarcResult jarcWriter_openNewMemory(JarcWriter** writer, JarcChunkHandler* handlers, size_t handlerCount);
JarcResult jarcWriter_finalise(JarcWriter* writer);
JarcResult jarcWriter_getMemory(JarcWriter* writer, uint8_t** bytesPtr, size_t* lengthPtr);
JarcChunkHandler* jarcWriter_getHandlerForType(JarcWriter* writer, const char* chunkType, size_t chunkTypeLength);
void jarcWriter_free(JarcWriter* writer);
JarcResult jarcWriter_writeChunk(
    JarcWriter* writer, 
    const char* chunkType, size_t chunkTypeLength,
    const char* name,      size_t nameLength,
    void* userData, 
    JarcFlags flags
);
#endif