{-# LANGUAGE InstanceSigs #-}
{-|
Module      : TypedFlow.Abstract
Description : Abstract Tensor representations
Copyright   : (c) Jean-Philippe Bernardy, 2018
License     : LGPL-3
Maintainer  : jean-philippe.bernardy@gu.se
Stability   : experimental

This module provides operations on the abstract representation of
tensor operations. It is not normally imported directly by users.
-}

{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.KnownNat.Solver #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveFoldable #-}
{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE DeriveTraversable #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE MagicHash #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeInType #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE UnicodeSyntax #-}

module TypedFlow.Abstract where

import System.IO.Unsafe
import Data.Unique
import TypedFlow.Python
import Prelude hiding (RealFrac(..))
import GHC.TypeLits
import Data.Proxy
import TypedFlow.Types hiding (T)
import Data.Type.Equality
import Data.Kind (Type,)
import TypedFlow.Types (T(..))
import TypedFlow.Types.Proofs
import Text.PrettyPrint.Compact hiding (All,Last,Product,Sum)
import TypedFlow.Memo


broadcast :: forall n s t proxy. KnownTyp t => KnownShape s => KnownNat n
  => Unique -> Bool -> proxy n -> T s t -> T (n : s) t
broadcast u varyNoise n x = result
  where f :: forall s' t'. STyp t' -> SShape s' -> T s' t' -> T (n : s') t'
        f = memo3 memoOrd memoOrd memo (protoBroadcast u varyNoise (proxySat n) (f typeSTyp) finished)
        finished :: forall s' t'. T s' t' -> Bool
        finished = memo (protoFinished u varyNoise finished)
        -- note: the memo table must be shared across all the calls to
        -- 'finished' in 'protoBroadcast' for proper efficiency.
        result = f typeSTyp typeSShape x


protoFinished :: Unique -> Bool -> (forall s' t'. T s' t' -> Bool) -> T s t -> Bool
protoFinished u varyNoise rec = \case
  DirectBroadcast _ _ _ _ x -> rec x
  GatherND _ _ _ x y -> rec x && rec y
  Noise _ _ _ _ -> not varyNoise
  If cond x y ->  rec cond && rec x && rec y
  Where cond x y -> rec cond && rec x && rec y
  T _ -> True
  Unbroadcast _p u' _x -> u /= u'
  UnOp _op _ _ _ x -> rec x
  MatMul _ _ _ _ x y -> rec x && rec y
  BinOp _op _ _ _ _ x y -> rec x && rec y
  Gather _is _s0 _m _s1 x ix -> rec x && rec ix
  Transpose _ _t x -> rec x
  ReshapeFrom _s x -> rec x
  Stack _s0 _m _s1 xs -> all rec xs
  Convolution _bs _inChans _outChans _filterShape _s x filters -> rec x && rec filters
  Pool _ _ _ _ _ x  -> rec x

class Batched (f :: [Shape] -> Type) where
  -- | Applying an expansion function to all the tensors in the given structure.
  batchify :: forall n r. KnownNat n => All KnownShape r
    => Proxy n -> (forall s t. KnownTyp t => KnownShape s => T s t -> T (n:s) t)
    -> f r  -> f (Ap (FMap (Cons n)) r)

batchifyHTV :: forall n r ty. KnownTyp ty => KnownNat n => All KnownShape r => Proxy n -> (forall s t. KnownTyp t => KnownShape s => T s t -> T (n:s) t)
  -> HTV ty r  -> HTV ty (Ap (FMap (Cons n)) r)
batchifyHTV _ _ Unit = Unit
batchifyHTV n bc (F x :* xs) = F (bc x) :* batchifyHTV n bc xs

instance KnownTyp ty => Batched (HTV ty) where
  batchify = batchifyHTV

-- | Perform broadcast on all the tensors in the given structure
broadcastGen  :: KnownNat n => Batched f => All KnownShape r => Unique -> Bool -> Proxy n -> f r -> f (Ap (FMap (Cons n)) r)
broadcastGen u varyNoise n = batchify n (broadcast u varyNoise n)

testSatEqual :: forall n m. Sat KnownNat n -> Sat KnownNat m -> Maybe (n :~: m)
testSatEqual Sat Sat = testEqual (Proxy @n) (Proxy @m)


-- | Turns a tensor of indices in a container into a tensor of indices
-- in a container of higher rank. The added indexed dimension
-- corresponds to the first dimension of the index.
broadcastIndex :: forall n containerShape indexShape w.
  KnownBits w => Sat KnownNat n ->
  SShape containerShape ->
  SShape indexShape ->
  IndexTensor (n ': indexShape) containerShape w ->
  IndexTensor (n ': indexShape) (n ': containerShape) w
broadcastIndex n cs = broadcastIndex' n (sListLenAsNat cs)

broadcastIndex' :: forall n containerRank indexShape w.
  KnownBits w => Sat KnownNat n ->
  Sat KnownNat containerRank ->
  SShape indexShape ->
  T (n ': indexShape ++ '[containerRank])  ('Typ 'Int w) ->
  T (n ': indexShape ++ '[1 + containerRank]) ('Typ 'Int w)
broadcastIndex' n@Sat cr is ix = concatT' ((:*) n is) (natSat @1) cr Unit nIndex ix
  where nIndex :: T (n ': indexShape ++ '[1]) ('Typ 'Int w)
        nIndex = DirectBroadcast Unit Unit ((:*) n Unit) (is .+. (:*) (natSat @1) Unit) range

directBroadcast0 :: forall n s t. KnownShape s => KnownNat n => T s t -> T (n:s) t
directBroadcast0 = appRUnit @s $ DirectBroadcast Unit ((:*) (natSat @n) Unit) (typeSShape @s) Unit

broadcastIndexMany :: forall n containerShape indexShape w.
  KnownBits w =>
  Sat KnownNat n ->
  SShape containerShape ->
  SShape indexShape ->
  IndexTensor indexShape '[n] w ->
  IndexTensor (containerShape ++ indexShape) (containerShape ++ '[n]) w
broadcastIndexMany _ Unit _ x = x
broadcastIndexMany n ((:*) m@Sat cs) is x =
  knownSShape (cs .+. (*:) is (sListLenAsNat ((*:) cs n))) $
  -- (m : cs ++ is ++  '[(Length (m : cs ++ [n]))])
  broadcastIndex m ((*:) cs n) (cs .+. is) $
  -- (m : (cs ++ is ++  '[Length (cs ++ [n])]))
  appAssocS cs is ((:*) (sListLenAsNat ((*:) cs n)) Unit) $
  -- (m : cs ++ is ++ '[Length (cs ++ [n])])
  directBroadcast0 $
  -- (cs ++ is ++  '[Length (cs ++ [n])])
  broadcastIndexMany n cs is x
  -- is

--  Product (filterSpatialShape ++ '[inChannels, outChannels * n])
-- Product ((filterSpatialShape ++ '[inChannels, outChannels]) ++ '[n])


protoBroadcast :: forall n s t.
  Unique -> Bool
  -> Sat KnownNat n
  -> (forall s' t'. KnownTyp t' => SShape s' -> T s' t' -> T (n ': s') t')
  -> (forall s' t'. T s' t' -> Bool)
  -> STyp t
  -> SShape s
  -> T s t
  -> T (n ': s) t
protoBroadcast u varyNoise n@(Sat) rec finished ty s tensor
  | finished tensor = simpleBC
  | otherwise = knownTyp ty $ case tensor of
  DirectBroadcast s0 s1 s2 s3 x -> DirectBroadcast (n :* s0) s1 s2 s3 (rec (s0 .+. s2) x)
  GatherND cs es is x ix
    | finished x -> GatherND cs es (n :* is) x (rec (is *: sListLenAsNat cs) ix)
    | otherwise -> GatherND (n :* cs) es (n :* is) (rec (cs .+. es) x) (broadcastIndex' n (sListLenAsNat cs) is (rec (is *: sListLenAsNat cs) ix))
  Noise v s0 s1 x -> if varyNoise then Noise v (n :* s0) s1 x else simpleBC
  -- When varying noise, then we extend the shape of the noise (so
  -- more stuff is sampled), otherwise we copy the noise using simple
  -- broadcasting
  Pool bs@Sat window pt numChans outSpatial x ->
    knownSShape (zipWithMulSShapes window outSpatial *: numChans) $
    prodAssocS n bs (productS (zipWithMulSShapes window outSpatial *: numChans)) $
    prodAssocS n bs (productS (outSpatial *: numChans)) $
    reshapeFrom (satMul n bs :* outSpatial *: numChans) $
    Pool (satMul n bs) window pt numChans outSpatial (reshapeAuto (rec typeSShape x))
  If cond x y
    | finished cond -> If cond (rec s x) (rec s y)
    | otherwise ->  error "broadcast if condition not implemented"
  Where cond x y -> Where (rec s cond) (rec s x) (rec s y)
  T _ -> error "panic: broadcast constant should be finished!"
  Unbroadcast p@Sat u' x
    | u == u' -> case testSatEqual p n of
        Nothing -> UnOp (Simple1Op "panic.unbroadcast" [integer (natVal n)
                                                       ,integer (natVal p)])
                         Unit (p :* s) (n :* s) x
        Just Refl -> x
    | otherwise -> knownSShape s $ Unbroadcast p u' (transpose01 (rec (p :* s) x))
  MatMul Unit a@Sat b@Sat c@Sat x y
     -- this optimisation is absolutely critical to implement dense
     -- layers efficiently (at least with TF 1.3). (about 10x performance increase)
     | finished y -> inflate2 (MatMul Unit (satMul n a) b c (flatten2 (rec (a :* b :* Unit) x)) y)
  MatMul s0 a b c x y -> MatMul (n :* s0) a b c (rec (s0 .+. a :* b :* Unit) x) (rec (s0 .+. b :* c :* Unit) y)
  BinOp op s0 s1 s2 s3 x y -> BinOp op (n :* s0) s1 s2 s3 (rec (s0 .+. s1) x) (rec (s0 .+. s2) y)
  UnOp op s0 s1 s2 x -> UnOp op (n :* s0) s1 s2 (rec (s0 .+. s1) x)
  Gather is Unit m s1 x ix
    -- this optimisation is important to get efficient embeddings
    | finished x -> Gather (n :* is) Unit m s1 x (rec is ix)
  Gather is s0 m s1 x ix
    | finished ix -> Gather is (n :* s0) m s1 (rec (s0 .+. m :* s1) x) ix
    -- otherwise, Gather is not strong enough, and we need to convert
    -- it to GatherND before broadcasting.
    | otherwise -> appAssocS s0 (m :* Unit) s1 $
                   lengthHomoS s0 (m :* Unit) $
                   prodHomoS is ((natSat @1) :* Unit) $
                   knownSShape is $
                   rec s (GatherND (s0 *: m) s1 (s0 .+. is) x (broadcastIndexMany m s0 is (reshapeAuto ix)))
  Transpose s0 t x -> Transpose (n :* s0) (PermSkip t) (rec s0 x)
  ReshapeFrom s0 x -> reshapeFrom (n :* s0) (rec s0 x)
  Stack s0 m s1 xs -> Stack (n :* s0) m s1 (fmap (rec (s0 .+. s1)) xs)
  Convolution bs@(Sat) inChans outChans filterShape s0 x filters
    | finished filters ->
      prodAssocS n bs (productS (s0 *: inChans)) $
      prodAssocS n bs (productS (s0 *: outChans)) $
      knownSShape (s0 *: inChans)  $
      reshapeFrom (satMul n bs :* s0 *: outChans) $ 
      Convolution (satMul n bs) inChans outChans filterShape s0 (reshapeAuto (rec typeSShape x)) filters
    | finished x ->
      knownSShape (filterShape .+. inChans :* outChans :* Unit) $
      knownSShape (bs :* s0 .+. outChans :* Unit) $
      transposeN' $
      reshapeProven (ANat bs !:* AShape s0 *:! (ANat outChans :*: ANat n))
                    ((ANat bs !:* AShape s0 *:! ANat outChans) *:! ANat n) $
      Convolution bs inChans (outChans `satMul` n) filterShape s0 x $
      reshapeProven ((AShape filterShape :++: (ANat inChans !:* Single (ANat outChans))) *:! ANat n)
                    (AShape filterShape :++: ANat inChans !:* Single (ANat outChans :*: ANat n)) $
      transposeN $
      rec typeSShape filters
    | otherwise -> error "broadcast on both convolution filter and data not implemented"
 where simpleBC :: Tensor (n ': s) t
       simpleBC = appRUnit @s $ DirectBroadcast Unit (n :* Unit) s Unit tensor

inversePerm :: Permutation a b -> Permutation b a
inversePerm PermId = PermId
inversePerm (PermSkip x) = PermSkip (inversePerm x)
inversePerm PermSwap = PermSwap
inversePerm (PermTrans x y) = PermTrans (inversePerm y) (inversePerm x)

atShape :: SList s -> T s t -> T s t
atShape _ x = x

reshapeAuto :: forall s s0 t. KnownShape s0 => Product s ~ Product s0 => T s0 t -> T s t
reshapeAuto = reshapeFrom typeSShape

reshapeProven :: forall s s0 t n. ShapeX s0 n -> ShapeX s n -> T s0 t -> T s t
reshapeProven s1 s2 = case decideProductEq s1 s2 of
                        Refl -> knownSShape (exprSShape s1) $ reshapeAuto

reshapeTo :: forall s s0 t proxy. KnownShape s0=> Product s ~ Product s0 => proxy s -> T s0 t -> T s t
reshapeTo _ = reshapeAuto

reshapeFrom :: forall s s0 t. Product s ~ Product s0 => SShape s0 -> T s0 t -> T s t
reshapeFrom _ (ReshapeFrom s1 x) = ReshapeFrom s1 x -- avoid reshaping over and over
reshapeFrom s0 x = ReshapeFrom s0 x

-- | Zeros
zeros :: ∀ t (shape :: Shape). KnownShape shape => KnownTyp t => (T shape t)
zeros = T (funcall "tf.zeros" [showShapeType @shape, named "dtype" (showTyp @t)])

-- | Ones
ones :: ∀ t (shape :: Shape). KnownShape shape => KnownTyp t => (T shape t)
ones = T (funcall "tf.ones" [showShapeType @shape, named "dtype" (showTyp @t)])

-- | Identity matrix in dimensions m,n (extended with zeros if m ≠ n), and repeated on shape s.
eye :: ∀ m n s t. KnownShape s => KnownNat m => KnownNat n => KnownTyp t => (T (m ': n ': s) t)
eye = T (funcall "tf.eye" [showDim @n,
                            named "num_columns" (showDim @m),
                            named "batch_shape" (showShapeType @s),
                            named "dtype" (showTyp @t)])

-- | range[i] = i
range :: forall n w. KnownNat n => KnownBits w => T '[n] ('Typ 'Int w)
range = T (func "tf.range" [] [("start",integer 0),
                               ("limit",integer (natVal (Proxy @n))),
                               ("dtype",showTyp @('Typ 'Int w))])

-- | Constant
constant :: forall s t w. KnownShape s => KnownBits w => KnownKind t => HostType t -> T s ('Typ t w)
constant c = T (funcall "tf.constant" [pretty c, named "shape" (showShapeType @s), named "dtype" (showTyp @('Typ t w))])


reduceAll :: forall s t. KnownTyp t => KnownShape s =>
     (∀n s'. (KnownTyp t,KnownShape s') => Axis n s' -> T s' t -> T (Take n s' ++ Drop ('Succ n) s') t) -> Tensor s t -> Tensor '[] t
reduceAll op x = knownProduct @s $
   op axis0 (reshapeTo ((:*) (productS (typeSShape @s)) Unit) x)

-- | Mean value of the input tensor.
reduceMeanAll, reduceSumAll, reduceMaxAll, reduceMinAll :: ∀ (s :: Shape) t. KnownTyp t => KnownShape s => Tensor s t -> Tensor '[] t
reduceMaxAll = reduceAll reduceMax
reduceMeanAll = reduceAll reduceMean
reduceSumAll = reduceAll reduceSum
reduceMinAll = reduceAll reduceMin

sShapeTake' :: Axis n s -> SList' f s -> SList' f (Take n s)
sShapeTake' AxZero _s = Unit
sShapeTake' (AxSucc n) ((:*) x xs) = (:*) x (sShapeTake' n xs)

sShapeDrop' :: Axis n s -> SList' f s -> SList' f (Drop n s)
sShapeDrop' AxZero s = s
sShapeDrop' (AxSucc n) ((:*) _ xs) = sShapeDrop' n xs

sShapeDropSucc :: Axis n s -> SList' f s -> SList' f (Drop ('Succ n) s)
sShapeDropSucc AxZero (_ :* s) = s
sShapeDropSucc (AxSucc n) (_ :* xs) = sShapeDropSucc n xs

-- | Internal. Use 'reduceSum', etc. instead.
reduce :: ∀ n s t. KnownTyp t => (KnownShape s) => String -> Axis n s -> T s t -> T (Take n s ++ Drop ('Succ n) s) t
reduce op n x = UnOp (Axis1Op ("tf.reduce_" ++ op) [] (axisInt n)) Unit (typeSShape @s)  (sShapeTake' n s .+. sShapeDropSucc n s) x
  where s = typeSShape @s

-- | Reduce along a given dimension
reduceSum, reduceMean, reduceMax, reduceMin :: ∀n s t. (KnownTyp t,KnownShape s) => Axis n s -> T s t -> T (Take n s ++ Drop ('Succ n) s) t
reduceSum = reduce "sum"
reduceMean = reduce "mean"
reduceMax = reduce "max"
reduceMin = reduce "min"


-- | Sum along the first dimension
reduceSum0 :: ∀ s' n t. KnownNat n => KnownTyp t => KnownShape s' => Tensor (n ': s') t -> Tensor s' t
reduceSum0 = reduceSum axis0



addN :: ∀ s t. KnownTyp t => KnownShape s => [Tensor s t] -> Tensor s t
addN [] = zeros
addN ts = foldr1 (+) ts

instance (KnownTyp t, KnownShape s) => Num (T s t) where
  (+) = (⊕)
  (*) = (⊙)
  signum = unOp "tf.sign"
  fromInteger x = case typeSTyp @t of
    STyp SInt b -> knownBits b $ constant (fromIntegral x :: Int)
    STyp SBool b -> knownBits b $ constant (x /= 0)
    STyp SFloat b -> knownBits b $ constant (fromIntegral x :: Float)
  abs = unOp "tf.abs"
  (-) = (⊝)
  negate = unOp "-"

instance (KnownBits b, KnownShape s) => Fractional (T s ('Typ 'Float b)) where
  fromRational x = knownBits (bitsVal @b) $ constant (fromRational x :: Float)
  (/) = (⊘)

instance (KnownBits b, KnownShape s) => Floating (T s ('Typ 'Float b)) where
  pi = constant pi
  exp = unOp "tf.exp"
  log = unOp "tf.log"
  sin = unOp "tf.sin"
  cos = unOp "tf.cos"
  asin = unOp "tf.asin"
  acos = unOp "tf.acos"
  sinh = unOp "tf.sinh"
  cosh = unOp "tf.cosh"
  asinh = unOp "tf.asinh"
  acosh = unOp "tf.acosh"
  tanh = unOp "tf.tanh"
  atan = unOp "tf.atan"
  atanh = unOp "tf.atanh"
  sqrt = unOp "tf.sqrt"

-- | Pretend that the argument is a constant for the purposes of
-- gradient computation
stopGradient :: ∀ s t. KnownTyp t => KnownShape s => Tensor s t -> Tensor s t
stopGradient = unOp "tf.stop_gradient"

-- | Divide tensors, broacasting along shape @s@
(⊘) :: forall s t. KnownBits t => KnownShape s => T s ('Typ 'Float t) -> T s ('Typ 'Float t) -> T s ('Typ 'Float t)
(⊘) = binOp "tf.divide"


-- | Indexwise equality test.
equal :: forall s t. (KnownShape s, KnownTyp t) => Tensor s t -> Tensor s t -> Tensor s TFBool
equal = binOp "tf.equal"

-- | Indexwise operator
(⊕), (⊝), (⊙)  :: ∀ (s :: Shape) t. (KnownShape s, KnownTyp t) => Tensor s t -> Tensor s t -> Tensor s t
(⊝) = binOp "tf.subtract"
(⊙) = binOp "tf.multiply"
(⊕) = binOp "tf.add"

maxT,minT :: ∀ (s :: Shape) t. (KnownShape s, KnownTyp t) => Tensor s t -> Tensor s t -> Tensor s t
maxT = binOp "tf.maximum"
minT = binOp "tf.minimum"

lessThan :: ∀ (s :: Shape) t. (KnownShape s, KnownTyp t) => Tensor s t -> Tensor s t -> Tensor s TFBool
lessThan = binOp "tf.less"

infixl 7 ⊙,⊘
infixl 6 ⊕,⊝


-- | Matrix multiplication (note that shape @s@ is preserved)
matmul :: forall m n o t. KnownNat m => KnownNat o => KnownNat n => KnownTyp t => T '[n,o] t -> T '[o,m] t -> T '[n,m] t
matmul = MatMul Unit Sat Sat Sat

unOp :: forall s t. KnownShape s => KnownTyp t => String -> T s t -> T s t
unOp op = UnOp (Simple1Op op []) Unit (typeSShape @s) (typeSShape @s)

binOp :: forall s t u. KnownShape s => KnownTyp t => String -> T s t -> T s t -> T s u
binOp op = BinOp (Simple2Op op Nothing) Unit (typeSShape @s) (typeSShape @s) (typeSShape @s)

sigmoid, relu, square, round, floor, hardSigmoid
   :: ∀ s t. (KnownShape s, KnownBits t) => Tensor s ('Typ 'Float t) -> Tensor s ('Typ 'Float t)
sigmoid = unOp "tf.sigmoid"
hardSigmoid = unOp "tf.keras.backend.hard_sigmoid"
square = unOp "tf.square"
relu = unOp "tf.nn.relu"

-- Unfortunately RealFrac is utterly broken; so we have to do this:
round = unOp "tf.round"
floor = unOp "tf.floor"

-- | Take a slice at dimension n from i to j.
slice :: forall i j s t n. KnownTyp t => KnownShape s => KnownNat j => KnownNat i => (i <= j, j <= At n s, KnownLen s) =>
         Axis n s -> Tensor s t -> Tensor (Take n s ++ ((j-i) ': Drop ('Succ n) s)) t
slice n = UnOp (SliceOp (natVal (Proxy @i)) (natVal (Proxy @j))) Unit (typeSShape @s)
             (sShapeTake' n s .+. (:*) (natSat @(j-i)) (sShapeDropSucc n s))
             -- (typeSShape @(Take n s ++ ((j-i) ': Drop ('Succ n) s)))
        where s = typeSShape @s


slice1 :: forall i j m n s t. KnownShape s => KnownNat m => KnownNat n => KnownTyp t => KnownNat j => KnownNat i => (i <= j, j <= m, KnownLen s) =>
         Tensor (n ': m ': s) t -> Tensor (n ': (j-i) ': s) t
slice1 = slice @i @j axis1

slice0 :: forall i j m s t. KnownShape s => KnownNat m => KnownTyp t => KnownNat j => KnownNat i => (i <= j, j <= m, KnownLen s) =>
         Tensor (m ': s) t -> Tensor ((j-i) ': s) t
slice0 = slice @i @j axis0


-- MAYBE: drop these combinators and use zipWithT instead?
-- | Concatenate tensors with explicit shapes. Recommended: use @zipWithTT (concat0 ...)@ instead.
concatT' :: ∀ s0 d1 d2 s1 t. KnownTyp t =>
    SShape s0 -> Sat KnownNat d1 -> Sat KnownNat d2 -> SShape s1 -> T (s0 ++ (d1 ': s1)) t -> T (s0 ++ (d2 ': s1)) t -> T (s0 ++ ((d1+d2) ': s1)) t
concatT' s0 d1@Sat d2@Sat s1 = BinOp (Axis2Op "tf.concat" 0) s0 ((:*) d1 s1) ((:*) d2 s1) ((:*) (natSat @(d1+d2)) s1)

-- MAYBE: drop these combinators and use zipWithT instead?
-- | Concatenate tensors on dimension @n@. Recommended: use @zipWithTT (concat0 ...)@ instead.
concatT :: ∀ n d1 d2 s t. KnownNat d2 => KnownNat d1 => KnownShape s => (KnownTyp t, (d1+d2) ~ At n s) =>
    Axis n s -> T (Take n s ++ (d1 ': Drop ('Succ n) s)) t -> T (Take n s ++ (d2 ': Drop ('Succ n) s)) t -> T s t
concatT n = BinOp (Axis2Op "tf.concat" (axisInt n)) Unit
  (sShapeTake' n s .+. (:*) d1 (sShapeDropSucc n s))
  (sShapeTake' n s .+. (:*) d2 (sShapeDropSucc n s))
  s
  -- FIXME: Prove Take n s ++ At n s ++ Drop (n+1) s ~ s and use concatT'
  where s = typeSShape @s; d1 = natSat @d1; d2 = natSat @d2

-- | Concatenate tensors on the first dimension
concat0 :: ∀ d1 d2 ys t. KnownTyp t => KnownShape ys => KnownNat d2 => KnownNat d1 => (KnownLen ys) => T (d1 ': ys) t -> T (d2 ': ys) t -> T ((d1 + d2) ': ys) t
concat0 = concatT axis0

-- | Concatenate tensors on the second dimension
concat1 :: ∀ n ys d1 d2 t. KnownShape ys => KnownNat n => KnownNat d2 => KnownNat d1 => KnownTyp t => (KnownLen ys) =>  T (n ': d1 ': ys) t -> T (n ': d2 ': ys) t -> T (n ': (d1 + d2) ': ys) t
concat1 = concatT axis1

-- | Add an extra dimension at axis (@n@) of size 1.
expandDim :: forall n s t. KnownTyp t => KnownShape s => (KnownLen s, PeanoNat n <= Length s) => SPeano n -> Tensor s t -> Tensor (Take n s ++ (1 ': Drop n s)) t
expandDim n x =
  -- Product (Take n s ++ (1 ': Drop n s))
  prodHomo @(Take n s) @(1' : Drop n s) $
  -- Product (Take n s) * Product (Drop n s)
  prodHomo @(Take n s) @(Drop n s) $
  -- Product (Take n s ++ (1 ': Drop n s))
  takeDrop @s n $
  -- Product s
  reshapeFrom (typeSShape @s) x

-- +expandDim :: forall n s t. KnownTyp t => KnownShape s => Axis n s -> Tensor s t -> Tensor (Take n s ++ (1 ': Drop n s)) t
-- +expandDim ax x = case expandDimProof ax s of Refl -> reshapeFrom s x

-- | Add an extra dimension at axis (0) of size 1.
expandDim0 :: ∀ s t. KnownShape s => KnownTyp t => KnownLen s => Tensor s t -> Tensor (1 ': s) t
expandDim0 = expandDim SZero

-- | Add an extra dimension at axis (1) of size 1.
expandDim1 :: ∀ n s t. KnownNat n => KnownTyp t => KnownShape s => Tensor (n ': s) t -> Tensor (n ': 1 ': s) t
expandDim1 = reshapeFrom (typeSShape @(n ': s))

reshape :: ∀ s2 s1 t. KnownShape s1 => KnownTyp t => KnownShape s2 => Product s1 ~ Product s2 => Tensor s1 t -> Tensor s2 t
reshape = reshapeAuto


-- | Flatten all the dimensions of the tensor
flattenAll :: forall s t. KnownTyp t => KnownShape s => Tensor s t -> Tensor '[Product s] t
flattenAll = knownProduct @s reshape

inflateAll :: forall s t. KnownTyp t => KnownShape s => Tensor '[Product s] t -> Tensor s t
inflateAll = knownProduct @s reshape

-- | Reshape a tensor so that the first two dimensions are collapsed
flatten2 :: ∀ m n s t. KnownTyp t => (KnownNat m, KnownNat n, KnownShape s) => Tensor (m ': n ': s) t -> Tensor (m*n ': s) t
flatten2 = prodAssoc @m @n @(Product s) reshape


squeeze0 :: ∀ s t. KnownTyp t => (KnownShape s) => Tensor (1 ': s) t -> Tensor s t
squeeze0 = reshape

-- | Reshape a tensor so that the last two dimensions are collapsed
flattenN2 :: ∀ s m n t. KnownTyp t => (KnownNat m, KnownNat n, KnownShape s) => Tensor (s ++ '[m,n]) t -> Tensor (s ++ '[m*n]) t
flattenN2  = prodHomo @s @'[m,n] $
             prodHomo @s @'[m*n] $
             knownAppend @s @'[m*n] $
             knownAppend @s @'[m,n] $
             reshape

-- | Reshape a tensor so that the first three dimensions are collapsed
flatten3 :: ∀ m n o s t. KnownTyp t => (KnownNat m, KnownNat n, KnownNat o, KnownShape s) => Tensor (m ': n ': o ': s) t -> Tensor (m*n*o ': s) t
flatten3  =  -- (m * (n * (o * Product s)))
             prodAssoc @m @n @(o * Product s) $
             -- (m * n) * (o * Product s)
             prodAssoc @(m * n) @o @(Product s) $
             -- ((m * n) * o) * Product s
             reshape

-- | Reshape a tensor so that the first two dimensions are collapsed
flatten12 :: ∀ m n o s t. KnownTyp t => KnownNat o => (KnownNat m, KnownNat n, KnownShape s) => Tensor (o ': m ': n ': s) t -> Tensor (o ': m*n ': s) t
flatten12 = prodAssoc @m @n @(Product s) reshape

-- | Reshape a tensor so that the first dimension is expanded into two.
inflate2 :: ∀ m n s t. KnownTyp t => (KnownNat m, KnownNat n, KnownShape s) => Tensor (m*n ': s) t -> Tensor (m ': n ': s) t
inflate2 = prodAssoc @m @n @(Product s) reshape

-- | Reshape a tensor so that the first dimension is expanded into three.
inflate3 :: ∀ m n o s t. KnownTyp t => (KnownNat m, KnownNat n, KnownNat o, KnownShape s) => Tensor (m*n*o ': s) t -> Tensor (m ': n ': o ': s) t
inflate3 = -- (m * (n * (o * Product s)))
           prodAssoc @m @n @(o * Product s) $
           -- (m * n) * (o * Product s)
           prodAssoc @(m * n) @o @(Product s) $
           -- ((m * n) * o) * Product s
           reshape

-- | Reshape a tensor so that the first two dimensions are collapsed
inflate12 :: ∀ m n o s t. KnownTyp t => KnownNat o => (KnownNat m, KnownNat n, KnownShape s) => Tensor (o ': m*n ': s) t -> Tensor (o ': m ': n ': s) t
inflate12 = prodAssoc @m @n @(Product s) reshape


-- | Access the last element in a tensor (in the 0th dimension)
last0 :: ∀ n s t. KnownShape s => KnownTyp t => KnownNat n => KnownLen s => T (n ': s) t -> Tensor s t
last0 = nth0 (natVal (Proxy @n) - 1)

-- | Access the nth element in a tensor (in the 0th dimension)
nth0 :: ∀ n s t. KnownTyp t => KnownNat n => KnownShape s => Integer -> T (n ': s) t -> Tensor s t
nth0 i = UnOp (IndexOp 0 i) Unit (typeSShape @(n ': s)) (typeSShape @s)

-- | Access the nth element in a tensor (in the 0th dimension), with a static index
nth0' :: ∀ n m s t. KnownNat m => KnownTyp t => KnownShape s => KnownNat n => KnownLen s => n < m => T (m ': s) t -> Tensor s t
nth0' = nth0 (natVal (Proxy @n))

stackT :: ∀ s0 s (n::Nat) t. KnownShape s => KnownShape s0 => KnownNat n => (KnownLen s0) => V n (T (s0 ++ s) t) -> Tensor (s0 ++ (n ': s)) t
stackT = Stack (typeSShape @s0) (natSat @n) (typeSShape @s)

-- | Concatenate @n@ tensors along the first dimension
stack0 :: ∀ s (n::Nat) t. KnownNat n => KnownShape s => (KnownLen s) => V n (T s t) -> Tensor (n ': s) t
stack0 = stackT @'[]

-- | Concatenate @n@ tensors along the second dimension
stack1 :: ∀ s (n::Nat) m t. KnownNat n => KnownNat m => KnownShape s => (KnownLen s) => V n (T (m ': s) t) -> Tensor (m ': n ': s) t
stack1 = stackT @'[m]

-- | Concatenate @n@ tensors along the last dimension
stackN :: ∀ s (n::Nat) t. KnownNat n => KnownShape s => V n (T s t) -> Tensor (s ++ '[n]) t
stackN = appRUnit @s $
         stackT @s @'[]

-- | Split a tensors into @n@ tensors along the first dimension
unstack0 :: ∀ s (n::Nat) t. KnownTyp t => KnownNat n => KnownShape s => (KnownLen s) => Tensor (n ': s) t -> V n (T s t)
unstack0 x = V [nth0 i x | i <- [0..natVal (Proxy @n) - 1]  ]

-- | Stack a tensor vector. (To be used on literal lists of tensors.)
litStack0 :: KnownShape s => KnownLen xs => TV s t xs -> Tensor (Length xs ': s) t
litStack0 tv = knownSList tv $ stack0 $ toV tv
  where toV :: TV s t xs -> V (Length xs) (T s t)
        toV Unit = V []
        toV (K x :* xs) = V (x : xs') where V xs' = toV xs

permN :: SList s -> Permutation (n ': s) (s ++ '[n])
permN Unit = PermId
permN ((:*) _n s) = PermSwap `PermTrans` PermSkip (permN s)

permN01 :: SList s -> Proxy m -> Proxy n -> Permutation (s ++ [m,n]) (s ++ [n,m])
permN01 Unit _ _ = PermSwap
permN01 ((:*) _n s) m n = PermSkip (permN01 s m n)

-- | Transposition. See the type for the permutation of dimensions.
transposeN :: ∀ s n t. KnownNat n => KnownShape s => T (n ': s) t -> T (s ++ '[n]) t
transposeN  = Transpose typeSShape (permN (typeSList @s))

-- | Transposition. See the type for the permutation of dimensions.
transposeN' :: ∀ s n t. KnownNat n => KnownShape s => T (s ++ '[n]) t -> T (n ': s) t
transposeN' = Transpose (typeSShape @s *: (natSat @n)) (inversePerm (permN (typeSList @s)))

-- | Transposition. See the type for the permutation of dimensions.
transpose01 :: ∀ s m n t. KnownNat n => KnownNat m => KnownShape s => T (m ': n ': s) t -> T (n ': m ': s) t
transpose01 = Transpose typeSShape PermSwap

-- | Transposition. See the type for the permutation of dimensions.
transposeN01 :: ∀ s m n t. KnownNat n => KnownNat m => KnownShape s => T (s ++ [m,n]) t -> T (s ++ [n,m]) t
transposeN01 = Transpose (typeSShape @s .+. typeSShape @'[m,n]) (permN01 (typeSList @s) (Proxy @m) (Proxy @n))

-- | Generate a mask of given length for each sequence.
sequenceMask :: forall maxlen. KnownNat maxlen => Tensor '[] Int32 -> Tensor '[maxlen] TFBool
sequenceMask lens = mapT (lens `lessThan`) (range @maxlen)

-- | Map a function along the first dimension of a tensor
mapT :: forall n s r t u. KnownShape r => KnownNat n => KnownTyp u => KnownLen r => KnownLen s => (T s t -> T r u) ->  T (n ': s) t -> T (n ': r) u
mapT f x = broadcast u False (Proxy @n) (f (Unbroadcast (natSat @n) u x))
  where u = unsafePerformIO newUnique

-- | Map a function along the few first dimensions of a tensor, given by the first type parameter
mapTT :: forall a s t r u. KnownShape r => KnownShape a => KnownTyp u => KnownLen r => KnownShape s => KnownTyp t
  => (T s t -> T r u) ->  T (a ++ s) t -> T (a ++ r) u
mapTT f x = prodHomo @a @r $
            prodHomo @a @s $
            knownProduct @a $
            knownAppend @a @r $
            knownAppend @a @s $
            reshape (mapT @(Product a) f (reshape x))

-- | zip  a function along the first dimension of two tensors tensors
zipWithT :: forall (n :: Nat) (s :: [Nat]) (t :: Typ) (s1 :: [Nat]) (t1 :: Typ) (s2 :: Shape)  (t2 :: Typ).
            KnownShape s2 => KnownNat n => KnownTyp t2
            => (T s t -> T s1 t1 -> T s2 t2)
            -> Tensor (n ': s) t
            -> Tensor (n ': s1) t1
            -> Tensor (n ': s2) t2
zipWithT f x y = broadcast u False (Proxy @n) (f (Unbroadcast (natSat @n) u x) (Unbroadcast (natSat @n) u y))
  where u = unsafePerformIO newUnique

-- | zip  a function along the few first dimensions of a tensor, given by the first type parameter
zipWithTT :: forall a (s :: [Nat]) (s1 :: [Nat]) (s2 :: Shape) (t :: Typ) (t1 :: Typ)  (t2 :: Typ).
            KnownTyp t1 => KnownTyp t => KnownShape s => KnownShape s1 => KnownShape a => KnownShape s2 => KnownTyp t2
            => (T s t -> T s1 t1 -> T s2 t2)
            -> Tensor (a ++ s) t
            -> Tensor (a ++ s1) t1
            -> Tensor (a ++ s2) t2
zipWithTT f x y = 
            prodHomo @a @s1 $
            prodHomo @a @s2 $
            prodHomo @a @s $
            knownProduct @a $
            knownAppend @a @s1 $
            knownAppend @a @s2 $
            knownAppend @a @s $
            reshape (zipWithT @(Product a) f (reshape x) (reshape y))



-- | Size-preserving convolution operation.
convolution :: forall outputChannels filterSpatialShape inChannels s t.
               KnownShape s => KnownNat inChannels => KnownNat outputChannels => KnownShape filterSpatialShape
            => KnownTyp t
            => Length filterSpatialShape <= 3
            => Length s ~ Length filterSpatialShape
            => T (s ++ '[inChannels]) t -- ^ input tensor
            -> T (filterSpatialShape ++ '[inChannels,outputChannels]) t -- ^ filters
            -> T (s ++ '[outputChannels]) t
convolution x filters = knownAppend @s @'[outputChannels] $
                        knownAppend @s @'[inChannels] $
  squeeze0 (Convolution (natSat @1) (natSat @inChannels) (natSat @outputChannels) (typeSShape @filterSpatialShape) (typeSShape @s)
             (expandDim0 x)
             filters)

softmaxInternal :: KnownBits w => SShape s0 -> SShape s1 -> T (s0 ++ s1) ('Typ 'Float w) -> T (s0 ++ s1) ('Typ 'Float w)
softmaxInternal s0 s1 = UnOp (Axis1Op "tf.nn.softmax" [] (sListLength s0 - 1)) Unit (s0 .+. s1) (s0 .+. s1)

-- | Softmax along the first dimension
softmax0 :: forall n s w. KnownBits w => KnownNat n => KnownShape s => T (n ': s) ('Typ 'Float w) -> T (n ': s) ('Typ 'Float w)
softmax0 = softmaxInternal (typeSShape @'[n]) (typeSShape @s)

-- | Softmax along the second dimension
softmax1 :: forall n m s w.  KnownBits w => KnownNat n => KnownNat m => KnownShape s => T (m ': n ': s) ('Typ 'Float w) -> T (m ': n ': s) ('Typ 'Float w)
softmax1 =  softmaxInternal (typeSShape @'[m,n]) (typeSShape @s)

argmaxInternal :: forall n s0 s1 t u. KnownTyp t => KnownBits u => Sat KnownNat n -> SShape s0 -> SShape s1 -> T (s0 ++ (n ': s1)) t -> T (s0 ++ s1) ('Typ 'Int u)
argmaxInternal n s0 s1 = UnOp (Axis1Op "tf.argmax" [("output_type",showTyp @('Typ 'Int u))] (sListLength s0)) Unit (s0 .+. (:*) n s1) (s0 .+. s1)

axisSplitApp :: Axis n s -> (Take n s ++ Drop n s) :~: s
axisSplitApp AxZero = Refl
axisSplitApp (AxSucc n) = case axisSplitApp n of
  Refl -> Refl

-- | Argmax along axis @n@
argmax :: forall m n u s t. (KnownShape s, KnownBits u, KnownNat m, KnownTyp t) => Axis n s -> Tensor (Take n s ++ (m ': Drop n s)) t -> Tensor s ('Typ 'Int u)
argmax n = case axisSplitApp n of
  Refl -> argmaxInternal (natSat @m) (sShapeTake' n (typeSShape @s)) (sShapeDrop' n s)
  where s = typeSShape @s

-- | Argmax along the first dimension
argmax0 :: forall u n s t. (KnownNat n, KnownShape s, KnownBits u, KnownTyp t) => T (n ': s) t -> T s ('Typ 'Int u)
argmax0 = argmaxInternal (natSat @n) Unit (typeSShape @s)

-- | Argmax along the second dimension
argmax1 :: forall u m n s t. (KnownNat n, KnownNat m, KnownShape s, KnownBits u, KnownTyp t) => T (m ': n ': s) t -> T (m ': s) ('Typ 'Int u)
argmax1 = argmaxInternal (natSat @n) (natSat @m :* Unit) (typeSShape @s)
-- argmax1 = mapT argmax0 -- equivalent?

-- | Cast the element type.
cast :: forall u s t. KnownTyp t => KnownShape s => KnownTyp u => T s t -> T s u
cast = UnOp (Simple1Op "tf.cast" [showTyp @ u]) Unit (typeSShape @s) (typeSShape @s)

-- | (dense) softmax cross entropy with logits.
softmaxCrossEntropyWithLogits :: forall numClasses.
     KnownNat numClasses => Tensor '[numClasses] Float32 -- ^ labels
  -> Tensor '[numClasses] Float32 -- ^ logits
  -> Tensor '[] Float32
softmaxCrossEntropyWithLogits  =
  BinOp (Simple2Op "tf.nn.softmax_cross_entropy_with_logits" (Just ("labels","logits"))) -- FIXME: use _v2 for TF 1.5
  Unit (typeSShape @ '[numClasses]) (typeSShape @ '[numClasses]) Unit


-- | Computes sigmoid cross entropy given logits. Measures the
-- probability error in discrete classification tasks in which each
-- class is independent and not mutually exclusive. For instance, one
-- could perform multilabel classification where a picture can contain
-- both an elephant and a dog at the same time. See
-- https://www.tensorflow.org/api_docs/python/tf/nn/sigmoid_cross_entropy_with_logits
sigmoidCrossEntropyWithLogits :: forall s w.
  KnownBits w => KnownShape s => Tensor s (Flt w) -- ^ labels
                              -> Tensor s (Flt w) -- ^ logits
                              -> Tensor s (Flt w)
sigmoidCrossEntropyWithLogits  =
  BinOp (Simple2Op "tf.nn.sigmoid_cross_entropy_with_logits" (Just ("labels","logits")))
        Unit (typeSShape @s) (typeSShape @s) (typeSShape @s)

-- | sparse softmax cross entropy with logits.
sparseSoftmaxCrossEntropyWithLogits :: forall numClasses t.
   KnownNat numClasses => KnownBits t =>
  Tensor '[] Int32                   -- ^ desired label
  -> Tensor '[numClasses] (Flt t) -- ^ predictions for each label
  -> Tensor '[] (Flt t) 
sparseSoftmaxCrossEntropyWithLogits  =
  BinOp (Simple2Op "tf.nn.sparse_softmax_cross_entropy_with_logits" (Just ("labels","logits")))
     Unit (typeSShape @ '[]) (typeSShape @ '[numClasses]) (typeSShape @ '[])

-- | One hot vector along axis 0
oneHot0 :: forall numClasses w s t. KnownNat numClasses => KnownBits t => KnownBits w =>
  (KnownShape s) =>
  Tensor s ('Typ 'Int w) -> Tensor (numClasses ': s) (Flt t)
oneHot0 = UnOp (Axis1Op "tf.one_hot" [("dtype",showTyp @(Flt t))] 0) Unit s
                 (natSat @numClasses :* s)
  where s = typeSShape @s

-- | One hot vector along axis 1
oneHot1 :: forall numClasses w s m t. KnownBits w =>KnownShape s => KnownNat numClasses => KnownNat m => KnownBits t => Tensor (m ': s) ('Typ 'Int w) -> Tensor (m ': numClasses ': s) (Flt t)
oneHot1 = mapT oneHot0

-- | Generate a random tensor whose distribution is given. A new noise
-- is sampled for each element in a batch.
noise :: KnownShape s => Distribution s t -> Gen (T s t)
noise d = do
  noiseId <- newId -- necessary for correct broadcasting behaviour
  return $ Noise noiseId Unit typeSShape d

-- | Clip a tensor
clipByValue :: KnownShape s => KnownBits t => Float -> Float -> T s (Flt t) -> T s (Flt t)
clipByValue lo hi = UnOp (Simple1Op "tf.clip_by_value" [float lo,float hi]) Unit typeSShape typeSShape

-- | (where_ c x y)[i] = if c[i] then x[i] else y[i]
where_ :: T s TFBool -> T s t -> T s t -> T s t
where_ = Where


-- | Selection of a tensor (note: this is a strict operation)
if_ :: Scalar TFBool -> T s t -> T s t -> T s t
if_ = If

-- | @(gather x ix)[k] = x[ix[k]]@. See https://www.tensorflow.org/api_docs/python/tf/gather
gather :: forall n indexShape s t. KnownShape s => KnownNat n => KnownShape indexShape => T (n ': s) t -> T indexShape Int32 -> T (indexShape ++ s) t
gather = Gather typeSShape Unit (natSat @n) typeSShape
-- gather params ix = GatherND (typeSShape @'[n]) (typeSShape @s) (typeSShape @indexShape) params $
--   prodHomo @indexShape @'[1] $
--   (reshapeAuto ix)

-- | @(lookup i xs) = xs[i]@. This function returns an element of a
-- tensor at a dynamic index. This is a version of 'gather'
-- specialised to a scalar index.
lookupT :: KnownShape xs => KnownNat n => Scalar Int32 -> Tensor (n ': xs) t -> Tensor xs t
lookupT ix xs = gather xs ix

-- | x by y maxpool layer.
maxPool2D :: forall windowx windowy height width channels t.
             KnownNat height => KnownNat width => KnownNat channels => (KnownNat windowx, KnownNat windowy, KnownBits t) =>
             T '[windowx*width,windowy*height,channels] (Flt t) -> T '[width,height,channels] (Flt t)
maxPool2D x = squeeze0 (Pool (natSat @1) (typeSShape @'[windowx,windowy]) MaxPool (natSat @channels) (typeSShape @'[width,height]) (expandDim0 x))

-- | maxpool layer. window size is the first type argument.
maxPool1D :: forall window width channels t.
             KnownNat width => KnownNat channels => (KnownNat window,KnownBits t) =>
             T '[window*width,channels] (Flt t) -> T '[width,channels] (Flt t)
maxPool1D x = squeeze0 (Pool (natSat @1) (typeSShape @'[window]) MaxPool (natSat @channels) (typeSShape @'[width]) (expandDim0 x))


