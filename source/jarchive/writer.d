module jarchive.writer;

import core.stdc.config;
import jarchive, jarchive.lzma;

extern(C) @nogc nothrow:

struct JarcWriter
{
    static immutable MAGIC_NUMBER = ['j', 'r', 'c'];

    @nogc
    private nothrow
    {
        JarcBinaryStream*  _archiveStream;
        JarcChunkHandler[] _handlers;
        uint               _chunkCount;
        c_long             _ptrCrc;
        c_long             _ptrChunkCount;
        c_long             _ptrChunkStart;

        JarcResult setup()
        {
            return this.writeHeader();
        }

        JarcResult writeHeader()
        {
            JarcResult result;

            result = jarcBinaryStream_writeBytes(this._archiveStream, cast(ubyte*)MAGIC_NUMBER.ptr, cast(ulong)MAGIC_NUMBER.length);
            if(result != JARC_OK) return result;

            result = jarcBinaryStream_writeU8(this._archiveStream, JARC_VERSION_LATEST);
            if(result != JARC_OK) return result;

            this._ptrCrc = jarcBinaryStream_getCursor(this._archiveStream);

            result = jarcBinaryStream_writeU32(this._archiveStream, 0);
            if(result != JARC_OK) return result;

            this._ptrChunkCount = jarcBinaryStream_getCursor(this._archiveStream);

            result = jarcBinaryStream_writeU32(this._archiveStream, 0);
            if(result != JARC_OK) return result;

            this._ptrChunkStart = jarcBinaryStream_getCursor(this._archiveStream);

            return JARC_OK;
        }
    }

    @nogc
    public nothrow
    {
        @disable
        this(this){}

        this(JarcBinaryStream* stream, JarcChunkHandler[] handlers)
        {
            assert(stream !is null);
            this._archiveStream = stream;
            this._handlers = handlers;
        }

        ~this()
        {
            if(this._archiveStream !is null)
                jarcBinaryStream_free(this._archiveStream);
        }
    }
}

JarcResult jarcWriter_openMemory(JarcWriter** writer, JarcChunkHandler* handlers, size_t handlerCount)
{
    *writer = alloc!JarcWriter(
        jarcBinaryStream_openNewMemory(JARC_READ_WRITE),
        handlers[0..handlerCount]
    );
    return (*writer).setup();
}

JarcResult jarcWriter_finalise(JarcWriter* writer)
{
    auto result = jarcBinaryStream_setCursor(writer._archiveStream, writer._ptrCrc);
    if(result != JARC_OK) return result;

    const crc = jarcBinaryStream_calculateCrc(writer._archiveStream, writer._ptrChunkStart);
    result = jarcBinaryStream_writeBytes(writer._archiveStream, crc.ptr, crc.length);
    if(result != JARC_OK) return result;

    result = jarcBinaryStream_setCursor(writer._archiveStream, writer._ptrChunkCount);
    if(result != JARC_OK) return result;

    result = jarcBinaryStream_writeU32(writer._archiveStream, writer._chunkCount);
    if(result != JARC_OK) return result;

    return JARC_OK;
}

void jarcWriter_free(JarcWriter* writer)
{
    free!JarcWriter(writer);
}

JarcResult jarcWriter_getMemory(
    JarcWriter* writer,
    scope ubyte** bytesPtr,
    scope size_t* lengthPtr
)
{
    return jarcBinaryStream_getMemory(writer._archiveStream, bytesPtr, lengthPtr);
}

JarcChunkHandler* jarcWriter_getHandlerForType(JarcWriter* writer, const char* chunkType, size_t chunkTypeLength)
{
    import std.algorithm : countUntil;

    const type = chunkType[0..chunkTypeLength];
    foreach(ref handler; writer._handlers)
    {
        if(handler.typeName[0..handler.typeNameLength] == type)
            return &handler;
    }

    return null;
}

