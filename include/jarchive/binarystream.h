#pragma once

#include <inttypes.h>
#include "common.h"

#define READ_PRIMITIVE(NAME, T) \
    JarcResult jarcBinaryStream_read ## NAME (JarcBinaryStream* stream, T* data);

#define WRITE_PRIMITIVE(NAME, T) \
    JarcResult jarcBinaryStream_write ## NAME (JarcBinaryStream* stream, T data);

typedef void JarcBinaryStream;

JarcBinaryStream* jarcBinaryStream_openBorrowedMemory(JarcReadWrite readWrite, uint8_t* bytes, uintptr_t length);
JarcBinaryStream* jarcBinaryStream_openOwnedMemory(JarcReadWrite readWrite, uint8_t* bytes, uintptr_t length);
JarcBinaryStream* jarcBinaryStream_openCopyOwnedMemory(JarcReadWrite readWrite, uint8_t* bytes, uintptr_t length);
JarcBinaryStream* jarcBinaryStream_openNewMemory(JarcReadWrite readWrite);
JarcBinaryStream* jarcBinaryStream_openFileByNamez(JarcReadWrite readWrite, uint8_t* name);
JarcBinaryStream* jarcBinaryStream_openFileByName(JarcReadWrite readWrite, uint8_t* name_, uintptr_t length);
void jarcBinaryStream_free(JarcBinaryStream* stream);

JarcResult jarcBinaryStream_setCursor(JarcBinaryStream* stream, long offset);
long jarcBinaryStream_getCursor(JarcBinaryStream* stream);
uint8_t jarcBinaryStream_isEof(JarcBinaryStream* stream);

uintptr_t jarcBinaryStream_readBytes(
    JarcBinaryStream* stream, 
    char*             buffer, 
    uintptr_t*        bufferSize, 
    uintptr_t         amount
);
READ_PRIMITIVE(U8,  uint8_t);
READ_PRIMITIVE(U16, uint16_t);
READ_PRIMITIVE(U32, uint32_t);
READ_PRIMITIVE(U64, uint64_t);
JarcResult jarcBinaryStream_read7BitEncodedU(JarcBinaryStream* stream, uint64_t* data);

JarcResult jarcBinaryStream_writeBytes(JarcBinaryStream* stream, char* bytes, uintptr_t amount);
WRITE_PRIMITIVE(U8,  uint8_t);
WRITE_PRIMITIVE(U16, uint16_t);
WRITE_PRIMITIVE(U32, uint32_t);
WRITE_PRIMITIVE(U64, uint64_t);
JarcResult jarcBinaryStream_write7BitEncodedU(JarcBinaryStream* stream, uint64_t data);