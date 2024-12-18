{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# OPTIONS_GHC -Wno-unused-imports #-}

module Main where

import Control.Exception
import System.Posix.IO (openFd, defaultFileFlags, closeFd, OpenMode(ReadWrite))
import System.Posix.Types (Fd(Fd))
import Foreign.Marshal.Alloc (alloca)
import Foreign.Ptr (Ptr)
import Foreign
import Foreign.Storable
import Foreign.C.Types
import Foreign.C
import Foreign.Marshal.Array

#include <linux/vt.h>
#include <sys/ioctl.h>
#include <errno.h>

requestVTGETSTATE :: CInt
requestVTGETSTATE = 0x5603
requestVTACTIVATE :: CInt
requestVTACTIVATE = 0x5606
requestVTWAITACTIVE :: CInt
requestVTWAITACTIVE = 0x5607

foreign import ccall "set_ctm" c_setCTM :: CInt -> CUInt -> Ptr CFloat -> IO ()
foreign import ccall "find_crtc" c_findCRTC :: CInt -> IO CUInt

setCTM :: Fd -> CUInt -> CTM -> IO ()
setCTM (Fd fd) crtc CTM{..} = do
  allocaArray 9 $ \(cctm :: Ptr CFloat) -> do
    pokeArray
      cctm
      (CFloat <$> [ctmRR,ctmGR,ctmBR,ctmRG,ctmGG,ctmBG,ctmRB,ctmGB,ctmBB])
    c_setCTM fd crtc cctm

findCRTC :: Fd -> IO CUInt
findCRTC (Fd fd) = c_findCRTC fd

foreign import ccall "ioctl" c_ioctl :: CInt -> CInt -> Ptr () -> IO CInt
foreign import ccall "ioctl" c_ioctl' :: CInt -> CInt -> CInt -> IO CInt
foreign import ccall "strerror" c_strerror :: CInt -> CString

data CTM =
  CTM
  { ctmRR :: Float , ctmGR :: Float , ctmBR :: Float
  , ctmRG :: Float , ctmGG :: Float , ctmBG :: Float
  , ctmRB :: Float , ctmGB :: Float , ctmBB :: Float
  } deriving (Show)

data IoctlException = IoctlException Int String deriving (Show)
instance Exception IoctlException

ioctl :: CInt -> CInt -> Ptr a -> IO ()
ioctl fd req p = do
  err <- c_ioctl fd req (castPtr p)

  if err == 0
    then pure ()
    else do
      errmsg <- peekCString (c_strerror err)
      throw $ IoctlException (fromIntegral err) errmsg

ioctl' :: CInt -> CInt -> CInt -> IO ()
ioctl' fd req arg = do
  err <- c_ioctl' fd req arg

  if err == 0
    then pure ()
    else do
      errmsg <- peekCString (c_strerror err)
      throw $ IoctlException (fromIntegral err) errmsg

data VTStat
  = VTStat
    { vActive :: CUShort
    , vSignal :: CUShort
    , vState :: CUShort
    } deriving (Show)

instance Storable VTStat where
  alignment _ = #{alignment struct vt_stat}
  sizeOf _    = #{size      struct vt_stat}
  peek p      =
    return VTStat
    <*> (#{peek struct vt_stat, v_active} p)
    <*> (#{peek struct vt_stat, v_signal} p)
    <*> (#{peek struct vt_stat, v_state} p)
  poke p vstat = do
    #{poke struct vt_stat, v_active} p $ vActive vstat
    #{poke struct vt_stat, v_signal} p $ vSignal vstat
    #{poke struct vt_stat, v_state} p $ vState vstat

getCurrentVT :: Fd -> IO VTStat
getCurrentVT (Fd fd) = do
  alloca $ \(ptr :: Ptr VTStat) -> do
    ioctl fd requestVTGETSTATE ptr
    peek ptr

setCurrentVT :: Fd -> Int -> IO ()
setCurrentVT (Fd fd) (fromIntegral -> vt) = do
  ioctl' fd requestVTACTIVATE vt
  ioctl' fd requestVTWAITACTIVE vt

clamp :: Ord a => a -> a -> a -> a
clamp x l u =
  if x < l
  then l
  else if x > u
       then u
       else x

ctmMult :: CTM -> CTM -> CTM
ctmMult x y =
  CTM
    (ctmRR x * ctmRR y + ctmGR x * ctmRG y + ctmBR x * ctmRB y)
    (ctmRR x * ctmGR y + ctmGR x * ctmGG y + ctmBR x * ctmGB y)
    (ctmRR x * ctmBR y + ctmGR x * ctmBG y + ctmBR x * ctmBB y)
    (ctmRG x * ctmRR y + ctmGG x * ctmRG y + ctmBG x * ctmRB y)
    (ctmRG x * ctmGR y + ctmGG x * ctmGG y + ctmBG x * ctmGB y)
    (ctmRG x * ctmBR y + ctmGG x * ctmBG y + ctmBG x * ctmBB y)
    (ctmRB x * ctmRR y + ctmGB x * ctmRG y + ctmBB x * ctmRB y)
    (ctmRB x * ctmGR y + ctmGB x * ctmGG y + ctmBB x * ctmGB y)
    (ctmRB x * ctmBR y + ctmGB x * ctmBG y + ctmBB x * ctmBB y)

temp :: Float -> CTM
temp t' =
  let
    t = t' / 100
    r =
      if t <= 66
      then 255
      else clamp (329.698727446 * (t - 60) ** (-0.1332047592)) 0 255
    g =
      if t <= 66
      then clamp (99.4708025861 * (log t) - 161.1195681661) 0 255
      else clamp (288.1221695283 * (t - 60) ** (-0.0755148492)) 0 255
    b =
      if t <= 66
      then if t <= 19
           then 0
           else clamp (log(t - 10) * 138.5177312231 - 305.0447927307) 0 255
      else 255
  in
    CTM
      (r / 255) 0 0
      0 (g / 255) 0
      0 0 (b / 255)

main :: IO ()
main = do
  fd <- openFd "/dev/console" ReadWrite Nothing defaultFileFlags

  currentVT <- getCurrentVT fd

  setCurrentVT fd 3

  drmFd <- openFd "/dev/dri/card1" ReadWrite Nothing defaultFileFlags
  crtc <- findCRTC drmFd
  print crtc

  let
    bwCtm = CTM 0.299 0.299 0.299 0.587 0.587 0.587 0.114 0.114 0.114
    br = CTM 1.1 0 0 0 1.1 0 0 0 1.1
    ctm = bwCtm `ctmMult` temp 2500 `ctmMult` br

  setCTM drmFd crtc ctm
  setCurrentVT fd (fromIntegral $ vActive currentVT)

  closeFd fd
  closeFd drmFd