JarcResult jarcWriter_writeChunk(
    JarcWriter* writer, 
    const char* chunkType, size_t chunkTypeLength,
    const char* name,      size_t nameLength,
    void* userData, 
    JarcFlags flags
)
{
    JarcResult result;
    writer._chunkCount++;

    const handler = jarcWriter_getHandlerForType(writer, chunkType, chunkTypeLength);
    if(handler is null) return JARC_NO_HANDLER;

    scope attributeWriter = jarcBinaryStream_openNewMemory(JARC_READ_WRITE);
    scope bodyWriter      = jarcBinaryStream_openNewMemory(JARC_READ_WRITE);
    ubyte[] compressedData;

    JarcResult freeAndReturn()
    {
        jarcBinaryStream_free(attributeWriter);
        jarcBinaryStream_free(bodyWriter);

        if(compressedData !is null)
            free(compressedData);

        return result;
    }

    result = handler.funcWriteAttributes(attributeWriter, userData);
    if(result != JARC_OK) return freeAndReturn();

    result = handler.funcWriteBody(bodyWriter, userData);
    if(result != JARC_OK) return freeAndReturn();

    ubyte* attributeData;
    size_t attributeLength;
    result = jarcBinaryStream_getMemory(attributeWriter, &attributeData, &attributeLength);
    if(result != JARC_OK) return freeAndReturn();

    ubyte* bodyData;
    size_t uncompressedBodyLength;
    size_t compressedBodyLength;
    result = jarcBinaryStream_getMemory(bodyWriter, &bodyData, &uncompressedBodyLength);
    if(result != JARC_OK) return freeAndReturn();

    size_t bodyLength;
    ubyte[5] lzmaProps;
    size_t lzmaPropsLength = 5;
    if(flags & JARC_FLAG_COMPRESSED)
    {
        import std.algorithm : min, max;
        const dictSize   = max(1, uncompressedBodyLength / 4);
        auto  bufferSize = dictSize + uncompressedBodyLength + (uncompressedBodyLength / 3);

        while(true)
        {
            CLzmaEncProps props;
            LzmaEncProps_Init(&props);
            props.dictSize = cast(uint)min(1024 * 1024 * 128, dictSize);

            compressedData = allocArray!ubyte(bufferSize);
            size_t compressedLength = compressedData.length;

            const lzmaResult = LzmaEncode(
                compressedData.ptr, &compressedLength,
                bodyData, uncompressedBodyLength,
                &props, lzmaProps.ptr, &lzmaPropsLength,
                0,
                &g_defaultLzmaProgress,
                &g_defaultLzmaAlloc,
                &g_defaultLzmaAlloc
            );

            import core.stdc.stdio;
            debug(lzma) printf("LzmaEncode returned: %d\n", lzmaResult);

            if(lzmaResult == SZ_ERROR_OUTPUT_EOF)
            {
                bufferSize += (uncompressedBodyLength / 3);
                free(compressedData);
                continue;
            }
            else if(lzmaResult != SZ_OK)
            {
                result = JARC_UNKNOWN_ERROR;
                return freeAndReturn();
            }

            assert(lzmaPropsLength == 5);
            bodyData = compressedData.ptr;
            bodyLength = compressedLength;
            compressedBodyLength = compressedLength;
            break;
        }
    }
    else
        bodyLength = uncompressedBodyLength;

    result = jarcBinaryStream_writeU16(writer._archiveStream, flags);
    if(result != JARC_OK) return freeAndReturn();

    result = jarcBinaryStream_write7BitEncodedU(writer._archiveStream, uncompressedBodyLength);
    if(result != JARC_OK) return freeAndReturn();

    if(flags & JARC_FLAG_COMPRESSED)
    {
        result = jarcBinaryStream_write7BitEncodedU(writer._archiveStream, compressedBodyLength);
        if(result != JARC_OK) return freeAndReturn();

        result = jarcBinaryStream_writeBytes(writer._archiveStream, lzmaProps.ptr, lzmaPropsLength);
        if(result != JARC_OK) return freeAndReturn();
    }

    result = jarcBinaryStream_write7BitEncodedU(writer._archiveStream, attributeLength);
    if(result != JARC_OK) return freeAndReturn();

    result = jarcBinaryStream_writeString(writer._archiveStream, name, nameLength);
    if(result != JARC_OK) return freeAndReturn();

    result = jarcBinaryStream_writeString(writer._archiveStream, handler.typeName, handler.typeNameLength);
    if(result != JARC_OK) return freeAndReturn();

    result = jarcBinaryStream_writeBytes(writer._archiveStream, attributeData, attributeLength);
    if(result != JARC_OK) return freeAndReturn();
    
    result = jarcBinaryStream_writeBytes(writer._archiveStream, bodyData, bodyLength);
    if(result != JARC_OK) return freeAndReturn();

    result = JARC_OK;
    return freeAndReturn();
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
        const test = *(cast(Test*) userData);
        return jarcBinaryStream_writeString(stream, test.str.ptr, test.str.length);
    };

    JarcChunkHandler[1] handlers = [handler];

    JarcWriter* writer;
    auto result = jarcWriter_openMemory(&writer, handlers.ptr, handlers.length);
    scope(exit) jarcWriter_free(writer);
    assert(writer !is null);
    assert(result == JARC_OK);

    auto entry1 = Test(true, "Lol");
    result = jarcWriter_writeChunk(
        writer, 
        "test", 4, 
        "entry1", 6, 
        &entry1,
        JARC_FLAG_NONE
    );
    assert(result == JARC_OK);

    auto entry2 = Test(false, "This is a message for all florbs.");
    result = jarcWriter_writeChunk(
        writer,
        "test", 4,
        "entry2", 6,
        &entry2,
        JARC_FLAG_NONE
    );
    assert(result == JARC_OK);

    // Normally compression should only be used for large blobs of data, not these super tiny ones.
    auto entry3 = Test(true, "This is an LZMA compressed entry.");
    result = jarcWriter_writeChunk(
        writer,
        "test", 4,
        "entry3", 6,
        &entry3,
        JARC_FLAG_COMPRESSED
    );
    assert(result == JARC_OK, "Compression failed");

    assert(jarcWriter_finalise(writer) == JARC_OK);

    ubyte* bytes;
    size_t length;
    result = jarcWriter_getMemory(writer, &bytes, &length);
    assert(result == JARC_OK);
    assert(bytes !is null);
    assert(length > 0);

    ubyte[] slice = bytes[0..length];

    import core.stdc.stdio;
    auto file = fopen("debug.bin", "w");
    scope(exit) fclose(file);
    fwrite(slice.ptr, 1, slice.length, file);

    static ubyte[] expected = [
        'j', 'r', 'c',
        JARC_VERSION_LATEST,
        0xB9, 0xC1, 0xDD, 0x88,
        0, 0, 0, 3,
        
        0, 0,
        0b1000_0100,
        0b1000_0001,
        0b1000_0110, 'e', 'n', 't', 'r', 'y', '1',
        0b1000_0100, 't', 'e', 's', 't',
        1,
        0b1000_0011, 'L', 'o', 'l',

        0, 0,
        0b1010_0010,
        0b1000_0001,
        0b1000_0110, 'e', 'n', 't', 'r', 'y', '2',
        0b1000_0100, 't', 'e', 's', 't',
        0,
        0b1010_0001, 'T', 'h', 'i', 's', ' ', 'i', 's', ' ', 'a', ' ', 'm', 'e', 's', 's', 'a', 'g', 'e', ' ',
                     'f', 'o', 'r', ' ', 'a', 'l', 'l', ' ', 'f', 'l', 'o', 'r', 'b', 's', '.',

        0, JARC_FLAG_COMPRESSED,
        0b1010_0010,
        0b1010_0110,         // Again, you'd use compression on larger data blobs, because small ones like this actually make it *larger*.
        0x5D, 0, 0x10, 0, 0, // LZMA header, not sure what it means but, this is the output.
        0b1000_0001,
        0b1000_0110, 'e', 'n', 't', 'r', 'y', '3',
        0b1000_0100, 't', 'e', 's', 't',
        // Compressed data is ignored as I can't hand-replicate it easily, so it is assumed to be correct.
    ];
    assert(slice.length >= expected.length);
    
    const areSame = (slice[0..expected.length] == expected);
    if(!areSame)
    {
        import core.stdc.stdio;

        foreach(i; 0..expected.length)
            printf("%X: %X == %X\n", cast(uint)i, cast(uint)expected[i], cast(uint)slice[i]);

        assert(false);
    }
}