project('jarchive', 'c', 'd', version: '0.1', default_options: ['warning_level=3'])

lzma_src = [
    'extern/lzma/7zTypes.h',
    'extern/lzma/LzmaDec.h',
    'extern/lzma/LzmaDec.c',
    'extern/lzma/Lzma2Dec.h',
    'extern/lzma/Lzma2Dec.c',
    'extern/lzma/LzmaEnc.h',
    'extern/lzma/LzmaEnc.c',
    'extern/lzma/Lzma2Enc.h',
    'extern/lzma/Lzma2Enc.c',
    'extern/lzma/LzFind.h',
    'extern/lzma/LzFind.c',
    'extern/lzma/LzFindMt.h',
    'extern/lzma/LzFindMt.c',
    'extern/lzma/Threads.h',
    'extern/lzma/Threads.c',
    'extern/lzma/MtCoder.h',
    'extern/lzma/MtCoder.c',
    'extern/lzma/MtDec.h',
    'extern/lzma/MtDec.c',
]

jarchive_src = [
    'source/jarchive/package.d',
    'source/jarchive/writer.d',
    'source/jarchive/binarystream.d',
    'source/jarchive/memory.d',
    'source/jarchive/enums.d',
    'source/jarchive/chunkhandler.d',
]

all_d_src = jarchive_src

d_include = include_directories('source/', 'extern/')

lzma     = library('lzma', lzma_src)
jarchive = library('jarchive', all_d_src, link_with: [lzma], include_directories: [d_include], d_args: ['--betterC'])

test('basic', executable('jarchive-tests', all_d_src + ['test.d'], link_with: [lzma], include_directories: [d_include], d_unittest: true))