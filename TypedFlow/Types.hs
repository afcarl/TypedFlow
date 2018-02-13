{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE UndecidableSuperClasses #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.KnownNat.Solver #-}
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
{-# LANGUAGE OverloadedStrings #-}

module TypedFlow.Types where

import Text.PrettyPrint.Compact hiding (All,Last,Product,Sum)
import GHC.TypeLits
import Unsafe.Coerce
import Data.Proxy
import Control.Monad.State
import Data.Char (toLower)
import Data.Kind (Constraint)
import Data.Type.Equality

data Sat (a :: k -> Constraint) (b::k) where
  Sat :: a b => Sat a b

type DOC = Doc ()

type i < j = CmpNat i j ~ 'LT
-- type i <= j = (i <=? j) ~ 'True

type family Product xs where
  Product '[] = 1
  Product (x ': xs) = x * Product xs

type family Sum xs where
  Sum '[] = 0
  Sum (x ': xs) = x + Sum xs


type family (++) xs ys where
   '[] ++  xs       = xs
   (x ': xs) ++ ys       = x ': (xs ++ ys)

type family Tail xs where
  Tail (x ': xs) = xs

type family Last xs where
  Last '[x] = x
  Last (x ': xs) = Last xs

type family Init xs where
  Init '[x] = '[]
  Init (x ': xs) = x ': Init xs

-- Some proofs.

-- initLast' :: forall s k. ((Init s ++ '[Last s]) ~ s => k) -> k
-- initLast' k = unsafeCoerce# k -- why not?


succPos' :: CmpNat 0 (1 + n) :~: 'LT
succPos' = unsafeCoerce Refl

succPos :: forall n k. ((0 < (1+n)) => k) -> k
succPos k = case succPos' @n  of
  Refl -> k


plusComm' :: forall x y. (x + y) :~: (y + x)
plusComm' = unsafeCoerce Refl

plusComm :: forall x y k. ((x + y) ~ (y + x) => k) -> k
plusComm k = case plusComm' @x @y of
  Refl -> k

plusAssoc' :: forall x y z. (x + y) + z :~: x + (y + z)
plusAssoc' = unsafeCoerce Refl

plusAssoc :: forall x y z k. (((x + y) + z) ~ (x + (y + z)) => k) -> k
plusAssoc k = case plusAssoc' @x @y @z of
  Refl -> k

prodAssoc' :: forall x y z. (x * y) * z :~: x * (y * z)
prodAssoc' = unsafeCoerce Refl

prodAssoc :: forall (x::Nat) (y::Nat) (z::Nat) k. (((x * y) * z) ~ (x * (y * z)) => k) -> k
prodAssoc k = case prodAssoc' @x @y @z of
  Refl -> k

prodHomo' ::  forall x y. Product (x ++ y) :~: Product x * Product y
prodHomo' = unsafeCoerce Refl

prodHomo ::  forall x y k. ((Product (x ++ y) ~ (Product x * Product y)) => k) -> k
prodHomo k = case prodHomo' @x @y of Refl -> k

knownProduct' :: forall s k. All KnownNat s => SList s -> (KnownNat (Product s) => k) -> k
knownProduct' LZ k = k
knownProduct' (LS _ n) k = knownProduct' n k

knownProduct :: forall s k. KnownShape s => (KnownNat (Product s) => k) -> k
knownProduct = knownProduct' @s shapeSList

appEmpty' :: (xs ++ '[]) :~: xs
appEmpty' = unsafeCoerce Refl

appEmpty :: forall xs k. (((xs ++ '[]) ~ xs) => k) -> k
appEmpty k = case appEmpty' @xs of Refl -> k

initLast' :: forall s k. SList s -> ((Init s ++ '[Last s]) ~ s => k) -> k
initLast' LZ _ = error "initLast': does not hold on empty lists"
initLast' (LS _ LZ) k = k
initLast' (LS _ (LS y ys)) k = initLast' (LS y ys) k

initLast :: forall s k. KnownShape s => ((Init s ++ '[Last s]) ~ s => k) -> k
initLast = initLast' @s shapeSList

knownLast' :: All KnownNat s => SList s -> (KnownNat (Last s) => k) -> k
knownLast' LZ _ = error "knownLast: does not hold on empty lists"
knownLast' (LS _ LZ) k = k
knownLast' (LS _ (LS y xs)) k = knownLast' (LS y xs) k

knownLast :: forall s k. KnownShape s => (KnownNat (Last s) => k) -> k
knownLast = knownLast' @s shapeSList

splitApp' :: forall ys xs k. SList xs -> ((Take (PeanoLength xs) (xs ++ ys) ~ xs,
                                              Drop (PeanoLength xs) (xs ++ ys) ~ ys) => k) -> k
splitApp' LZ k = k
splitApp' (LS _ n) k = splitApp' @ys n k

splitApp :: forall xs ys k. KnownLen xs => ((Take (PeanoLength xs) (xs ++ ys) ~ xs,
                                             Drop (PeanoLength xs) (xs ++ ys) ~ ys) => k) -> k
splitApp = splitApp' @ys (shapeSList @xs)

knownAppend' :: forall t s k. (All KnownNat s, KnownShape t) => SList s -> (KnownShape (s ++ t) => k) -> k
knownAppend' LZ k = k
knownAppend' (LS _ n) k = knownAppend' @t n k

knownAppend :: forall s t k.  (KnownShape s, KnownShape t) => (KnownShape (s ++ t) => k) -> k
knownAppend = knownAppend' @t (shapeSList @s)

-- knownCons :: proxy x -> SList xs -> (KnownLen (x ': xs) => k) -> k
-- knownCons _ LZ k = k
-- knownCons _ (LS x n) k = knownCons x n k

-- knownFmap' :: forall f xs. SList xs -> SList (Ap (FMap f) xs)
-- knownFmap' LZ = LZ
-- knownFmap' (LS x n) = LS Proxy (knownFmap' @f n)

knownSList :: SList xs -> (KnownLen xs => k) -> k
knownSList LZ k = k
knownSList (LS _ n) k = knownSList n k

type family Length xs where
  Length '[] = 0
  Length (x ': xs) = 1 + Length xs

type family Reverse' xs ys where
  Reverse' '[] ys = ys
  Reverse' (x ': xs) ys = Reverse' xs (x ': ys )

type family Reverse xs where
  Reverse xs = Reverse' xs '[]

newtype V (n::Nat) a = V [a]
  deriving (Functor, Foldable, Traversable)

lastV :: V (1+n) a -> a
lastV (V xs) = last xs

instance KnownNat n => Applicative (V n) where
  pure = V . replicate (fromIntegral (natVal (Proxy @n)))
  V fs <*> V xs = V (zipWith ($) fs xs)

-- From: https://www.cs.ox.ac.uk/projects/utgp/school/andres.pdf
data NP f (xs :: [k]) where
  Unit :: NP f '[]
  (:*) :: f x -> NP f xs -> NP f (x ': xs)

newtype I a = I a
newtype K a x = K a
type HList = NP I

pattern HSingle :: f a -> NP f '[a]
pattern HSingle x = x :* Unit

pattern VecSing :: Tensor s t -> HTV t '[s]
pattern VecSing t1 = F t1 :* Unit

pattern VecPair :: Tensor s t -> Tensor s' t -> HTV t '[s,s']
pattern VecPair t1 t2 = F t1 :* F t2 :* Unit

pattern VecTriple :: Tensor s t -> Tensor s' t -> Tensor s3 t -> HTV t '[s,s',s3]
pattern VecTriple t1 t2 t3 = F t1 :* F t2 :* F t3 :* Unit

type family All (c :: k -> Constraint) (xs :: [k]) :: Constraint where
  All c '[] = ()
  All c (x ': xs) = (c x, All c xs)

class Fun (c :: k -> Constraint)  where
  type Ap c (t :: k) :: l

class Cons (x :: k) (xs :: [k])
instance Fun (Cons x) where type Ap (Cons x) xs = x ': xs

class Snoc (x :: k) (xs :: [k])
instance Fun (Snoc x) where
  type Ap (Snoc x) '[] = '[x]
  type Ap (Snoc x) (y ': ys) = y ': Ap (Snoc x) ys

class FMap (c :: k -> Constraint) (xs :: [k]) where

instance Fun c => Fun (FMap c)  where
  type Ap (FMap c) '[] = '[]
  type Ap (FMap c) (x ': xs) = Ap c x ': Ap (FMap c) xs

-- type family All2 (c :: k -> l -> Constraint) (xs :: [k]) (ys :: [l]) :: Constraint where
--   All2 c '[] '[] = ()
--   All2 c (x ': xs) (y ': ys) = (c x y, All2 c xs ys)
--   All2 c '[] (y ': ys) = 'True ~ 'False
--   All2 c (y ': ys) '[] = 'True ~ 'False

-- | Flip at type level
newtype F g t s = F {fromF :: g s t}

-- | Heterogeneous tensor vector with the same kind of elements
type HTV t = NP (F T t)

data Pair a b = a :& b

type family Fst (x :: Pair a b) where Fst (x ':& y) = x
type family Snd (x :: Pair a b) where Snd (x ':& y) = y

newtype Uncurry g (s :: Pair a b) = Uncurry {fromUncurry :: g (Fst s) (Snd s)}

type HHTV = NP (Uncurry T)

hhead :: NP f (x ': xs) -> f x
hhead (x :* _) = x

htail :: NP f (x ': xs) -> NP f xs
htail (_ :* xs) = xs

htmap :: forall f ss t u. (forall s. Tensor s t -> Tensor (Ap f s) u) -> HTV t ss -> HTV u (Ap (FMap f) ss)
htmap _ Unit = Unit
htmap f (F x :* xs) = F (f x) :* htmap @f f xs

-- htmap' :: forall f ss t u. All KnownShape ss => (forall s. KnownShape s => Tensor (Ap f s) t -> Tensor s u) -> SList ss -> HTV t (Ap (FMap f) ss) -> HTV u ss 
-- htmap' _ LZ Unit = Unit
-- htmap' f (LS _ n)(F x :* xs) = F (f x) :* htmap' @f f n xs

hmap :: (forall x. f x -> g x) -> NP f xs -> NP g xs
hmap _ Unit = Unit
hmap f (x :* xs) = f x :* hmap f xs

hendo :: NP Endo xs -> HList xs -> HList xs
hendo Unit Unit = Unit
hendo (Endo f :* fs) (I x :* xs) = (I (f x) :* hendo fs xs)

happ :: NP f xs -> NP f ys -> NP f (xs ++ ys)
happ Unit xs = xs
happ (x :* xs) ys = x :* (happ xs ys)

data Both f g x = Both (f x) (g x)

hzip :: NP f xs -> NP g xs -> NP (Both f g) xs
hzip = hzipWith Both

hzipWith :: (forall x. f x -> g x -> h x) -> NP f xs -> NP g xs -> NP h xs
hzipWith _ Unit Unit = Unit
hzipWith f (x :* xs) (y :* ys) = f x y :* hzipWith f xs ys

hfor_ :: Monad m => NP f xs -> (forall x. f x -> m a) -> m ()
hfor_ Unit _  = return ()
hfor_ (x :* xs) f = f x >> hfor_ xs f

htoList :: NP (K a) xs -> [a]
htoList Unit = []
htoList (K x :* xs) = x : htoList xs

hsplit' :: SPeano n -> NP f xs -> (NP f (Take n xs), NP f (Drop n xs))
hsplit' SZero xs = (Unit,xs)
hsplit' (SSucc _n) Unit = (Unit,Unit)
hsplit' (SSucc n) (x :* xs) = case hsplit' n xs of
  (l,r) -> (x :* l,r)

hsplit :: forall xs ys f. KnownLen xs => NP f (xs++ys) -> (NP f xs, NP f ys)
hsplit xys = splitApp @xs @ys (hsplit' (shapePeano @xs) xys)

hsnoc :: NP f xs -> f x -> NP f (xs ++ '[x])
hsnoc xs x = happ xs (x :* Unit)

infixr 5 :*

data Peano = Zero | Succ Peano

type Dim0 = 'Zero
type Dim1 = 'Succ Dim0
type Dim2 = 'Succ Dim1
type Dim3 = 'Succ Dim2

type Axis0 = 'Zero
type Axis1 = 'Succ Dim0
type Axis2 = 'Succ Dim1
type Axis3 = 'Succ Dim2

class KnownPeano n where peanoInt :: Integer
instance KnownPeano 'Zero where peanoInt = 0
instance KnownPeano n => KnownPeano ('Succ n) where peanoInt = 1 + (peanoInt @n)

data SPeano n where
  SZero :: SPeano 'Zero
  SSucc :: SPeano n -> SPeano ('Succ n)

data Vec (n::Peano) a where
  VNil  :: Vec 'Zero a
  VCons :: a -> Vec n a -> Vec ('Succ n) a

vecToList :: Vec n a -> [a]
vecToList VNil = []
vecToList (VCons x xs) = x : vecToList xs

-- type family App n (xs :: Vec n a) ys where
--    App 'Zero 'VNil  xs            =  xs
--    App ('Succ n) ('VCons x xs) ys =  x ': App n xs ys

type family Take n xs where
   Take 'Zero xs            =  '[]
   Take ('Succ n) '[] =  '[]
   Take ('Succ n) (x ': xs) =  x ': Take n xs

type family Drop n xs where
   Drop 'Zero xs            = xs
   Drop ('Succ n) '[]       = '[]
   Drop ('Succ n) (x ': xs) = Drop n xs

type family At n xs where
  At 'Zero (x ': xs) = x
  At ('Succ n) (x ': xs) = At n xs

data Kind = Float | Int | Bool deriving Show
data NBits = B32 | B64 | B1 deriving Show
data Typ = Typ Kind NBits

type Flt t = 'Typ 'Float t
type Float32 = 'Typ 'Float 'B32
type Int32 = 'Typ 'Int 'B32
type Int64 = 'Typ 'Int 'B64
type TFBool = 'Typ 'Bool 'B1
type Scalar t = T '[] t

instance Show Typ where
  show (Typ Bool _)= "tf.bool"
  show (Typ k l) = "tf." ++ map toLower (show k) ++ drop 1 (show l)

type Shape = [Nat]



data SNat (n :: Nat) where
  SNat :: KnownNat n => Proxy n -> SNat n

class (KnownLen s, All KnownNat s) => KnownShape s where

instance KnownShape '[]
instance (KnownNat x, KnownShape xs) => KnownShape (x ': xs)

class KnownTyp t where
  typVal :: Typ

class KnownBits t where
  bitsVal :: NBits

instance KnownBits 'B1 where bitsVal = B1
instance KnownBits 'B32 where bitsVal = B32
instance KnownBits 'B64 where bitsVal = B64

instance (KnownBits l, KnownKind k) => KnownTyp ('Typ k l) where
  typVal = Typ (kindVal @k) (bitsVal @l)

class Pretty t where
  pretty :: t -> DOC

instance Pretty Bool where pretty = bool
instance Pretty Float where pretty = float
instance Pretty Int where pretty = int
class (Pretty (HostType t)) => KnownKind t where
  kindVal :: Kind
  type HostType t

instance KnownKind 'Bool where
  kindVal = Bool
  type HostType 'Bool = Bool
instance KnownKind 'Float where
  kindVal = Float
  type HostType 'Float = Float
instance KnownKind 'Int where
  kindVal = Int
  type HostType 'Int = Int

type SList = SList' Proxy

data SList' f s where
  LZ :: SList' f '[]
  LS :: forall x xs f. f x -> SList' f xs -> SList' f (x ': xs)

type family PeanoLength xs :: Peano where
  PeanoLength '[] = 'Zero
  PeanoLength (x ': xs) = 'Succ (PeanoLength xs)


withKnownNat :: forall k. Int -> (forall (n::Nat). KnownNat n => Proxy n -> k) -> k
withKnownNat 0 f = f (Proxy @0)
withKnownNat 1 f = f (Proxy @1)
withKnownNat n f = withKnownNat (n `div` 2) (if n `mod` 2 == 0 then f2x else f2x1)
  where f2x,f2x1 :: forall (n::Nat). KnownNat n => Proxy n -> k
        f2x  _ = f (Proxy @(n*2))
        f2x1 _ = f (Proxy @(n*2+1))

-- Probably a GHC bug:
-- withKnownNat'' :: forall k. Int -> (forall (n::Nat). KnownNat n => k) -> k
-- withKnownNat'' 0 f = f @0
-- withKnownNat'' n f = withKnownNat'' (n-1) fsucc
--   where fsucc :: forall (n::Nat). KnownNat n =>  k
--         fsucc = f @(n+1)

-- This also fails:
-- appProxy :: forall (n::Nat) k. KnownNat n => Proxy n -> (forall (m::Nat). KnownNat m => k) -> k
-- appProxy f _ = f @n

-- withKnownNat :: forall k. Int -> (forall (n::Nat). KnownNat n => k) -> k
-- withKnownNat n f = withKnownNat' n (\proxy -> appProxy proxy f)

class KnownLen s where
  listLen :: Integer -- CLEAN: re
  shapePeano :: SPeano (PeanoLength s)
  shapeSList :: SList s

instance KnownLen '[] where
  listLen = 0
  shapePeano = SZero
  shapeSList = LZ
  
instance KnownLen xs => KnownLen (x ': xs) where
  listLen = 1 Prelude.+ listLen @ xs
  shapePeano = SSucc (shapePeano @xs)
  shapeSList = LS Proxy (shapeSList @xs)

shapeSListProxy :: KnownLen xs => proxy xs -> SList xs
shapeSListProxy _ = shapeSList

shapeProxySList :: KnownLen xs => SList xs -> Proxy xs 
shapeProxySList _ = Proxy


shapeToList' :: All KnownNat s => SList s -> [Integer]
shapeToList' LZ = []
shapeToList' (LS x xs) = natVal x : shapeToList' xs

shapeToList :: ∀(s::Shape). KnownShape s => [Integer]
shapeToList = shapeToList' (shapeSList @ s)

rememberNat :: SNat n -> (KnownNat n => r) -> r
rememberNat (SNat _) k = k

type None = 514229 --  fibonnaci prime.
-- type None = 0 - 1 -- GHC does not like negative Nats.
-- Using a maybe type would be a RPITA.


--------------------------------
-- Generation Effects

data ParamInfo = ParamInfo {paramName :: String
                           ,paramShape :: [Integer]
                           ,paramDType :: Typ
                           ,paramVar   :: forall s t. (KnownShape s, KnownTyp t) => Tensor s t}
data GState = GState {nextVar :: Integer, -- ^ next free variable
                      genText :: DOC,
                      genParams :: [ParamInfo], -- ^ optimizable parameters
                      genRegularizers :: [Scalar Float32], -- ^ accumulated regularizers
                      genTrainingPlaceholder :: Scalar TFBool, -- ^ flag which is true when training
                      genPeeks :: [(String,UntypedExpression)]}
newtype Gen x = Gen {fromGen :: State GState x} deriving (Monad, MonadState GState, Functor, Applicative)

--------------------------
-- Tensors

type UntypedExpression = DOC

data T (s :: Shape) (t :: Typ) where
  SimpleBroadcast :: Proxy s0 -> Proxy m ->  Proxy s1 -> T (s0 ++  s1) t -> T (s0 ++ (m ': s1)) t
  T :: UntypedExpression -> T s t
  BinOp :: BinOp -> SList s0 -> Proxy s1 -> Proxy s2 -> Proxy s3 -> T (s0 ++ s1) t -> T (s0 ++ s2) t -> T (s0 ++ s3) u
  UnOp :: UnOp -> SList s0 -> Proxy s1 -> Proxy s2 -> T (s0 ++ s1) t -> T (s0 ++ s2) u
  Unbroadcast :: KnownNat n => Proxy n -> T (n ': s) t -> T s t
  -- ReduceBy :: String -> SList s0 -> Proxy m -> SList s1 -> T (s0 ++ (m ': s1)) t -> T (s0 ++ s1) t
  ReshapeTo :: SList s -> T s0 t -> T s t
  Transpose :: Permutation s0 s -> T s0 t -> T s t
  Share :: T s t -> T s t
  Stack :: SList s0 -> Proxy m -> Proxy s1 -> V m (T (s0 ++ s1) t) -> T (s0 ++ (m ': s1)) t
  -- Index :: Int -> SList s0 -> Proxy m ->  SList s1 -> T (s0 ++ (m ': s1))t -> T (s0 ++ s1) t
  Concat :: SList s0 -> Proxy m -> Proxy o -> SList s1 -> T (s0 ++ (m ': s1))t -> T (s0 ++ (o ': s1))t -> T (s0 ++ ((m+o) ': s1))t
  Gather :: SList indexShape -> SList s0 -> Proxy m -> SList s1 -> T (s0 ++ (m ': s1)) t -> T indexShape ('Typ 'Int w0) -> T (s0 ++ indexShape ++ s1) t
  -- MatMul :: KnownLen s => Proxy m -> Proxy n ->  Proxy o -> SList s -> T (s ++ '[n,o]) t -> T (s ++ [o,m]) t -> T (s ++ [n,m]) t
  ArgMax :: SList s0 -> Proxy m -> Proxy s1 -> T (s0 ++ (m ': s1)) t' -> T (s0 ++ s1) ('Typ 'Int w)
  SoftMax :: SList s0 -> Proxy m ->  Proxy s1 -> T (s0 ++ (m ': s1)) t -> T (s0 ++ (m ': s1)) t
  Where :: T s TFBool  -> T s t -> T s t -> T s t
  Convolution :: Proxy bs -> Proxy inChannels -> Proxy outChannels -> SList filterSpatialShape
            -> T (bs ': filterSpatialShape ++ '[inChannels]) t -- ^ input tensor (batched)
            -> T (filterSpatialShape ++ '[inChannels,outChannels]) t -- ^ filters
            -> T (bs ': filterSpatialShape ++ '[outChannels]) t

type Tensor shape = T shape

data UnOp  = Simple1Op String | SliceOp Integer Integer | Axis1Op String Integer | IndexOp {indexOpAxis :: Integer, indexOpIndex :: Integer}
data BinOp = Simple2Op String | Axis2Op String Integer

data Permutation (s :: [k]) (t :: [k]) where
  PermId :: Permutation s t
  PermSkip :: Permutation s t -> Permutation (n ': s) (n ': t)
  PermSwap :: Permutation (n ': m ': s) (m ': n ': s)
  PermTrans :: Permutation s t -> Permutation t u -> Permutation s u

