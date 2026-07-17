/* zconf.h -- configuration of the zlib compression library
 * Copyright (C) 1995-2026 Jean-loup Gailly, Mark Adler
 * For conditions of distribution and use, see copyright notice in zlib.h
 */

/* @(#) $Id$ */

#ifndef NIOEXTRAS_ZCONF_H
#define NIOEXTRAS_ZCONF_H

/*
 * If you *really* need a unique prefix for all types and library functions,
 * compile with -DZ_PREFIX. The "standard" zlib should be compiled without it.
 * Even better than compiling with -DZ_PREFIX would be to use configure to set
 * this permanently in zconf.h using "./configure --zprefix".
 */
#if 1 /* CNIOEXTRAS_Z_PREFIX - cnioextras_z_ */
#  define CNIOEXTRAS_Z_PREFIX_SET

/* all linked symbols and init macros */
#  define _dist_code            cnioextras_z__dist_code
#  define _length_code          cnioextras_z__length_code
#  define _tr_align             cnioextras_z__tr_align
#  define _tr_flush_bits        cnioextras_z__tr_flush_bits
#  define _tr_flush_block       cnioextras_z__tr_flush_block
#  define _tr_init              cnioextras_z__tr_init
#  define _tr_stored_block      cnioextras_z__tr_stored_block
#  define _tr_tally             cnioextras_z__tr_tally
#  define adler32               cnioextras_z_adler32
#  define adler32_combine       cnioextras_z_adler32_combine
#  define adler32_combine64     cnioextras_z_adler32_combine64
#  define adler32_z             cnioextras_z_adler32_z
#  ifndef CNIOEXTRAS_Z_SOLO
#    define compress              cnioextras_z_compress
#    define compress2             cnioextras_z_compress2
#    define compress_z            cnioextras_z_compress_z
#    define compress2_z           cnioextras_z_compress2_z
#    define compressBound         cnioextras_z_compressBound
#    define compressBound_z       cnioextras_z_compressBound_z
#  endif
#  define crc32                 cnioextras_z_crc32
#  define crc32_combine         cnioextras_z_crc32_combine
#  define crc32_combine64       cnioextras_z_crc32_combine64
#  define crc32_combine_gen     cnioextras_z_crc32_combine_gen
#  define crc32_combine_gen64   cnioextras_z_crc32_combine_gen64
#  define crc32_combine_op      cnioextras_z_crc32_combine_op
#  define crc32_z               cnioextras_z_crc32_z
#  define deflate               cnioextras_z_deflate
#  define deflateBound          cnioextras_z_deflateBound
#  define deflateBound_z        cnioextras_z_deflateBound_z
#  define deflateCopy           cnioextras_z_deflateCopy
#  define deflateEnd            cnioextras_z_deflateEnd
#  define deflateGetDictionary  cnioextras_z_deflateGetDictionary
#  define deflateInit           cnioextras_z_deflateInit
#  define deflateInit2          cnioextras_z_deflateInit2
#  define deflateInit2_         cnioextras_z_deflateInit2_
#  define deflateInit_          cnioextras_z_deflateInit_
#  define deflateParams         cnioextras_z_deflateParams
#  define deflatePending        cnioextras_z_deflatePending
#  define deflatePrime          cnioextras_z_deflatePrime
#  define deflateReset          cnioextras_z_deflateReset
#  define deflateResetKeep      cnioextras_z_deflateResetKeep
#  define deflateSetDictionary  cnioextras_z_deflateSetDictionary
#  define deflateSetHeader      cnioextras_z_deflateSetHeader
#  define deflateTune           cnioextras_z_deflateTune
#  define deflateUsed           cnioextras_z_deflateUsed
#  define deflate_copyright     cnioextras_z_deflate_copyright
#  define get_crc_table         cnioextras_z_get_crc_table
#  ifndef CNIOEXTRAS_Z_SOLO
#    define gz_error              cnioextras_z_gz_error
#    define gz_intmax             cnioextras_z_gz_intmax
#    define gz_strwinerror        cnioextras_z_gz_strwinerror
#    define gzbuffer              cnioextras_z_gzbuffer
#    define gzclearerr            cnioextras_z_gzclearerr
#    define gzclose               cnioextras_z_gzclose
#    define gzclose_r             cnioextras_z_gzclose_r
#    define gzclose_w             cnioextras_z_gzclose_w
#    define gzdirect              cnioextras_z_gzdirect
#    define gzdopen               cnioextras_z_gzdopen
#    define gzeof                 cnioextras_z_gzeof
#    define gzerror               cnioextras_z_gzerror
#    define gzflush               cnioextras_z_gzflush
#    define gzfread               cnioextras_z_gzfread
#    define gzfwrite              cnioextras_z_gzfwrite
#    define gzgetc                cnioextras_z_gzgetc
#    define gzgetc_               cnioextras_z_gzgetc_
#    define gzgets                cnioextras_z_gzgets
#    define gzoffset              cnioextras_z_gzoffset
#    define gzoffset64            cnioextras_z_gzoffset64
#    define gzopen                cnioextras_z_gzopen
#    define gzopen64              cnioextras_z_gzopen64
#    ifdef _WIN32
#      define gzopen_w              cnioextras_z_gzopen_w
#    endif
#    define gzprintf              cnioextras_z_gzprintf
#    define gzputc                cnioextras_z_gzputc
#    define gzputs                cnioextras_z_gzputs
#    define gzread                cnioextras_z_gzread
#    define gzrewind              cnioextras_z_gzrewind
#    define gzseek                cnioextras_z_gzseek
#    define gzseek64              cnioextras_z_gzseek64
#    define gzsetparams           cnioextras_z_gzsetparams
#    define gztell                cnioextras_z_gztell
#    define gztell64              cnioextras_z_gztell64
#    define gzungetc              cnioextras_z_gzungetc
#    define gzvprintf             cnioextras_z_gzvprintf
#    define gzwrite               cnioextras_z_gzwrite
#  endif
#  define inflate               cnioextras_z_inflate
#  define inflateBack           cnioextras_z_inflateBack
#  define inflateBackEnd        cnioextras_z_inflateBackEnd
#  define inflateBackInit       cnioextras_z_inflateBackInit
#  define inflateBackInit_      cnioextras_z_inflateBackInit_
#  define inflateCodesUsed      cnioextras_z_inflateCodesUsed
#  define inflateCopy           cnioextras_z_inflateCopy
#  define inflateEnd            cnioextras_z_inflateEnd
#  define inflateGetDictionary  cnioextras_z_inflateGetDictionary
#  define inflateGetHeader      cnioextras_z_inflateGetHeader
#  define inflateInit           cnioextras_z_inflateInit
#  define inflateInit2          cnioextras_z_inflateInit2
#  define inflateInit2_         cnioextras_z_inflateInit2_
#  define inflateInit_          cnioextras_z_inflateInit_
#  define inflateMark           cnioextras_z_inflateMark
#  define inflatePrime          cnioextras_z_inflatePrime
#  define inflateReset          cnioextras_z_inflateReset
#  define inflateReset2         cnioextras_z_inflateReset2
#  define inflateResetKeep      cnioextras_z_inflateResetKeep
#  define inflateSetDictionary  cnioextras_z_inflateSetDictionary
#  define inflateSync           cnioextras_z_inflateSync
#  define inflateSyncPoint      cnioextras_z_inflateSyncPoint
#  define inflateUndermine      cnioextras_z_inflateUndermine
#  define inflateValidate       cnioextras_z_inflateValidate
#  define inflate_copyright     cnioextras_z_inflate_copyright
#  define inflate_fast          cnioextras_z_inflate_fast
#  define inflate_table         cnioextras_z_inflate_table
#  define inflate_fixed         cnioextras_z_inflate_fixed
#  ifndef CNIOEXTRAS_Z_SOLO
#    define uncompress            cnioextras_z_uncompress
#    define uncompress2           cnioextras_z_uncompress2
#    define uncompress_z          cnioextras_z_uncompress_z
#    define uncompress2_z         cnioextras_z_uncompress2_z
#  endif
#  define zError                cnioextras_z_zError
#  ifndef CNIOEXTRAS_Z_SOLO
#    define zcalloc               cnioextras_z_zcalloc
#    define zcfree                cnioextras_z_zcfree
#  endif
#  define zlibCompileFlags      cnioextras_z_zlibCompileFlags
#  define zlibVersion           cnioextras_z_zlibVersion

