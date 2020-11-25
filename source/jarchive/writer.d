module jarchive.writer;

import core.stdc.config;
import jarchive;

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

    result = jarcBinaryStream_writeU32(writer._archiveStream, 0); // TODO
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

    JarcResult freeAndReturn()
    {
        jarcBinaryStream_free(attributeWriter);
        jarcBinaryStream_free(bodyWriter);
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
    size_t bodyLength;
    size_t compressedBodyLength;
    result = jarcBinaryStream_getMemory(bodyWriter, &bodyData, &bodyLength);
    if(result != JARC_OK) return freeAndReturn();

    if(flags & JARC_FLAG_COMPRESSED)
        assert(false, "TODO");

    result = jarcBinaryStream_writeU16(writer._archiveStream, flags);
    if(result != JARC_OK) return freeAndReturn();

    result = jarcBinaryStream_write7BitEncodedU(writer._archiveStream, bodyLength);
    if(result != JARC_OK) return freeAndReturn();

    if(flags & JARC_FLAG_COMPRESSED)
    {
        result = jarcBinaryStream_write7BitEncodedU(writer._archiveStream, compressedBodyLength);
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
        JARC_FLAG_NONE//JARC_FLAG_COMPRESSED
    );

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
        0, 0, 0, 0,
        0, 0, 0, 2,
        
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
                     'f', 'o', 'r', ' ', 'a', 'l', 'l', ' ', 'f', 'l', 'o', 'r', 'b', 's', '.'
    ];
    assert(slice == expected);
}