module jarchive.reader;

import jarchive;

import core.stdc.config, core.stdc.stdio;

extern(C) nothrow @nogc:

struct JarcChunkHeader
{
    JarcFlags flags;
    ulong uncompressedSize;
    ulong compressedSize;
    ubyte[5] lzmaHeader;
    ulong attributeSize;
    c_long ptrDataStart;
    c_long ptrAttributeStart;

    const(char)* name;
    size_t nameLength;

    const(char)* type;
    size_t typeLength;
}

struct JarcReader
{
    @nogc nothrow 
    private
    {
        // State
        JarcBinaryStream*  _archiveStream;
        JarcChunkHandler[] _handlers;

        // Header
        ubyte[4]           _crc;
        JarcVersion        _version;
        uint               _chunkCount;

        // Buffers
        char[][]           _names;
        size_t             _namesRead;
        char[]             _typeBuffer;
        JarcChunkHeader[]  _chunkHeaders;
        ubyte[]            _chunkDataBuffer;

        JarcResult readHeader()
        {
            ubyte[JarcWriter.MAGIC_NUMBER.length] magicNumber;
            auto bytesRead = jarcBinaryStream_readBytes(this._archiveStream, magicNumber.ptr, null, magicNumber.length);
            if(bytesRead != magicNumber.length) return JARC_EOF;
            if(magicNumber != JarcWriter.MAGIC_NUMBER) return JARC_BAD_DATA;

            auto result = jarcBinaryStream_readU8(this._archiveStream, cast(ubyte*)&this._version);
            if(result != JARC_OK) return result;

            bytesRead = jarcBinaryStream_readBytes(this._archiveStream, this._crc.ptr, null, this._crc.length);
            if(bytesRead != this._crc.length) return JARC_EOF;

            result = jarcBinaryStream_readU32(this._archiveStream, &this._chunkCount);
            if(result != JARC_OK) return result;

            const ptrCurrent = jarcBinaryStream_getCursor(this._archiveStream);
            const crc = jarcBinaryStream_calculateCrc(this._archiveStream, ptrCurrent);

            if(crc != this._crc)
                return JARC_BAD_DATA;

            this._names = allocArray!(char[])(this._chunkCount);
            if(this._names is null)
                return JARC_OOM;

            this._chunkHeaders = allocArray!JarcChunkHeader(this._chunkCount);
            if(this._chunkHeaders is null)
                return JARC_OOM;

            foreach(i; 0..this._chunkCount)
            {
                result = this.readChunkHeader(&this._chunkHeaders[i]);
                if(result != JARC_OK) return result;

                // Move past the data.
                auto ptr = jarcBinaryStream_getCursor(this._archiveStream);
                ptr += this._chunkHeaders[i].attributeSize;
                ptr += (this._chunkHeaders[i].flags & JARC_FLAG_COMPRESSED)
                ? this._chunkHeaders[i].compressedSize
                : this._chunkHeaders[i].uncompressedSize;
                jarcBinaryStream_setCursor(this._archiveStream, ptr);
            }

            return JARC_OK;
        }

        JarcResult readChunkHeader(JarcChunkHeader* header)
        {
            auto result = jarcBinaryStream_readU16(this._archiveStream, &header.flags);
            if(result != JARC_OK) return result;

            result = jarcBinaryStream_read7BitEncodedU(this._archiveStream, &header.uncompressedSize);
            if(result != JARC_OK) return result;

            if(header.flags & JARC_FLAG_COMPRESSED)
            {
                result = jarcBinaryStream_read7BitEncodedU(this._archiveStream, &header.compressedSize);
                if(result != JARC_OK) return result;

                const bytesRead = jarcBinaryStream_readBytes(
                    this._archiveStream,
                    header.lzmaHeader.ptr,
                    null,
                    header.lzmaHeader.length
                );
                if(bytesRead != header.lzmaHeader.length) return JARC_EOF;
            }

            result = jarcBinaryStream_read7BitEncodedU(this._archiveStream, &header.attributeSize);
            if(result != JARC_OK) return result;

            // Memory model: JarcReader owns the memory for all chunk header names, so once
            //               a JarcReader is freed, all chunk headers become invalidated.
            //
            //               For type names, we store it into a temporary buffer, then swap it over
            //               to the user's provided pointer for that type name, so we don't have to manage another
            //               set of strings.
            if(this._namesRead >= this._names.length)
                return JARC_BAD_DATA; // Chunk headers should only be read once, so this indicates the chunk count is wrong.

            ulong nameLength;
            result = jarcBinaryStream_read7BitEncodedU(this._archiveStream, &nameLength);
            if(result != JARC_OK) return result;
            version(x86) if(nameLength > uint.max) return JARC_OOM;

            auto name = allocArray!char(nameLength);
            if(name is null) return JARC_OOM;
            this._names[this._namesRead++] = name;

            auto bytesRead = jarcBinaryStream_readBytes(this._archiveStream, cast(ubyte*)name.ptr, null, nameLength);
            if(bytesRead != nameLength) return JARC_EOF; // Name is freed up in the dtor.

            header.name = name.ptr;
            header.nameLength = nameLength;

            ulong typeLength;
            result = jarcBinaryStream_read7BitEncodedU(this._archiveStream, &typeLength);
            if(result != JARC_OK) return result;
            version(x86) if(typeLength > uint.max) return JARC_OOM;
        
            // typeLength being too high isn't an error - it just means we don't have a handler for it.
            if(typeLength <= this._typeBuffer.length)
            {
                bytesRead = jarcBinaryStream_readBytes(this._archiveStream, cast(ubyte*)this._typeBuffer.ptr, null, typeLength);
                if(bytesRead != typeLength) return JARC_EOF;

                // If we end up leaving the type null, it *also* means we just don't have the handler for it. Again, not an error.
                foreach(handler; this._handlers)
                {
                    if(handler.typeName[0..handler.typeNameLength] == this._typeBuffer[0..typeLength])
                    {
                        header.type = handler.typeName;
                        header.typeLength = typeLength;
                        break;
                    }
                }
            }

            header.ptrAttributeStart = jarcBinaryStream_getCursor(this._archiveStream);
            header.ptrDataStart      = cast(c_long)(header.ptrAttributeStart + header.attributeSize);
            return JARC_OK;
        }

        void setupTypeBuffer()
        {
            import std.algorithm : maxElement, map;

            const largestTypeName = this._handlers.map!(h => h.typeNameLength).maxElement;
            this._typeBuffer = allocArray!char(largestTypeName);
            assert(this._typeBuffer !is null);
        }

        ubyte[] getTempBuffer(size_t length)
        {
            const origLength = length;
            if(length > this._chunkDataBuffer.length)
            {
                if(length < 4096)
                    length = 4096;

                resizeArray!ubyte(this._chunkDataBuffer, length);
            }

            return this._chunkDataBuffer[0..origLength];
        }
    }

