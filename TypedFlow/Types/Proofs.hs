{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveFoldable #-}
{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE DeriveTraversable #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE InstanceSigs #-}
{-# LANGUAGE MagicHash #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeInType #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE UndecidableSuperClasses #-}
{-# LANGUAGE UnicodeSyntax #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.KnownNat.Solver #-}

module TypedFlow.Types.Proofs where


import Prelude hiding (RealFrac(..))
import GHC.TypeLits
import Data.Proxy
import TypedFlow.Types hiding (T)
import Data.Type.Equality
import Unsafe.Coerce

testEqual :: KnownNat m => KnownNat n => Proxy m -> Proxy n -> Maybe (m :~: n)
testEqual m n = if natVal m == natVal n then Just (unsafeCoerce Refl) else Nothing

productS :: forall s. SShape s -> Sat KnownNat (Product s)
productS s = knownSShape s $ knownProduct @s $ Sat

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

plusAssocS :: forall x y z k px py pz. px x -> py y -> pz z -> (((x + y) + z) ~ (x + (y + z)) => k) -> k
plusAssocS _ _ _ k = case plusAssoc' @x @y @z of
  Refl -> k

prodAssoc' :: forall x y z. (x * y) * z :~: x * (y * z)
prodAssoc' = unsafeCoerce Refl

prodAssoc :: forall (x::Nat) (y::Nat) (z::Nat) k. (((x * y) * z) ~ (x * (y * z)) => k) -> k
prodAssoc k = case prodAssoc' @x @y @z of
  Refl -> k

prodAssocS :: forall x y z k px py pz. px x -> py y -> pz z -> (((x * y) * z) ~ (x * (y * z)) => k) -> k
prodAssocS _ _ _ k = case prodAssoc' @x @y @z of
  Refl -> k

-- Some proofs.

-- initLast' :: forall s k. ((Init s ++ '[Last s]) ~ s => k) -> k

-- initLast' k = unsafeCoerce# k -- why not?

termCancelation' :: forall a b. (a + b) - b :~: a
termCancelation' = unsafeCoerce Refl

termCancelation  :: forall a b k. ((((a + b) - b) ~ a) => k) -> k
termCancelation k = case termCancelation' @a @b of Refl -> k

plusMono :: forall a b k. ((a <= (a+b)) => k) -> k
plusMono k = case plusMono' of Refl -> k
  where plusMono' :: (a <=? (a+b)) :~: 'True
        plusMono' = unsafeCoerce Refl

succPos' :: (1 <=? 1+j) :~: 'True
  -- CmpNat 0 (1 + n) :~: 'LT
succPos' = unsafeCoerce Refl

succPos :: forall n k. ((0 < (1+n)) => k) -> k
succPos k = case succPos' @n  of
  Refl -> k


prodHomo' ::  forall x y. Product (x ++ y) :~: Product x * Product y
prodHomo' = unsafeCoerce Refl

prodHomo ::  forall x y k. ((Product (x ++ y) ~ (Product x * Product y)) => k) -> k
prodHomo k = case prodHomo' @x @y of Refl -> k

prodHomoS ::  forall x y k px py. px x -> py y -> ((Product (x ++ y) ~ (Product x * Product y)) => k) -> k
prodHomoS _ _ k = case prodHomo' @x @y of Refl -> k

knownProduct' :: forall s k. All KnownNat s => SList s -> (KnownNat (Product s) => k) -> k
knownProduct' Unit k = k
knownProduct' ((:*) _ n) k = knownProduct' n k

knownProduct :: forall s k. KnownShape s => (KnownNat (Product s) => k) -> k
knownProduct = knownProduct' @s typeSList


takeDrop' :: forall s n. (PeanoNat n <= Length s) => SPeano n -> (Take n s ++ Drop n s) :~: s
takeDrop' _ = unsafeCoerce Refl

takeDrop :: forall s n k. (PeanoNat n <= Length s) => SPeano n -> ((Take n s ++ Drop n s) ~ s => k) -> k
takeDrop n k = case takeDrop' @s n of Refl -> k

lengthHomo' :: forall x y. Length (x ++ y) :~: Length x + Length y
lengthHomo' = unsafeCoerce Refl

lengthHomoS :: forall x y k proxyx proxyy. proxyx x -> proxyy y -> ((Length (x ++ y) ~ (Length x + Length y)) => k) -> k
lengthHomoS _ _ k = case lengthHomo' @x @y of Refl -> k

lengthInit' :: forall s k. (0 < Length s) => SList s -> ((Length (Init s) + 1) ~ Length s => k) -> k
lengthInit' x k = case lengthHomo' @(Init s) @'[Last s] of
  Refl -> initLast' x k

lengthInit :: forall s k. KnownLen s => (0 < Length s) => ((Length (Init s) + 1) ~ Length s => k) -> k
lengthInit = lengthInit' (typeSList @s)

incrPos' :: forall x. (1 <=? x+1) :~: 'True
incrPos' = unsafeCoerce Refl

incrPos :: forall x k. ((0 < (x + 1)) => k) -> k
incrPos k = case incrPos' @x of Refl -> k

incrCong' :: forall x y. ((x+1) ~ (y+1)) => x :~: y
incrCong' = unsafeCoerce Refl

incrCong :: forall x y k. ((x+1) ~ (y+1)) => ((x ~ y) => k) -> k
incrCong k = case incrCong' @x @y of Refl -> k


initLast' :: forall s k. {-(0 < Length s) => FIXME -} SList s -> ((Init s ++ '[Last s]) ~ s => k) -> k
initLast' Unit _ = error "initLast': does not hold on empty lists"
initLast' ((:*) _ Unit) k = k
initLast' ((:*) _ ((:*) y ys)) k = initLast' ((:*) y ys) k

