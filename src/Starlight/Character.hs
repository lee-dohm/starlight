{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE TypeApplications #-}
-- | Characters are player or non-player characters.
module Starlight.Character
( Character(..)
, target_
, actions_
, ship_
, HasActor(..)
, Action(..)
, Turn(..)
, Face(..)
, Change(..)
, Weapon(..)
) where

import Control.Lens (Lens')
import Data.Generics.Product.Fields
import Data.Set (Set)
import GHC.Generics (Generic)
import Starlight.Actor (Actor, HasActor(..))
import Starlight.Identifier
import Starlight.Radar
import Starlight.Ship

data Character = Character
  { actor   :: !Actor
  , target  :: !(Maybe Identifier)
  , actions :: !(Set Action)
  , ship    :: !Ship
  }
  deriving (Generic, Show)

instance HasActor Character where
  actor_ = field @"actor"

instance HasMagnitude Character where
  magnitude_ = ship_.magnitude_


target_ :: Lens' Character (Maybe Identifier)
target_ = field @"target"

actions_ :: Lens' Character (Set Action)
actions_ = field @"actions"

ship_ :: Lens' Character Ship
ship_ = field @"ship"


data Action
  = Thrust
  | Turn Turn
  | Face Face
  | Fire Weapon
  | ChangeTarget (Maybe Change)
  deriving (Eq, Ord, Show)

data Turn
  = L
  | R
  deriving (Eq, Ord, Show)

data Face
  = Backwards
  | Forwards
  | Target
  deriving (Eq, Ord, Show)

data Change
  = Prev
  | Next
  deriving (Eq, Ord, Show)

data Weapon
  = Main
  deriving (Eq, Ord, Show)