    @nogc nothrow
    public
    {
        @disable
        this(this){}

        this(JarcBinaryStream* stream, JarcChunkHandler[] handlers)
        {
            assert(stream !is null);
            this._archiveStream = stream;
            this._handlers = handlers;
            this.setupTypeBuffer();
        }

        ~this()
        {
            if(this._archiveStream !is null)
                jarcBinaryStream_free(this._archiveStream);

            if(this._typeBuffer !is null)
                free(this._typeBuffer);

            if(this._names !is null)
            {
                foreach(name; this._names)
                {
                    if(name !is null)
                        free(name);
                }
                free(this._names);
            }

            if(this._chunkHeaders !is null)
                free(this._chunkHeaders);

            if(this._chunkDataBuffer !is null)
                free(this._chunkDataBuffer);
        }
    }
}

JarcResult jarcReader_openBorrowedMemory(
    JarcReader** reader, 
    JarcChunkHandler* handlers, size_t handlerCount, 
    ubyte* bytes, size_t byteCount
)
{
    *reader = alloc!JarcReader(
        jarcBinaryStream_openBorrowedMemory(JARC_READ, bytes, byteCount),
        handlers[0..handlerCount]
    );
    return (*reader).readHeader();
}

void jarcReader_free(JarcReader* reader)
{
    free!JarcReader(reader);
}