/* all zlib typedefs in zlib.h and zconf.h */
#  define Byte                  cnioextras_z_Byte
#  define Bytef                 cnioextras_z_Bytef
#  define alloc_func            cnioextras_z_alloc_func
#  define charf                 cnioextras_z_charf
#  define free_func             cnioextras_z_free_func
#  ifndef CNIOEXTRAS_Z_SOLO
#    define gzFile                cnioextras_z_gzFile
#  endif
#  define gz_header             cnioextras_z_gz_header
#  define gz_headerp            cnioextras_z_gz_headerp
#  define in_func               cnioextras_z_in_func
#  define intf                  cnioextras_z_intf
#  define out_func              cnioextras_z_out_func
#  define uInt                  cnioextras_z_uInt
#  define uIntf                 cnioextras_z_uIntf
#  define uLong                 cnioextras_z_uLong
#  define uLongf                cnioextras_z_uLongf
#  define voidp                 cnioextras_z_voidp
#  define voidpc                cnioextras_z_voidpc
#  define voidpf                cnioextras_z_voidpf

/* all zlib structs in zlib.h and zconf.h */
#  define gz_header_s           cnioextras_z_gz_header_s
#  define internal_state        cnioextras_z_internal_state

#endif

#if defined(__MSDOS__) && !defined(MSDOS)
#  define MSDOS
#endif
#if (defined(OS_2) || defined(__OS2__)) && !defined(OS2)
#  define OS2
#endif
#if defined(_WINDOWS) && !defined(WINDOWS)
#  define WINDOWS
#endif
#if defined(_WIN32) || defined(_WIN32_WCE) || defined(__WIN32__)
#  ifndef WIN32
#    define WIN32
#  endif
#endif
#if (defined(MSDOS) || defined(OS2) || defined(WINDOWS)) && !defined(WIN32)
#  if !defined(__GNUC__) && !defined(__FLAT__) && !defined(__386__)
#    ifndef SYS16BIT
#      define SYS16BIT
#    endif
#  endif
#endif

