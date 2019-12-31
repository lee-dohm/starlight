{-# LANGUAGE LambdaCase #-}
module Starlight.Identifier
( Code
, Name
, Identifier(..)
, parentIdentifier
, describeIdentifier
, toList
) where

import Data.Function (on)
import Data.List.NonEmpty (NonEmpty(..))
import Data.Text

type Code = Int

type Name = Text

data Identifier
  = Star (Code, Name)
  | Identifier :/ (Code, Name)
  deriving (Eq, Read, Show)

infixl 5 :/

instance Ord Identifier where compare = compare `on` toList

parentIdentifier :: Identifier -> Maybe Identifier
parentIdentifier = \case
  parent :/ _ -> Just parent
  _           -> Nothing

describeIdentifier :: Identifier -> String
describeIdentifier = \case
  Star (code, name) -> show code <> " " <> unpack name
  _ :/ (code, name) -> show code <> " " <> unpack name

toList :: Identifier -> NonEmpty (Code, Name)
toList i = go i [] where
  go = \case
    Star leaf -> (leaf:|)
    i :/ leaf -> go i . (leaf:)
