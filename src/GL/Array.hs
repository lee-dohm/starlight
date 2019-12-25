{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE UndecidableInstances #-}
module GL.Array
( Array(..)
, configureArray
, Mode(..)
, drawArrays
, load
, loadInterleaved
, bindArray
, ArrayT(..)
, HasArray(..)
) where

import           Control.Algebra
import           Control.Carrier.Reader
import           Control.Effect.Finally
import           Control.Monad.IO.Class.Lift
import           Control.Monad.Trans.Class
import           Data.Coerce
import           Data.Functor.Identity
import           Data.Interval
import           Foreign.Ptr
import qualified Foreign.Storable as S
import           GHC.Stack
import qualified GL.Buffer as B
import           GL.Enum as GL
import           GL.Error
import           GL.Object
import           GL.Program (HasProgram(..), ProgramT(..))
import qualified GL.Shader.DSL as DSL
import qualified GL.Type as GL
import           Graphics.GL.Core41
import           Graphics.GL.Types

newtype Array n = Array { unArray :: GLuint }
  deriving (S.Storable)

instance Object (Array n) where
  gen n = runLiftIO . glGenVertexArrays n . coerce
  delete n = runLiftIO . glDeleteVertexArrays n . coerce

instance Bind (Array n) where
  bind = checkingGLError . runLiftIO . glBindVertexArray . maybe 0 unArray


configureArray :: forall i m sig . (DSL.Vars i, S.Storable (i Identity), Has (Lift IO) sig m) => B.Buffer 'B.Array (i Identity) -> Array (i Identity) -> m ()
configureArray _ _ = DSL.foldVarsM (\ f@DSL.Field { DSL.location, DSL.offset } _ -> runLiftIO $ do
  checkingGLError $ glEnableVertexAttribArray (fromIntegral location)
  checkingGLError $ glVertexAttribPointer     (fromIntegral location) (GL.glDims f) (GL.glType f) GL_FALSE (fromIntegral (S.sizeOf @(i Identity) undefined)) (nullPtr `plusPtr` DSL.getOffset offset)) (DSL.makeVars @i id)


data Mode
  = Points
  | Lines
  | LineStrip
  | LineLoop
  | TriangleStrip
  | Triangles
  deriving (Eq, Show)

instance GL.Enum Mode where
  glEnum = \case
    Points        -> GL_POINTS
    Lines         -> GL_LINES
    LineStrip     -> GL_LINE_STRIP
    LineLoop      -> GL_LINE_LOOP
    TriangleStrip -> GL_TRIANGLE_STRIP
    Triangles     -> GL_TRIANGLES


drawArrays
  :: ( Has (Lift IO) sig m
     , HasCallStack
     , HasArray i m
     , HasProgram u i o m
     )
  => Mode
  -> Interval Int
  -> m ()
drawArrays mode i = askProgram >> askArray >> checkingGLError (runLiftIO (glDrawArrays (glEnum mode) (fromIntegral (min_ i)) (fromIntegral (size i))))


load :: (DSL.Vars i, Has Finally sig m, Has (Lift IO) sig m) => [i Identity] -> m (i Array)
load is = do
  let is' = DSL.getApVars (traverse (DSL.ApVars . DSL.mapVars (const ((:[]) . runIdentity))) is)
  DSL.forVars is' (\ DSL.Field { DSL.location } vs -> runLiftIO $ do
    b <- gen1 @(B.Buffer 'B.Array _)
    a <- gen1
    bind (Just b)
    B.realloc b (length vs) B.Static B.Draw
    B.copy b 0 vs

    bind (Just a)
    checkingGLError $ glEnableVertexAttribArray (fromIntegral location)
    checkingGLError $ glVertexAttribPointer     (fromIntegral location) (GL.glDims a) (GL.glType a) GL_FALSE 0 nullPtr

    pure a)

loadInterleaved :: (DSL.Vars i, S.Storable (i Identity), Has Finally sig m, Has (Lift IO) sig m) => [i Identity] -> m (Array (i Identity))
loadInterleaved is = do
  b <- gen1 @(B.Buffer 'B.Array _)
  a <- gen1
  bind (Just b)
  bind (Just a)
  B.realloc b (length is) B.Static B.Draw
  B.copy b 0 is

  a <$ configureArray b a


bindArray :: Has (Lift IO) sig m => Array (i Identity) -> ArrayT i m a -> m a
bindArray array (ArrayT m) = do
  bind (Just array)
  a <- runReader array m
  a <$ bind @(Array _) Nothing

class Monad m => HasArray i m | m -> i where
  askArray :: m (Array (i Identity))


newtype ArrayT i m a = ArrayT { runArrayT :: ReaderC (Array (i Identity)) m a }
  deriving (Applicative, Functor, Monad, MonadIO, MonadTrans)

deriving instance HasArray     i   m => HasArray     i   (ProgramT u i o m)
deriving instance HasProgram u i o m => HasProgram u i o (ArrayT     i   m)

instance HasArray i m => HasArray i (ReaderC r m) where
  askArray = lift askArray

instance Algebra sig m => Algebra sig (ArrayT i m) where
  alg = ArrayT . send . handleCoercible

instance Algebra sig m => HasArray i (ArrayT i m) where
  askArray = ArrayT ask
