{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE TypeApplications #-}
module Starlight.Controls
( controls
, actions
, controlActions
, ControlType(..)
) where

import           Control.Applicative (liftA2)
import           Control.Effect.Lens
import           Control.Effect.Lift
import           Control.Effect.Reader
import           Control.Effect.State
import           Control.Monad (guard, when)
import           Data.Coerce (coerce)
import           Data.Functor (($>))
import           Data.Functor.Const
import           Data.Ix
import           Data.List (elemIndex)
import qualified Data.Map as Map
import qualified Data.Set as Set
import           Lens.Micro
import           Linear.Exts
import qualified SDL
import           Starlight.Action
import           Starlight.Actor
import           Starlight.Body
import           Starlight.Input
import           Starlight.Player
import           Starlight.System
import           Unit.Angle
import           Unit.Time

controls
  :: ( Has (Lift IO) sig m
     , Has (Reader (System StateVectors Float)) sig m
     , Has (State Input) sig m
     , Has (State Player) sig m
     )
  => Delta Seconds Float
  -> m ()
controls (Delta (Seconds dt)) = do
  input <- get
  when (input ^. (pressed_ SDL.KeycodePlus `or` pressed_ SDL.KeycodeEquals)) $
    throttle_ += dt * 10
  when (input ^. pressed_ SDL.KeycodeMinus) $
    throttle_ -= dt * 10

  thrust <- uses throttle_ (dt *)

  let angular = dt *^ Radians 5

  when (input ^. pressed_ SDL.KeycodeUp) $ do
    rotation <- use (actor_ . rotation_)
    actor_ . velocity_ += rotate rotation (unit _x ^* thrust) ^. _xy
  when (input ^. pressed_ SDL.KeycodeDown) $ do
    rotation <- use (actor_ . rotation_)
    velocity <- use (actor_ . velocity_)
    actor_ . rotation_ .= face angular (angleOf (negated velocity)) rotation

  when (input ^. pressed_ SDL.KeycodeLeft) $
    actor_ . rotation_ *= axisAngle (unit _z) (getRadians angular)
  when (input ^. pressed_ SDL.KeycodeRight) $
    actor_ . rotation_ *= axisAngle (unit _z) (getRadians (-angular))

  firing_ .= input ^. pressed_ SDL.KeycodeSpace

  System{ bodies } <- ask @(System StateVectors Float)
  let identifiers = Map.keys bodies
      switchTarget dir target = case target >>= (`elemIndex` identifiers) of
        Just i  -> identifiers !! i' <$ guard (inRange (0, pred (length bodies)) i') where
          i' = case dir of
            Prev -> i - 1
            Next -> i + 1
        Nothing -> Just $ case dir of { Prev -> last identifiers ; Next -> head identifiers }
  when (input ^. pressed_ SDL.KeycodeQ) $ do
    actor_ . target_ %= switchTarget Prev
    pressed_ SDL.KeycodeQ .= False
  when (input ^. pressed_ SDL.KeycodeE) $ do
    actor_ . target_ %= switchTarget Next
    pressed_ SDL.KeycodeE .= False
  where
  or = liftA2 (liftA2 (coerce (||)))

actions :: Input -> Set.Set Action
actions input = Set.fromList (concatMap (\ (kc, act) -> guard (input ^. pressed_ kc) $> act) controlActions)

-- FIXME: make this user-configurable
controlActions :: [(SDL.Keycode, Action)]
controlActions =
  [ (SDL.KeycodeUp,    Thrust)
  , (SDL.KeycodeDown,  Face Backwards)
  , (SDL.KeycodeLeft,  TurnL)
  , (SDL.KeycodeRight, TurnR)
  , (SDL.KeycodeSpace, Fire Main)
  , (SDL.KeycodeQ,     ChangeTarget (Just Prev))
  , (SDL.KeycodeE,     ChangeTarget (Just Next))
  ]

data ControlType
  = Continuous
  | Discrete
  deriving (Eq, Ord, Show)
