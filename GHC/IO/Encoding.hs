{-# LANGUAGE CPP, NoImplicitPrelude, PatternGuards #-}
{-# OPTIONS_GHC -funbox-strict-fields #-}

-----------------------------------------------------------------------------
-- |
-- Module      :  GHC.IO.Encoding
-- Copyright   :  (c) The University of Glasgow, 2008-2009
-- License     :  see libraries/base/LICENSE
-- 
-- Maintainer  :  libraries@haskell.org
-- Stability   :  internal
-- Portability :  non-portable
--
-- Text codecs for I/O
--
-----------------------------------------------------------------------------

module GHC.IO.Encoding (
  BufferCodec(..), TextEncoding(..), TextEncoder, TextDecoder,
  latin1, latin1_encode, latin1_decode,
  utf8, utf8_bom,
  utf16, utf16le, utf16be,
  utf32, utf32le, utf32be, 
  localeEncoding, fileSystemEncoding, foreignEncoding,
  mkTextEncoding,
  ) where

import GHC.Base
--import GHC.IO
import GHC.IO.Exception
import GHC.IO.Buffer
import GHC.IO.Encoding.Failure
import GHC.IO.Encoding.Types
import GHC.Word
#if !defined(mingw32_HOST_OS)
import qualified GHC.IO.Encoding.Iconv  as Iconv
#else
import qualified GHC.IO.Encoding.CodePage as CodePage
import Text.Read (reads)
#endif
import qualified GHC.IO.Encoding.Latin1 as Latin1
import qualified GHC.IO.Encoding.UTF8   as UTF8
import qualified GHC.IO.Encoding.UTF16  as UTF16
import qualified GHC.IO.Encoding.UTF32  as UTF32

import Data.List
import Data.Maybe

-- -----------------------------------------------------------------------------

-- | The Latin1 (ISO8859-1) encoding.  This encoding maps bytes
-- directly to the first 256 Unicode code points, and is thus not a
-- complete Unicode encoding.  An attempt to write a character greater than
-- '\255' to a 'Handle' using the 'latin1' encoding will result in an error.
latin1  :: TextEncoding
latin1 = Latin1.latin1_checked

-- | The UTF-8 Unicode encoding
utf8  :: TextEncoding
utf8 = UTF8.utf8

-- | The UTF-8 Unicode encoding, with a byte-order-mark (BOM; the byte
-- sequence 0xEF 0xBB 0xBF).  This encoding behaves like 'utf8',
-- except that on input, the BOM sequence is ignored at the beginning
-- of the stream, and on output, the BOM sequence is prepended.
--
-- The byte-order-mark is strictly unnecessary in UTF-8, but is
-- sometimes used to identify the encoding of a file.
--
utf8_bom  :: TextEncoding
utf8_bom = UTF8.utf8_bom

-- | The UTF-16 Unicode encoding (a byte-order-mark should be used to
-- indicate endianness).
utf16  :: TextEncoding
utf16 = UTF16.utf16

-- | The UTF-16 Unicode encoding (litte-endian)
utf16le  :: TextEncoding
utf16le = UTF16.utf16le

-- | The UTF-16 Unicode encoding (big-endian)
utf16be  :: TextEncoding
utf16be = UTF16.utf16be

-- | The UTF-32 Unicode encoding (a byte-order-mark should be used to
-- indicate endianness).
utf32  :: TextEncoding
utf32 = UTF32.utf32

-- | The UTF-32 Unicode encoding (litte-endian)
utf32le  :: TextEncoding
utf32le = UTF32.utf32le

-- | The UTF-32 Unicode encoding (big-endian)
utf32be  :: TextEncoding
utf32be = UTF32.utf32be

-- | The Unicode encoding of the current locale
localeEncoding :: TextEncoding

-- | The Unicode encoding of the current locale, but allowing arbitrary
-- undecodable bytes to be round-tripped through it
fileSystemEncoding :: TextEncoding

-- | The Unicode encoding of the current locale, but where undecodable
-- bytes are replaced with their closest visual match. Used for
-- the 'CString' marshalling functions in "Foreign.C.String"
foreignEncoding :: TextEncoding

#if !defined(mingw32_HOST_OS)
localeEncoding = Iconv.localeEncoding
fileSystemEncoding = Iconv.localeEncodingFailingWith SurrogateEscapeFailure
foreignEncoding = Iconv.localeEncodingFailingWith IgnoreCodingFailure
#else
localeEncoding = CodePage.localeEncoding
fileSystemEncoding = CodePage.localeEncoding -- On Windows, this is rarely used. FilePaths will always be Unicode
foreignEncoding = CodePage.localeEncodingFailingWith IgnoreCodingFailure
#endif

-- | Look up the named Unicode encoding.  May fail with 
--
--  * 'isDoesNotExistError' if the encoding is unknown
--
-- The set of known encodings is system-dependent, but includes at least:
--
--  * @UTF-8@
--
--  * @UTF-16@, @UTF-16BE@, @UTF-16LE@
--
--  * @UTF-32@, @UTF-32BE@, @UTF-32LE@
--
-- On systems using GNU iconv (e.g. Linux), there is additional
-- notation for specifying how illegal characters are handled:
--
--  * a suffix of @\/\/IGNORE@, e.g. @UTF-8\/\/IGNORE@, will cause 
--    all illegal sequences on input to be ignored, and on output
--    will drop all code points that have no representation in the
--    target encoding.
--
--  * a suffix of @\/\/TRANSLIT@ will choose a replacement character
--    for illegal sequences or code points.
--
-- On Windows, you can access supported code pages with the prefix
-- @CP@; for example, @\"CP1250\"@.
--
mkTextEncoding :: String -> IO TextEncoding
mkTextEncoding e = case mb_coding_failure_mode of
  Nothing -> unknown_encoding
  Just cfm -> case enc of
    "UTF-8"    -> return $ UTF8.utf8FailingWith cfm
    "UTF-16"   -> return $ UTF16.utf16FailingWith cfm
    "UTF-16LE" -> return $ UTF16.utf16leFailingWith cfm
    "UTF-16BE" -> return $ UTF16.utf16beFailingWith cfm
    "UTF-32"   -> return $ UTF32.utf32FailingWith cfm
    "UTF-32LE" -> return $ UTF32.utf32leFailingWith cfm
    "UTF-32BE" -> return $ UTF32.utf32beFailingWith cfm
#if defined(mingw32_HOST_OS)
    'C':'P':n | [(cp,"")] <- reads n -> return $ CodePage.codePageEncodingFailingWith cp cfm
    _ -> unknown_encoding
#else
    _ -> Iconv.mkTextEncoding e
#endif
  where
    -- The only problem with actually documenting //IGNORE and //TRANSLIT as
    -- supported suffixes is that they are not necessarily supported with non-GNU iconv
    (enc, suffix) = span (/= '/') e
    mb_coding_failure_mode = case suffix of
        ""            -> Just ErrorOnCodingFailure
        "//IGNORE"    -> Just IgnoreCodingFailure
        "//TRANSLIT"  -> Just TransliterateCodingFailure
        "//SURROGATE" -> Just SurrogateEscapeFailure
        _             -> Nothing
    
    unknown_encoding = ioException (IOError Nothing NoSuchThing "mkTextEncoding"
                                            ("unknown encoding:" ++ e)  Nothing Nothing)

latin1_encode :: CharBuffer -> Buffer Word8 -> IO (CharBuffer, Buffer Word8)
latin1_encode = Latin1.latin1_encode -- unchecked, used for binary
--latin1_encode = unsafePerformIO $ do mkTextEncoder Iconv.latin1 >>= return.encode

latin1_decode :: Buffer Word8 -> CharBuffer -> IO (Buffer Word8, CharBuffer)
latin1_decode = Latin1.latin1_decode
--latin1_decode = unsafePerformIO $ do mkTextDecoder Iconv.latin1 >>= return.encode