/*
 * Compile with -DMAXSEG_64K if the alloc function cannot allocate more
 * than 64k bytes at a time (needed on systems with 16-bit int).
 */
#ifdef SYS16BIT
#  define MAXSEG_64K
#endif
#ifdef MSDOS
#  define UNALIGNED_OK
#endif

#ifdef __STDC_VERSION__
#  ifndef STDC
#    define STDC
#  endif
#  if __STDC_VERSION__ >= 199901L
#    ifndef STDC99
#      define STDC99
#    endif
#  endif
#endif
#if !defined(STDC) && (defined(__STDC__) || defined(__cplusplus))
#  define STDC
#endif
#if !defined(STDC) && (defined(__GNUC__) || defined(__BORLANDC__))
#  define STDC
#endif
#if !defined(STDC) && (defined(MSDOS) || defined(WINDOWS) || defined(WIN32))
#  define STDC
#endif
#if !defined(STDC) && (defined(OS2) || defined(__HOS_AIX__))
#  define STDC
#endif

#if defined(__OS400__) && !defined(STDC)    /* iSeries (formerly AS/400). */
#  define STDC
#endif

#ifndef STDC
#  ifndef const /* cannot use !defined(STDC) && !defined(const) on Mac */
#    define const       /* note: need a more gentle solution here */
#  endif
#endif

