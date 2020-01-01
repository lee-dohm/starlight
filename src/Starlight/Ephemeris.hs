{-# LANGUAGE DisambiguateRecordFields #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE TypeOperators #-}
module Starlight.Ephemeris
( Ephemeris(..)
, fromEphemeris
, fromCSV
, fromFile
, fromDirectory
, Per(..)
) where

import Control.Effect.Lift
import Data.Char (isSpace, toUpper)
import Data.List (elemIndex)
import Data.Text (pack)
import Linear.Epsilon
import Linear.Exts
import Numeric (readDec)
import Starlight.Body
import Starlight.Identifier
import System.Directory
import System.FilePath
import Text.Read
import Unit.Angle
import Unit.Length
import Unit.Time

data Ephemeris = Ephemeris
  { julianDayNumberBarycentricDynamicalTime :: Double
  , calendarDate                            :: String
  , eccentricity                            :: Double
  , periapsisDistance                       :: Kilo Metres Double
  , inclination                             :: Degrees Double
  , longitudeOfAscendingNode                :: Degrees Double
  , argumentOfPerifocus                     :: Degrees Double
  , timeOfPeriapsisRelativeToEpoch          :: Seconds Double
  , meanMotion                              :: (Degrees `Per` Seconds) Double
  , meanAnomaly                             :: Degrees Double
  , trueAnomaly                             :: Degrees Double
  , semimajor                               :: Kilo Metres Double
  , apoapsisDistance                        :: Kilo Metres Double
  , siderealOrbitPeriod                     :: Seconds Double
  }
  deriving (Eq, Ord, Show)

fromEphemeris :: (Epsilon a, RealFloat a) => Ephemeris -> Orbit a
fromEphemeris Ephemeris{ eccentricity, semimajor, longitudeOfAscendingNode, inclination, argumentOfPerifocus, siderealOrbitPeriod, timeOfPeriapsisRelativeToEpoch }
  = Orbit
    { eccentricity    = realToFrac eccentricity
    , semimajor       = realToFrac <$> unKilo semimajor
    , orientation     = orient
      (realToFrac <$> fromDegrees longitudeOfAscendingNode)
      (realToFrac <$> fromDegrees inclination)
      (realToFrac <$> fromDegrees argumentOfPerifocus)
    , period          = realToFrac <$> siderealOrbitPeriod
    , timeOfPeriapsis = realToFrac <$> timeOfPeriapsisRelativeToEpoch
    }

fromCSV :: String -> Either String Ephemeris
fromCSV = toBody . splitOnCommas where
  splitOnCommas s = case break (== ',') s of
    ("", _) -> []
    (s, ss) -> s : splitOnCommas (drop 2 ss)
  toBody (julianDayNumberBarycentricDynamicalTime : calendarDate : eccentricity : periapsisDistance : inclination : longitudeOfAscendingNode : argumentOfPerifocus : timeOfPeriapsisRelativeToEpoch : meanMotion : meanAnomaly : trueAnomaly : semimajor : apoapsisDistance : siderealOrbitPeriod : _) = Ephemeris
    <$> readEither' "julianDayNumberBarycentricDynamicalTime" id         julianDayNumberBarycentricDynamicalTime
    <*> pure                                                                  calendarDate
    <*> readEither' "eccentricity"                            id              eccentricity
    <*> readEither' "periapsisDistance"                       (Kilo . Metres) periapsisDistance
    <*> readEither' "inclination"                             Degrees         inclination
    <*> readEither' "longitudeOfAscendingNode"                Degrees         longitudeOfAscendingNode
    <*> readEither' "argumentOfPerifocus"                     Degrees         argumentOfPerifocus
    <*> readEither' "timeOfPeriapsisRelativeToEpoch"          Seconds         timeOfPeriapsisRelativeToEpoch
    <*> readEither' "meanMotion"                              Per             meanMotion
    <*> readEither' "meanAnomaly"                             Degrees         meanAnomaly
    <*> readEither' "trueAnomaly"                             Degrees         trueAnomaly
    <*> readEither' "semimajor"                               (Kilo . Metres) semimajor
    <*> readEither' "apoapsisDistance"                        (Kilo . Metres) apoapsisDistance
    <*> readEither' "siderealOrbitPeriod"                     Seconds         siderealOrbitPeriod
  toBody vs = Left $ "lol no: " <> show vs
  readEither' :: Read a => String -> (a -> b) -> String -> Either String b
  readEither' err f = either (Left . ((err <> ": ") <>)) (Right . f) . readEither

fromFile :: (Epsilon a, RealFloat a, Has (Lift IO) sig m, MonadFail m) => FilePath -> m (Orbit a)
fromFile path = do
  lines <- lines <$> sendM (readFile path)
  last <- maybe (fail ("no ephemerides found in file: " <> path)) (pure . pred) (elemIndex "$$EOE" lines)
  either fail (pure . fromEphemeris) (fromCSV (lines !! last))

fromDirectory :: (Epsilon a, RealFloat a, Has (Lift IO) sig m, MonadFail m) => FilePath -> m [(Identifier, Orbit a)]
fromDirectory = go Nothing
  where
  go :: (Epsilon a, RealFloat a, Has (Lift IO) sig m, MonadFail m) => Maybe Identifier -> FilePath -> m [(Identifier, Orbit a)]
  go root dir
    =   sendM (listDirectory dir)
    >>= traverse (\ path -> do
      isDir <- sendM (doesDirectoryExist (dir </> path))
      case parseIdentifier root path of
        [identifier] -> if isDir then
          go (Just identifier) (dir </> path)
        else
          pure . (,) identifier <$> fromFile (dir </> path)
        _ -> pure [])
    >>= pure . concat
  parseIdentifier root path = do
    (code, rest) <- readDec path
    let name = pack (initCap (dropWhile isSpace (dropExtension rest)))
        leaf = (code, name)
    pure (maybe (Star leaf) (:/ leaf) root)
  initCap = \case
    ""   -> ""
    c:cs -> toUpper c : cs


newtype Per (f :: * -> *) (g :: * -> *) a = Per { getPer :: a }
  deriving (Eq, Ord, Show)