JarcChunkHandler* jarcReader_getHandlerForType(JarcReader* reader, const char* chunkType, size_t chunkTypeLength)
{
    import std.algorithm : countUntil;

    const type = chunkType[0..chunkTypeLength];
    foreach(ref handler; reader._handlers)
    {
        if(handler.typeName[0..handler.typeNameLength] == type)
            return &handler;
    }

    return null;
}

void jarcReader_getChunkHeaders(JarcReader* reader, const(JarcChunkHeader)** headers, size_t* headersCount)
{
    *headers = reader._chunkHeaders.ptr;
    *headersCount = reader._chunkHeaders.length;
}

JarcResult jarcReader_readChunkByHeader(JarcReader* reader, const(JarcChunkHeader) header, void* userDataDest)
{
    import std.algorithm : max;

    if(header.type is null)
        return JARC_NO_HANDLER;

    auto handler = jarcReader_getHandlerForType(reader, header.type, header.typeLength);
    if(handler is null)
        return JARC_NO_HANDLER;

    auto result = jarcBinaryStream_setCursor(reader._archiveStream, header.ptrAttributeStart);
    if(result != JARC_OK) 
        return result;

    auto buffer = reader.getTempBuffer(header.attributeSize);
    if(buffer is null)
        return JARC_OOM;

    auto bytesRead = jarcBinaryStream_readBytes(reader._archiveStream, buffer.ptr, null, header.attributeSize);
    if(bytesRead != header.attributeSize)
        return JARC_EOF;

    auto attribReader = jarcBinaryStream_openBorrowedMemory(JARC_READ, buffer.ptr, buffer.length);
    if(attribReader is null)
        return JARC_OOM;

    result = handler.funcReadAttributes(attribReader, userDataDest);
    jarcBinaryStream_free(attribReader);
    if(result != JARC_OK)
        return result;

    const sizeInArchive = (header.flags & JARC_FLAG_COMPRESSED)
    ? header.compressedSize
    : header.uncompressedSize;

    const largestSize = max(header.compressedSize, header.uncompressedSize);

    result = jarcBinaryStream_setCursor(reader._archiveStream, header.ptrDataStart);
    if(result != JARC_OK)
        return result;

    buffer = reader.getTempBuffer(largestSize * 2); // First half will store uncompressed, second stores compressed.
    if(buffer is null)
        return JARC_OOM;
    
    bytesRead = jarcBinaryStream_readBytes(reader._archiveStream, &buffer[largestSize], null, sizeInArchive);
    if(bytesRead != sizeInArchive)
        return JARC_EOF;

    if(header.flags & JARC_FLAG_COMPRESSED)
    {
        import jarchive.lzma;

        auto srcLength = cast()header.compressedSize;
        auto dstLength = cast()header.uncompressedSize;

        ELzmaStatus status;
        const lzmaResult = LzmaDecode(
            buffer.ptr, &dstLength,
            &buffer[largestSize], &srcLength,
            header.lzmaHeader.ptr, header.lzmaHeader.length,
            LZMA_FINISH_END,
            &status,
            &g_defaultLzmaAlloc
        );

        if(lzmaResult != SZ_OK)
            return JARC_UNKNOWN_ERROR;

        buffer = buffer[0..dstLength];
    }
    else
        buffer = buffer[largestSize..$]; // Use the "compressed" section as uncompressed, since that's what it's storing in this case.

    auto bodyReader = jarcBinaryStream_openBorrowedMemory(JARC_READ, buffer.ptr, buffer.length);
    if(bodyReader is null)
        return JARC_OOM;

    result = handler.funcReadBody(bodyReader, userDataDest);
    jarcBinaryStream_free(bodyReader);
    if(result != JARC_OK)
        return result;

    return JARC_OK;
}