#ifndef cnioextras_z_const
#  ifdef CNIOEXTRAS_ZLIB_CONST
#    define cnioextras_z_const const
#  else
#    define cnioextras_z_const
#  endif
#endif

#ifdef CNIOEXTRAS_Z_SOLO
#  ifdef _WIN64
     typedef unsigned long long cnioextras_z_size_t;
#  else
     typedef unsigned long cnioextras_z_size_t;
#  endif
#else
#  define cnioextras_z_longlong long long
#  if defined(NO_SIZE_T)
     typedef unsigned NO_SIZE_T cnioextras_z_size_t;
#  elif defined(STDC)
#    include <stddef.h>
     typedef size_t cnioextras_z_size_t;
#  else
     typedef unsigned long cnioextras_z_size_t;
#  endif
#  undef cnioextras_z_longlong
#endif

/* Maximum value for memLevel in deflateInit2 */
#ifndef MAX_MEM_LEVEL
#  ifdef MAXSEG_64K
#    define MAX_MEM_LEVEL 8
#  else
#    define MAX_MEM_LEVEL 9
#  endif
#endif

/* Maximum value for windowBits in deflateInit2 and inflateInit2.
 * WARNING: reducing MAX_WBITS makes minigzip unable to extract .gz files
 * created by gzip. (Files created by minigzip can still be extracted by
 * gzip.)
 */
#ifndef MAX_WBITS
#  define MAX_WBITS   15 /* 32K LZ77 window */
#endif

/* The memory requirements for deflate are (in bytes):
            (1 << (windowBits+2)) +  (1 << (memLevel+9))
 that is: 128K for windowBits=15  +  128K for memLevel = 8  (default values)
 plus a few kilobytes for small objects. For example, if you want to reduce
 the default memory requirements from 256K to 128K, compile with
     make CFLAGS="-O -DMAX_WBITS=14 -DMAX_MEM_LEVEL=7"
 Of course this will generally degrade compression (there's no free lunch).

   The memory requirements for inflate are (in bytes) 1 << windowBits
 that is, 32K for windowBits=15 (default value) plus about 7 kilobytes
 for small objects.
*/

                        /* Type declarations */

#ifndef OF /* function prototypes */
#  ifdef STDC
#    define OF(args)  args
#  else
#    define OF(args)  ()
#  endif
#endif

/* The following definitions for FAR are needed only for MSDOS mixed
 * model programming (small or medium model with some far allocations).
 * This was tested only with MSC; for other MSDOS compilers you may have
 * to define NO_MEMCPY in zutil.h.  If you don't need the mixed model,
 * just define FAR to be empty.
 */
#ifdef SYS16BIT
#  if defined(M_I86SM) || defined(M_I86MM)
     /* MSC small or medium model */
#    define SMALL_MEDIUM
#    ifdef _MSC_VER
#      define FAR _far
#    else
#      define FAR far
#    endif
#  endif
#  if (defined(__SMALL__) || defined(__MEDIUM__))
     /* Turbo C small or medium model */
#    define SMALL_MEDIUM
#    ifdef __BORLANDC__
#      define FAR _far
#    else
#      define FAR far
#    endif
#  endif
#endif

#if defined(WINDOWS) || defined(WIN32)
   /* If building or using zlib as a DLL, define CNIOEXTRAS_ZLIB_DLL.
    * This is not mandatory, but it offers a little performance increase.
    */
#  ifdef CNIOEXTRAS_ZLIB_DLL
#    if defined(WIN32) && (!defined(__BORLANDC__) || (__BORLANDC__ >= 0x500))
#      ifdef CNIOEXTRAS_ZLIB_INTERNAL
#        define ZEXTERN extern __declspec(dllexport)
#      else
#        define ZEXTERN extern __declspec(dllimport)
#      endif
#    endif
#  endif  /* CNIOEXTRAS_ZLIB_DLL */
   /* If building or using zlib with the WINAPI/WINAPIV calling convention,
    * define CNIOEXTRAS_ZLIB_WINAPI.
    * Caution: the standard ZLIB1.DLL is NOT compiled using CNIOEXTRAS_ZLIB_WINAPI.
    */
