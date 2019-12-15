{-# LANGUAGE RecordWildCards #-}
module UI.Glyph
( Glyph(..)
, scaleGlyph
, Instance(..)
, instanceBounds
, combineInstances
) where

import Geometry.Rect
import Linear.Exts
import Linear.Matrix
import Linear.V2
import Linear.V3
import Linear.V4

data Glyph = Glyph
  { codePoint    :: {-# UNPACK #-} !Char
  , advanceWidth :: {-# UNPACK #-} !Float
  , geometry     :: ![V4 Float]
  , bounds       :: {-# UNPACK #-} !(Rect Float)
  }

scaleGlyph :: V2 Float -> Glyph -> Glyph
scaleGlyph (V2 sx sy) Glyph{..} = Glyph codePoint (advanceWidth * sx) ((* V4 sx sy 1 1) <$> geometry) (transformRect (scaled (V3 sx sy 1)) bounds)

data Instance = Instance
  { glyph  :: {-# UNPACK #-} !Glyph
  , offset :: {-# UNPACK #-} !(V2 Float)
  , scale  :: {-# UNPACK #-} !(V3 Float)
  }

instanceBounds :: Instance -> Rect Float
instanceBounds Instance{..} = transformRect
  (   translated offset
  !*! scaled scale)
  (bounds glyph)

combineInstances :: V2 Float -> [Glyph] -> [Instance]
combineInstances = go where
  go offset (g:gs)
    = Instance g offset 1
    : go (offset + V2 (advanceWidth g) 0) gs
  go _ [] = []