unittest
{
    struct Test
    {
        bool isBoob;
        string str;
    }

    JarcChunkHandler handler;
    handler.typeName = "test";
    handler.typeNameLength = 4;
    handler.funcWriteAttributes = (stream, userData)
    {
        const test = *(cast(Test*)userData);
        return jarcBinaryStream_writeU8(stream, cast(ubyte)test.isBoob);
    };
    handler.funcWriteBody = (stream, userData)
    {
        const test = *(cast(Test*)userData);
        return jarcBinaryStream_writeString(stream, test.str.ptr, test.str.length);
    };
    handler.funcReadAttributes = (stream, userData)
    {
        auto test = (cast(Test*)userData);
        const result = jarcBinaryStream_readU8(stream, cast(ubyte*)&test.isBoob);
        return result;
    };
    handler.funcReadBody = (stream, userData)
    {
        auto test = (cast(Test*)userData);
        
        char* text;
        size_t length;
        const result = jarcBinaryStream_readMallocedString(stream, &text, &length);
        if(result != JARC_OK) return result;

        // Don't do this! I need to do it since I can't access the GC here.
        test.str = cast(string)text[0..length];
        return JARC_OK;
    };

    JarcChunkHandler[1] handlers = [handler];

    JarcWriter* writer;
    auto result = jarcWriter_openNewMemory(&writer, handlers.ptr, handlers.length);
    scope(exit) jarcWriter_free(writer);

    Test entry1 = Test(true, "Speedlings");
    result = jarcWriter_writeChunk(writer, "test", 4, "entry1", 6, &entry1, JARC_FLAG_NONE);
    assert(result == JARC_OK);

    Test entry2 = Test(false, "Slowlings");
    result = jarcWriter_writeChunk(writer, "test", 4, "entry2", 6, &entry2, JARC_FLAG_COMPRESSED);
    assert(result == JARC_OK);

    ubyte* borrowedMemory;
    size_t memoryLength;
    jarcWriter_finalise(writer);
    jarcWriter_getMemory(writer, &borrowedMemory, &memoryLength);

    import core.stdc.stdio : fopen, fwrite, fclose;
    auto file = fopen("debug_reader.bin", "w");
    fwrite(borrowedMemory, memoryLength, 1, file);
    fclose(file);

    JarcReader* reader;
    result = jarcReader_openBorrowedMemory(&reader, handlers.ptr, handlers.length, borrowedMemory, memoryLength);
    assert(result == JARC_OK);
    scope(exit) jarcReader_free(reader);

    const(JarcChunkHeader)* headers;
    size_t headerCount;
    jarcReader_getChunkHeaders(reader, &headers, &headerCount);
    assert(headerCount == 2);

    JarcChunkHeader h = *headers;
    assert(h.nameLength == 6);
    assert(h.name[0..6] == "entry1");
    assert(h.typeLength == 4);
    assert(h.type[0..4] == "test");
    assert(h.type is handlers[0].typeName);
    assert(h.attributeSize == 1);
    assert(h.compressedSize == 0);
    assert(h.flags == JARC_FLAG_NONE);
    assert(h.uncompressedSize == 11); // "Speedlings".length + 1 for length byte.
    assert(h.ptrAttributeStart == 0x1C);
    assert(h.ptrDataStart == 0x1D);

    h = headers[1];
    assert(h.nameLength == 6);
    assert(h.name[0..6] == "entry2");
    assert(h.typeLength == 4);
    assert(h.type[0..4] == "test");
    assert(h.type is handlers[0].typeName);
    assert(h.attributeSize == 1);
    assert(h.compressedSize == 15);
    assert(h.flags == JARC_FLAG_COMPRESSED);
    assert(h.uncompressedSize == 10); // "Slowlings".length + 1 for length byte.
    assert(h.ptrAttributeStart == 0x3E);
    assert(h.ptrDataStart == 0x3F);
    assert(h.lzmaHeader != headers[0].lzmaHeader);

    Test t;
    assert(jarcReader_readChunkByHeader(reader, headers[0], &t) == JARC_OK);
    assert(t.isBoob);
    assert(t.str.length == 10);
    assert(t.str == "Speedlings");
    auto tStrSlice = cast(char[])t.str;
    free(tStrSlice); // Again, don't. Do. This! It's just because I can't do a GC copy here.
    
    assert(jarcReader_readChunkByHeader(reader, headers[1], &t) == JARC_OK);
    assert(!t.isBoob);
    assert(t.str.length == 9);
    assert(t.str == "Slowlings");
    tStrSlice = cast(char[])t.str;
    free(tStrSlice);
}