#  ifdef CNIOEXTRAS_ZLIB_WINAPI
#    ifdef FAR
#      undef FAR
#    endif
#    ifndef WIN32_LEAN_AND_MEAN
#      define WIN32_LEAN_AND_MEAN
#    endif
#    include <windows.h>
     /* No need for _export, use ZLIB.DEF instead. */
     /* For complete Windows compatibility, use WINAPI, not __stdcall. */
#    define ZEXPORT WINAPI
#    ifdef WIN32
#      define ZEXPORTVA WINAPIV
#    else
#      define ZEXPORTVA FAR CDECL
#    endif
#  endif
#endif

#if defined (__BEOS__)
#  ifdef CNIOEXTRAS_ZLIB_DLL
#    ifdef CNIOEXTRAS_ZLIB_INTERNAL
#      define ZEXPORT   __declspec(dllexport)
#      define ZEXPORTVA __declspec(dllexport)
#    else
#      define ZEXPORT   __declspec(dllimport)
#      define ZEXPORTVA __declspec(dllimport)
#    endif
#  endif
#endif

#ifndef ZEXTERN
#  define ZEXTERN extern
#endif
#ifndef ZEXPORT
#  define ZEXPORT
#endif
#ifndef ZEXPORTVA
#  define ZEXPORTVA
#endif

#ifndef FAR
#  define FAR
#endif

#if !defined(__MACTYPES__)
typedef unsigned char  Byte;  /* 8 bits */
#endif
typedef unsigned int   uInt;  /* 16 bits or more */
typedef unsigned long  uLong; /* 32 bits or more */

#ifdef SMALL_MEDIUM
   /* Borland C/C++ and some old MSC versions ignore FAR inside typedef */
#  define Bytef Byte FAR
#else
   typedef Byte  FAR Bytef;
#endif
typedef char  FAR charf;
typedef int   FAR intf;
typedef uInt  FAR uIntf;
typedef uLong FAR uLongf;

#ifdef STDC
   typedef void const *voidpc;
   typedef void FAR   *voidpf;
   typedef void       *voidp;
#else
   typedef Byte const *voidpc;
   typedef Byte FAR   *voidpf;
   typedef Byte       *voidp;
#endif

#if !defined(CNIOEXTRAS_Z_U4) && !defined(CNIOEXTRAS_Z_SOLO) && defined(STDC)
#  include <limits.h>
#  if (UINT_MAX == 0xffffffffUL)
#    define CNIOEXTRAS_Z_U4 unsigned
#  elif (ULONG_MAX == 0xffffffffUL)
#    define CNIOEXTRAS_Z_U4 unsigned long
#  elif (USHRT_MAX == 0xffffffffUL)
#    define CNIOEXTRAS_Z_U4 unsigned short
#  endif
#endif

#ifdef CNIOEXTRAS_Z_U4
   typedef CNIOEXTRAS_Z_U4 cnioextras_z_crc_t;
#else
   typedef unsigned long cnioextras_z_crc_t;
#endif

#if 1     /* was set to #if 1 by ./configure */
#  define CNIOEXTRAS_Z_HAVE_UNISTD_H
#endif

#if 1     /* was set to #if 1 by ./configure */
#  define CNIOEXTRAS_Z_HAVE_STDARG_H
#endif

#ifdef STDC
#  ifndef CNIOEXTRAS_Z_SOLO
#    include <sys/types.h>      /* for off_t */
#  endif
#endif

#if defined(STDC) || defined(CNIOEXTRAS_Z_HAVE_STDARG_H)
#  ifndef CNIOEXTRAS_Z_SOLO
#    include <stdarg.h>         /* for va_list */
#  endif
#endif

