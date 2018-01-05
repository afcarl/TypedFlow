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
{-|
Module      : TypedFlow.Models.Topic
Description : Topic models
Copyright   : (c) Jean-Philippe Bernardy, 2017
License     : LGPL-3
Maintainer  : jean-philippe.bernardy@gu.se
Stability   : experimental
-}


module TypedFlow.Models.Topic where
import Prelude hiding ((/), sqrt)
import TypedFlow.TF
import TypedFlow.Layers
import TypedFlow.Types
import GHC.TypeLits

-- -- | create a document summarization function with appropriate parameters.
-- mkDocumentSummary
--   :: String -> -- ^ prefix for parameter names
--      Gen (T '[n,e] (Flt t) -> T '[a] (Flt t)) -- ^ document vector (summary)
-- mkDocumentSummary prefix = do
--   filter <- parameter (prefix ++ "_filter") (truncatedNormal 0.1 )
--   return $ (relu . conv filter)



-- p = softmax (A d)
-- s = B p

-- | A convolutional document summary function. Described in
-- 'Topically Driven Neural Language Model' by Lau, Baldwin and Cohn.
tldmDocsummary :: forall
  (vocSize :: Nat) -- number of words
  (e :: Nat) -- size of the embedding
  (a :: Nat) -- document vector summary size
  (n :: Nat) -- length of the document
  (batchSize :: Nat)
  (filterSize :: Nat) -- size of the convolution filter.
   (t :: NBits) -- size of floats
  .  KnownNat e => KnownNat a => KnownNat n => KnownNat batchSize => KnownBits t
  =>  (EmbeddingP vocSize e t) -> (ConvP t a e '[filterSize]) -> DropProb -> T '[n,batchSize] Int32 -> Gen (T '[a,batchSize] (Flt t))
tldmDocsummary embs filters dropProb document = do
  drpEmb <- mkDropout dropProb
  return (reduceMax @Dim1 (conv filters (drpEmb (embedding @e @vocSize embs document))))

-- | A topic modeler. Described 'Topically Driven Neural Language
-- Model' by Lau, Baldwin and Cohn.
tdlmTopic :: forall
  (kk :: Nat) -- number of topics
  (a :: Nat) -- document vector summary size
  (b :: Nat) -- topic representation size
  (t :: NBits) -- size of floats
  (batchSize :: Nat)
  . KnownNat kk => KnownNat a => KnownNat b => KnownBits t => KnownNat batchSize
  => T '[a,batchSize] (Flt t) -- ^ document summary
  -> Gen (Tensor '[b, batchSize] (Flt t), Scalar (Flt t))
tdlmTopic d = do
  drpS   <- mkDropout (DropProb 0.1)
  topicInput :: T '[a,kk] (Flt t) <- parameter "A" glorotUniform -- mapping from document representations to topics
  topicOutput :: T '[kk,b] (Flt t) <- parameter "B" glorotUniform  -- all possible topics
  let p :: T '[kk,batchSize] (Flt t)
      p = softmax0 (topicInput ∙ d) -- attention distribution (among the topics)
      s :: T '[b,batchSize] (Flt t)
      s = drpS (topicOutput ∙ p)  -- document topic representation
      topicNormalized :: T '[b,kk] (Flt t)
      topicNormalized = transpose01 topicOutput / (sqrt (reduceSum @Dim0 (topicOutput ⊙ topicOutput)) :: T '[b] (Flt t))
      topicCorrelation :: T '[b,b] (Flt t)
      topicCorrelation = matmul (transpose01 topicNormalized) topicNormalized
      topicUniqueness = reduceMaxAll (topicCorrelation ⊝ eye)
  return (s,topicUniqueness)
