module jarchive.chunkhandler;

import jarchive;

extern(C) @nogc nothrow:

alias ChunkHandlerWriteAttributes = JarcResult function(JarcBinaryStream* stream, void* userData);
alias ChunkHandlerWriteBody       = JarcResult function(JarcBinaryStream* stream, void* userData);
alias ChunkHandlerReadAttributes  = JarcResult function(JarcBinaryStream* stream, void* userData);
alias ChunkHandlerReadBody        = JarcResult function(JarcBinaryStream* stream, void* userData);

struct JarcChunkHandler
{
    const(char)* typeName;
    size_t typeNameLength;
    ChunkHandlerReadAttributes funcReadAttributes;
    ChunkHandlerReadBody funcReadBody;
    ChunkHandlerWriteAttributes funcWriteAttributes;
    ChunkHandlerWriteBody funcWriteBody;
}