{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE UndecidableInstances #-}
module UI.Label.Text
( shader
, U(..)
, V(..)
, O(..)
) where

import Foreign.Storable (Storable)
import GHC.Generics (Generic)
import GL.Object
import GL.Shader.DSL

shader :: Shader U V O
shader = program $ \ u
  ->  vertex (\ V{ pos} IF{ uv } -> do
    v <- let' "v" $ lerp2 (pos * 0.5 + 0.5) (rect u ^. _xy) (rect u ^. _zw)
    uv .= v - rect u ^. _xw
    gl_Position .= ext4 (ext3 (v * 2 - 1) 0) 1)

  >>> fragment (\ IF{ uv } O{ fragColour } -> do
    -- Get samples for -2/3 and -1/3
    valueL <- let' "valueL" $ texture (sampler u) (vec2 (uv ^. _x + dFdx (uv ^. _x)) (uv ^. _y)) ^. _yz * 255
    lowerL <- let' "lowerL" $ mod' valueL 16
    upperL <- let' "upperL" $ (valueL - lowerL) / 16
    alphaL <- let' "alphaL" $ min' (abs (upperL - lowerL)) 2

    -- Get samples for 0, +1/3, and +2/3
    valueR <- let' "valueR" $ texture (sampler u) uv ^. _xyz * 255
    lowerR <- let' "lowerR" $ mod' valueR 16
    upperR <- let' "upperR" $ (valueR - lowerR) / 16
    alphaR <- let' "alphaR" $ min' (abs (upperR - lowerR)) 2

    -- Average the energy over the pixels on either side
    rgba <- let' "rgba" $ vec4
      ((alphaR ^. _x + alphaR ^. _y + alphaR ^. _z) / 6)
      ((alphaL ^. _y + alphaR ^. _x + alphaR ^. _y) / 6)
      ((alphaL ^. _x + alphaL ^. _y + alphaR ^. _x) / 6)
      0

    iff (colour u ^. _x `eq` 0)
      (fragColour .= 1 - rgba)
      (fragColour .= colour u * rgba))


data U v = U
  { rect    :: v (V4 Float)
  , sampler :: v TextureUnit
  , colour  :: v (Colour Float)
  }
  deriving (Generic)

instance Vars U

newtype V v = V { pos :: v (V2 Float) }
  deriving (Generic)

instance Vars V

deriving instance Bind     (v (V2 Float)) => Bind     (V v)
deriving instance Storable (v (V2 Float)) => Storable (V v)

newtype IF v = IF { uv :: v (V2 Float) }
  deriving (Generic)

instance Vars IF

newtype O v = O { fragColour :: v (Colour Float) }
  deriving (Generic)

instance Vars O
