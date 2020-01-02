{-# LANGUAGE NamedFieldPuns #-}
module Starlight.System
( System(..)
, systemTrans
, _scale
, lookup
) where

import qualified Data.Map as Map
import           Lens.Micro (Lens', lens)
import           Linear.Matrix
import           Linear.V4
import           Linear.Vector
import           Prelude hiding (lookup)
import           Starlight.Identifier

data System f a = System
  { scale  :: !a
  , bodies :: !(Map.Map Identifier (f a))
  }
  deriving (Read, Show)

systemTrans :: Num a => System f a -> M44 a
systemTrans System{ scale } = scaled (V4 scale scale scale 1)

_scale :: Lens' (System f a) a
_scale = lens scale (\ s scale -> s { scale })

lookup :: Identifier -> System f a -> Maybe (f a)
lookup i = Map.lookup i . bodies
