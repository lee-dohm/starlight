{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}
module Starlight.Body
( StateVectors(..)
, Body(..)
, Orbit(..)
, rotationTimeScale
, transformAt
, orientationAt
, positionAt
, velocityAt
, systemAt
  -- * Drawing
, runBody
, Drawable
, drawBody
) where

import           Control.Carrier.Reader
import           Control.Effect.Finally
import           Control.Effect.Lens ((.=))
import           Control.Effect.Lift
import           Control.Effect.Profile
import           Data.Coerce (coerce)
import           Data.Foldable (find)
import           Data.Functor.Identity
import           Data.Functor.Interval
import           Geometry.Circle
import           GL.Array
import           GL.Program
import           Lens.Micro (lens, (^.))
import           Linear.Exts
import           Starlight.Actor (HasPosition(..))
import           Starlight.Body.Shader as Shader
import           Starlight.Identifier
import           Starlight.System
import           Starlight.View
import           UI.Colour
import qualified UI.Drawable as UI
import           Unit.Angle
import           Unit.Length
import           Unit.Mass
import           Unit.Time

data StateVectors a = StateVectors
  { body      :: Body a
  , transform :: M44 a
  , rotation  :: Quaternion a
  , position  :: Point V2 a
  }
  deriving (Show)

instance HasPosition (StateVectors a) a where
  position_ = lens position (\ s position -> s { position })

data Body a = Body
  { identifier  :: Identifier
  , radius      :: Metres a
  , mass        :: Kilo Grams a
  , orientation :: Quaternion a -- relative to orbit
  , period      :: Seconds a    -- sidereal rotation period
  , colour      :: Colour a
  , orbit       :: Orbit a
  }
  deriving (Read, Show)

data Orbit a = Orbit
  { eccentricity    :: a
  , semimajor       :: Metres a
  , orientation     :: Quaternion a -- relative to ecliptic
  , period          :: Seconds a
  , timeOfPeriapsis :: Seconds a    -- relative to epoch
  }
  deriving (Read, Show)


rotationTimeScale :: Num a => Seconds a
rotationTimeScale = 1

orbitTimeScale :: Num a => Seconds a
orbitTimeScale = 1

transformAt :: RealFloat a => Orbit a -> Seconds a -> M44 a
transformAt orbit@Orbit{ orientation } t = mkTransformation
  orientation
  (unP (positionAt orbit t))

orientationAt :: (Epsilon a, RealFloat a) => Body a -> Seconds a -> Quaternion a
orientationAt Body { orientation, period, orbit = Orbit { orientation = orbit } } t
  = orbit
  * orientation
  * axisAngle (unit _z) (getSeconds (t * rotationTimeScale / period))


positionAt :: RealFloat a => Orbit a -> Seconds a -> Point V3 a
positionAt Orbit { eccentricity, semimajor, period, timeOfPeriapsis } t = P (ext (cartesian2 (Radians trueAnomaly) r) 0) where
  t' = timeOfPeriapsis + t * orbitTimeScale
  meanAnomaly = getSeconds (meanMotion * t')
  meanMotion = (2 * pi) / period
  eccentricAnomaly = iter 10 (\ ea -> meanAnomaly + eccentricity * sin ea) meanAnomaly where
    iter n f = go n where
      go n a
        | n <= 0    = a
        | otherwise = go (n - 1 :: Int) (f a)
  trueAnomaly = atan2 (sqrt (1 - eccentricity * eccentricity) * sin eccentricAnomaly) (cos eccentricAnomaly - eccentricity)
  r = getMetres semimajor * (1 - eccentricity * cos eccentricAnomaly)

velocityAt :: RealFloat a => Orbit a -> Seconds a -> V3 a
velocityAt orbit t = positionAt orbit (t + 1) .-. positionAt orbit t


systemAt :: (Epsilon a, RealFloat a) => System Body a -> Seconds a -> System StateVectors a
systemAt sys@System{ bodies } t = sys { bodies = bodies' } where
  bodies' = fmap go bodies
  go b = StateVectors
    { body = b
    , transform = transform'
    , rotation = orientationAt b t
    , position = P ((transform' !* V4 0 0 0 1) ^. _xy)
    } where
    rel = maybe (systemTrans sys) transform $ do
      p <- parent (identifier b)
      find ((== p) . identifier . body) bodies'
    transform' = rel !*! transformAt (orbit b) t


runBody
  :: ( Has Finally sig m
     , Has (Lift IO) sig m
     )
  => ReaderC Drawable m a
  -> m a
runBody m = do
  program <- build Shader.shader
  array   <- load vertices
  runReader (Drawable UI.Drawable{ program, array }) m

drawBody
  :: ( Has (Lift IO) sig m
     , Has Profile sig m
     , Has (Reader Drawable) sig m
     , Has (Reader View) sig m
     )
  => StateVectors Float
  -> m ()
drawBody StateVectors{ body = Body{ radius = Metres r, colour }, transform, rotation } = measure "bodies" . UI.using getDrawable $ do
  vs@View{ focus } <- ask
  matrix_ .= Just
    (   scaleToViewZoomed vs
    !*! translated3 (ext (negated (unP focus)) 0) -- transform to the origin
    !*! transform
    !*! scaled (V4 r r r 1)
    !*! mkTransformation rotation 0)
  colour_ .= Just colour

  drawArraysInstanced LineLoop range 3


newtype Drawable = Drawable { getDrawable :: UI.Drawable Shader.U Shader.V Shader.O }


vertices :: [Shader.V Identity]
vertices = coerce @[V4 Float] . map (`ext` V2 0 1) $ circle 1 128

range :: Interval Identity Int
range = Interval 0 (Identity (length vertices))
