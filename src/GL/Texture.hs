{-# LANGUAGE DataKinds, GeneralizedNewtypeDeriving, KindSignatures, LambdaCase, ScopedTypeVariables #-}
module GL.Texture
( Texture(..)
, Type(..)
, KnownType(..)
, Filter(..)
, setMagFilter
, setMinFilter
) where

import Control.Monad.IO.Class.Lift
import Data.Coerce
import Data.Proxy
import Foreign.Storable
import GL.Enum as GL
import GL.Error
import GL.Object
import Graphics.GL.Core41
import Graphics.GL.Types

newtype Texture (ty :: Type) = Texture { unTexture :: GLuint }
  deriving (Storable)

instance Object (Texture ty) where
  gen n = runLiftIO . glGenTextures n . coerce
  delete n = runLiftIO . glDeleteTextures n . coerce

instance KnownType ty => Bind (Texture ty) where
  bind = checkingGLError . runLiftIO . glBindTexture (glEnum (typeVal (Proxy :: Proxy ty))) . maybe 0 unTexture


data Type
  = Texture2D
  deriving (Eq, Ord, Show)

class KnownType (ty :: Type) where
  typeVal :: proxy ty -> Type

instance KnownType 'Texture2D where
  typeVal _ = Texture2D

instance GL.Enum Type where
  glEnum = \case
    Texture2D -> GL_TEXTURE_2D


data Filter = Nearest | Linear

instance GL.Enum Filter where
  glEnum = \case
    Nearest -> GL_NEAREST
    Linear  -> GL_LINEAR

setMagFilter :: Has (Lift IO) sig m => Type -> Filter -> m ()
setMagFilter target = checkingGLError . runLiftIO . glTexParameteri (glEnum target) GL_TEXTURE_MAG_FILTER . fromIntegral . glEnum

setMinFilter :: Has (Lift IO) sig m => Type -> Filter -> m ()
setMinFilter target = checkingGLError . runLiftIO . glTexParameteri (glEnum target) GL_TEXTURE_MIN_FILTER . fromIntegral . glEnum
