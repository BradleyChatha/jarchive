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

src = [
    'source/jarchive/package.d'
]

lzma     = library('lzma', lzma_src)
jarchive = library('jarchive', src, link_with: lzma)

test('basic', executable('jarchive-tests', src + ['test.d'], d_unittest: true))