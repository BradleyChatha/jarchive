#ifndef __JARCHIVE_BINARYSTREAM_H
#define __JARCHIVE_BINARYSTREAM_H

#include <stdint.h>
#include "enums.h"

typedef void JarcBinaryStream;

JarcBinaryStream* jarcBinaryStream_openBorrowedMemory(JarcReadWrite readWrite, uint8_t* bytes, size_t length);
JarcBinaryStream* jarcBinaryStream_openOwnedMemory(JarcReadWrite readWrite, uint8_t* bytes, size_t length);
JarcBinaryStream* jarcBinaryStream_openCopyOwnedMemory(JarcReadWrite readWrite, const uint8_t* bytes, size_t length);
JarcBinaryStream* jarcBinaryStream_openNewMemory(JarcReadWrite readWrite);
JarcBinaryStream* jarcBinaryStream_openFileByNamez(JarcReadWrite readWrite, const char* name);
JarcBinaryStream* jarcBinaryStream_openFileByName(JarcReadWrite readWrite, const char* name, size_t length);
void jarcBinaryStream_free(JarcBinaryStream* stream);

JarcResult jarcBinaryStream_setCursor(JarcBinaryStream* stream, long offset);
long jarcBinaryStream_getCursor(JarcBinaryStream* stream);
bool jarcBinaryStream_isEof(JarcBinaryStream* stream);

size_t jarcBinaryStream_readBytes(
    JarcBinaryStream* stream, 
    uint8_t*          buffer, 
    size_t*           bufferSize, 
    size_t            amount
);
JarcResult jarcBinaryStream_readU8(JarcBinaryStream* stream, uint8_t* data);
JarcResult jarcBinaryStream_readU16(JarcBinaryStream* stream, uint16_t* data);
JarcResult jarcBinaryStream_readU32(JarcBinaryStream* stream, uint32_t* data);
JarcResult jarcBinaryStream_readU64(JarcBinaryStream* stream, uint64_t* data);
JarcResult jarcBinaryStream_read7BitEncodedU(JarcBinaryStream* stream, uint64_t* data);
JarcResult jarcBinaryStream_readMallocedString(JarcBinaryStream* stream, char** outputPtr, size_t* lengthPtr);

JarcResult jarcBinaryStream_writeBytes(
    JarcBinaryStream* stream,
    const uint8_t* bytes,
    size_t amount
);
JarcResult jarcBinaryStream_writeU8(JarcBinaryStream* stream, uint8_t data);
JarcResult jarcBinaryStream_writeU16(JarcBinaryStream* stream, uint16_t data);
JarcResult jarcBinaryStream_writeU32(JarcBinaryStream* stream, uint32_t data);
JarcResult jarcBinaryStream_writeU64(JarcBinaryStream* stream, uint64_t data);
JarcResult jarcBinaryStream_write7BitEncodedU(JarcBinaryStream* stream, uint64_t data);
JarcResult jarcBinaryStream_writeString(JarcBinaryStream* stream, const char* text, size_t textLength);

JarcResult jarcBinaryStream_getMemory(JarcBinaryStream* stream, uint8_t** bytesPtr, size_t* lengthPtr);

uint32_t jarcBinaryStream_calculateCrc(JarcBinaryStream* stream, long ptrStart);
#endif