#ifdef _WIN32
#  ifndef CNIOEXTRAS_Z_SOLO
#    include <stddef.h>         /* for wchar_t */
#  endif
#endif

/* a little trick to accommodate both "#define _LARGEFILE64_SOURCE" and
 * "#define _LARGEFILE64_SOURCE 1" as requesting 64-bit operations, (even
 * though the former does not conform to the LFS document), but considering
 * both "#undef _LARGEFILE64_SOURCE" and "#define _LARGEFILE64_SOURCE 0" as
 * equivalently requesting no 64-bit operations
 */
#if defined(_LARGEFILE64_SOURCE) && -_LARGEFILE64_SOURCE - -1 == 1
#  undef _LARGEFILE64_SOURCE
#endif

#ifndef CNIOEXTRAS_Z_HAVE_UNISTD_H
#  if defined(__WATCOMC__) || defined(__GO32__) || \
      (defined(_LARGEFILE64_SOURCE) && !defined(_WIN32))
#    define CNIOEXTRAS_Z_HAVE_UNISTD_H
#  endif
#endif
#ifndef CNIOEXTRAS_Z_SOLO
#  if defined(CNIOEXTRAS_Z_HAVE_UNISTD_H)
#    include <unistd.h>         /* for SEEK_*, off_t, and _LFS64_LARGEFILE */
#    ifdef VMS
#      include <unixio.h>       /* for off_t */
#    endif
#    ifndef cnioextras_z_off_t
#      define cnioextras_z_off_t off_t
#    endif
#  endif
#endif

#if defined(_LFS64_LARGEFILE) && _LFS64_LARGEFILE-0
#  define CNIOEXTRAS_Z_LFS64
#endif

#if defined(_LARGEFILE64_SOURCE) && defined(CNIOEXTRAS_Z_LFS64)
#  define CNIOEXTRAS_Z_LARGE64
#endif

#if defined(_FILE_OFFSET_BITS) && _FILE_OFFSET_BITS-0 == 64 && defined(CNIOEXTRAS_Z_LFS64)
#  define CNIOEXTRAS_Z_WANT64
#endif

#if !defined(SEEK_SET) && !defined(CNIOEXTRAS_Z_SOLO)
#  define SEEK_SET        0       /* Seek from beginning of file.  */
#  define SEEK_CUR        1       /* Seek from current position.  */
#  define SEEK_END        2       /* Set file pointer to EOF plus "offset" */
#endif

#ifndef cnioextras_z_off_t
#  define cnioextras_z_off_t long long
#endif

#if !defined(_WIN32) && defined(CNIOEXTRAS_Z_LARGE64)
#  define cnioextras_z_off64_t off64_t
#elif defined(__MINGW32__)
#  define cnioextras_z_off64_t long long
#elif defined(_WIN32) && !defined(__GNUC__)
#  define cnioextras_z_off64_t __int64
#elif defined(__GO32__)
#  define cnioextras_z_off64_t offset_t
#else
#  define cnioextras_z_off64_t cnioextras_z_off_t
#endif

/* MVS linker does not support external names larger than 8 bytes */
#if defined(__MVS__)
  #pragma map(deflateInit_,"DEIN")
  #pragma map(deflateInit2_,"DEIN2")
  #pragma map(deflateEnd,"DEEND")
  #pragma map(deflateBound,"DEBND")
  #pragma map(inflateInit_,"ININ")
  #pragma map(inflateInit2_,"ININ2")
  #pragma map(inflateEnd,"INEND")
  #pragma map(inflateSync,"INSY")
  #pragma map(inflateSetDictionary,"INSEDI")
  #pragma map(compressBound,"CMBND")
  #pragma map(inflate_table,"INTABL")
  #pragma map(inflate_fast,"INFA")
  #pragma map(inflate_copyright,"INCOPY")
#endif

#endif /* NIOEXTRAS_ZCONF_H */
