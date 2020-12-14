#ifndef __JARCHIVE_READER_H
#define __JARCHIVE_READER_H

#include <stdint.h>
#include "binarystream.h"
#include "chunkhandler.h"
#include "enums.h"

typedef void JarcReader;

struct JarcChunkHeader
{
    JarcFlags flags;
    uint64_t uncompressedSize;
    uint64_t compressedSize;
    char lzmaHeader[5];
    uint64_t attributeSize;
    long ptrDataStart;
    long ptrAttributeStart;

    const char* name;
    size_t nameLength;

    const char* type;
    size_t typeLength;
};

JarcResult jarcReader_openBorrowedMemory(
    JarcReader** reader, 
    JarcChunkHandler* handlers, size_t handlerCount, 
    char* bytes, size_t byteCount
);
void jarcReader_free(JarcReader* reader);
JarcChunkHandler* jarcReader_getHandlerForType(JarcReader* reader, const char* chunkType, size_t chunkTypeLength);
void jarcReader_getChunkHeaders(JarcReader* reader, JarcChunkHeader** headers, size_t* headersCount);
JarcResult jarcReader_readChunkByHeader(JarcReader* reader, const JarcChunkHeader header, void* userDataDest);

#endif