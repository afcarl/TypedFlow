{-# LANGUAGE TypeInType #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE GADTs #-}
module TypedFlow.Memo where

import qualified Data.IntMap as I
import System.Mem.StableName
import Data.IORef
import System.IO.Unsafe
import Data.Kind (Type)
type SNMap k v = I.IntMap [(StableName k,v)]

snMapLookup :: StableName k -> SNMap k v -> Maybe v
snMapLookup sn m = do
  x <- I.lookup (hashStableName sn) m
  lookup sn x

snMapInsert :: StableName k -> v -> SNMap k v -> SNMap k v
snMapInsert sn res = I.insertWith (++) (hashStableName sn) [(sn,res)]

memo :: (a -> b) -> a -> b
memo f = unsafePerformIO (
  do { tref <- newIORef (I.empty)
     ; return (applyStable f tref)
     })

applyStable :: (a -> b) -> IORef (SNMap a b) -> a -> b
applyStable f tbl arg = unsafePerformIO (
  do { sn <- makeStableName arg
     ; lkp <- snMapLookup sn <$> readIORef tbl
     ; case lkp of
         Just result -> return result
         Nothing ->
           do { let res = f arg
              ; modifyIORef tbl (snMapInsert sn res)
              ; return res
              }})

data Some2 k1 k2 (f :: k1 -> k2 -> Type) where
  Some2 :: forall k1 k2 f a b. StableName (f a b) -> Some2 k1 k2 f

instance Eq (Some2 k1 k2 f) where
  Some2 sn1 == Some2 sn2 = eqStableName sn1 sn2

type SSNMap2 k1 k2 (f :: k1 -> k2 -> Type) v = I.IntMap [(Some2 k1 k2 f,v)]

makeSn2 :: f a b -> Some2 k1 k2 f
makeSn2 = Some2 . unsafePerformIO . makeStableName

snMapLookup2 :: Some2 k1 k2 f -> SSNMap2 k1 k2 f v -> Maybe v
snMapLookup2 (Some2 sn) m = do
  x <- I.lookup (hashStableName sn) m
  lookup (Some2 sn) x

snMapInsert2 :: Some2 k1 k2 f -> v -> SSNMap2 k1 k2 f v -> SSNMap2 k1 k2 f v
snMapInsert2 (Some2 sn) res = I.insertWith (++) (hashStableName sn) [(Some2 sn,res)]