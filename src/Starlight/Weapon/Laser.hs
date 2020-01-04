{-# LANGUAGE DisambiguateRecordFields #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}
module Starlight.Weapon.Laser
( Beam(..)
, runLaser
, drawLaser
, Drawable
) where

import           Control.Carrier.Reader
import           Control.Effect.Finally
import           Control.Effect.Lens ((?=))
import           Control.Effect.Lift
import           Control.Effect.Profile
import           Data.Coerce (coerce)
import           Data.Functor.Identity
import           Data.Functor.Interval
import           GL.Array
import           GL.Program
import           Linear.Exts
import           Starlight.View
import           Starlight.Weapon.Laser.Shader
import           UI.Colour
import qualified UI.Drawable as UI
import           Unit.Angle

data Beam = Beam
  { position :: Point V3 Float
  , angle    :: Radians Float
  , colour   :: Colour Float
  }
  deriving (Show)


runLaser
  :: ( Has Finally sig m
     , Has (Lift IO) sig m
     )
  => ReaderC Drawable m a
  -> m a
runLaser m = do
  program <- build shader
  array   <- load vertices
  runReader (Drawable UI.Drawable{ program, array }) m


drawLaser
  :: ( Has (Lift IO) sig m
     , Has Profile sig m
     , Has (Reader Drawable) sig m
     , Has (Reader View) sig m
     )
  => Beam
  -> m ()
drawLaser Beam{ colour, angle, position } = measure "laser" . UI.using getDrawable $ do
  vs@View{ focus } <- ask
  matrix_ ?=
        scaleToViewZoomed vs
    !*! translated3 (ext (negated (unP focus)) 0)
    !*! translated3 (unP position)
    !*! mkTransformation (axisAngle (unit _z) (getRadians angle)) 0
    !*! scaled (V4 1000 1000 1000 1)
  colour_ ?= colour

  drawArrays Lines range


newtype Drawable = Drawable { getDrawable :: UI.Drawable U V O }


vertices :: [V Identity]
vertices = coerce @[Float] [0, 1]

range :: Interval Identity Int
range = Interval 0 (Identity (length vertices))