initLast :: forall s k. KnownShape s => ((Init s ++ '[Last s]) ~ s => k) -> k
initLast = initLast' @s typeSList

appRUnit' :: forall s. (s ++ '[]) :~: s
appRUnit' = unsafeCoerce Refl

appRUnit :: forall s k. (((s ++ '[]) ~ s) => k) -> k
appRUnit k = case appRUnit' @s of
  Refl -> k

appAssoc' ::  ((xs ++ ys) ++ zs) :~: (xs ++ (ys ++ zs))
appAssoc' = unsafeCoerce Refl

appAssoc :: forall xs ys zs k. (((xs ++ ys) ++ zs) ~ (xs ++ (ys ++ zs)) => k) -> k
appAssoc k = case appAssoc' @xs @ys @zs of Refl -> k

appAssocS :: forall xs ys zs k proxy1 proxy2 proxy3.
             proxy1 xs -> proxy2 ys -> proxy3 zs -> (((xs ++ ys) ++ zs) ~ (xs ++ (ys ++ zs)) => k) -> k
appAssocS _ _ _  k = case appAssoc' @xs @ys @zs of Refl -> k


knownLast' :: All KnownNat s => SList s -> (KnownNat (Last s) => k) -> k
knownLast' Unit _ = error "knownLast: does not hold on empty lists"
knownLast' ((:*) _ Unit) k = k
knownLast' ((:*) _ ((:*) y xs)) k = knownLast' ((:*) y xs) k

knownLast :: forall s k. KnownShape s => (KnownNat (Last s) => k) -> k
knownLast = knownLast' @s typeSList

knownInit' :: All KnownNat s => SList s -> (KnownShape (Init s) => k) -> k
knownInit' Unit _ = error "knownLast: does not hold on empty lists"
knownInit' ((:*) _ Unit) k = k
knownInit' ((:*) _ ((:*) y xs)) k = knownInit' ((:*) y xs) k

knownInit :: forall s k. KnownShape s => (KnownShape (Init s) => k) -> k
knownInit = knownInit' @s typeSList

knownTail' :: forall x s k. All KnownNat s => SList (x ': s) -> (KnownShape s => k) -> k
knownTail' ((:*) _ Unit) k = k
knownTail' ((:*) _ ((:*) y xs)) k = knownTail' ((:*) y xs) k

knownTail :: forall s x xs k. (s ~ (x ': xs), KnownShape s) => (KnownShape xs => k) -> k
knownTail = knownTail' @x @xs typeSList

knownAppendS :: forall s t pt k. (All KnownNat s, KnownShape t) => SList s -> pt t -> (KnownShape (s ++ t) => k) -> k
knownAppendS Unit _t k = k
knownAppendS ((:*) _ n) t k = knownAppendS n t k

knownAppend :: forall s t k.  (KnownShape s, KnownShape t) => (KnownShape (s ++ t) => k) -> k
knownAppend = knownAppendS (typeSList @s) (Proxy @t)


-- knownFmap' :: forall f xs. SList xs -> SList (Ap (FMap f) xs)
-- knownFmap' Unit = Unit
-- knownFmap' ((:*) x n) = (:*) Proxy (knownFmap' @f n)

knownSList :: NP proxy xs -> (KnownLen xs => k) -> k
knownSList Unit k = k
knownSList ((:*) _ n) k = knownSList n k

knownSShape :: SShape xs -> (KnownShape xs => k) -> k
knownSShape Unit k = k
knownSShape ((:*) Sat s) k = knownSShape s k

data DimExpr (a :: Nat) (x :: Nat) (b :: Nat) where
  ANat :: Sat KnownNat x -> DimExpr a x (a * x)
  (:*:) :: DimExpr a x b -> DimExpr b y c -> DimExpr a (x*y) c

knownOutputDim :: forall a x b. Sat KnownNat a -> DimExpr a x b -> Sat KnownNat b
knownOutputDim a (ANat x) = satMul a x
knownOutputDim a (x :*: y) = knownOutputDim (knownOutputDim a x) y

dimSat :: DimExpr a x b -> Sat KnownNat x
dimSat (ANat s) = s
dimSat (x :*: y) = dimSat x `satMul` dimSat y

normDim :: forall ws xs ys. DimExpr ws xs ys -> (ws * xs) :~: ys
normDim (ANat _) = Refl
normDim (a :*:b) = case normDim a of Refl -> case normDim b of Refl -> prodAssocS (Proxy @ws) (dimSat a) (dimSat b) Refl

data ShapeExpr (a :: Nat) (x :: Shape) (b :: Nat) where
  Single :: DimExpr a x b -> ShapeExpr a '[x] b
  AShape :: SShape x -> ShapeExpr a x (a * Product x)
  (:++:) :: ShapeExpr a x b -> ShapeExpr b y c -> ShapeExpr a (x++y) c

infixr 5 :++:
infixr 5 *:!
infixr 5 !:*

(!:*) :: DimExpr a x b -> ShapeExpr b xs c -> ShapeExpr a (x ': xs) c
x !:* xs = Single x :++: xs

(*:!) :: ShapeExpr a xs b -> DimExpr b x c -> ShapeExpr a (xs ++ '[x]) c
xs *:! x = xs :++: Single x

exprSShape :: forall a x b. ShapeExpr a x b -> SShape x
exprSShape (AShape s) = s
exprSShape (Single x) = case dimSat x of Sat -> typeSShape
exprSShape (x :++: y) = exprSShape x .+. exprSShape y

normShape :: forall ws xs ys. ShapeExpr ws xs ys -> (ws * Product xs) :~: ys
normShape (Single x) = normDim x
normShape (AShape _) = Refl
normShape (l :++: r) = case normShape l of
                         Refl ->  case normShape r of
                           Refl -> prodHomoS (exprSShape l) (exprSShape r) $
                                   prodAssocS (Proxy @ws) (productS (exprSShape l)) (productS (exprSShape r))
                                   Refl
        -- r :: normShape b y ys ----> (b * y) ~ ys   (1)
        -- l :: normShape ws x b ----> (ws * x) ~ b   (2)
        -- subst (2) in (1): ((ws * x) * y) ~ ys
        -- assoc: (ws * (x * y)) ~ ys

decideProductEq1 :: forall xs zs. ShapeExpr 1 xs zs -> Product xs :~: zs
decideProductEq1 a  = case normShape a of Refl -> Refl

type ShapeX = ShapeExpr 1

decideProductEq :: ShapeExpr 1 xs zs -> ShapeExpr 1 ys zs -> Product xs :~: Product ys
decideProductEq l r = case decideProductEq1 l of
                        Refl -> case decideProductEq1 r of
                          Refl -> Refl
