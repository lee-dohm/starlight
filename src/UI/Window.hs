{-# LANGUAGE DeriveAnyClass #-}
module UI.Window
( withWindow
, withSDL
, withSDLWindow
, withGLContext
, Window
) where

import Control.Carrier.Lift
import qualified Control.Concurrent.Lift as CC
import qualified Control.Exception.Lift as E
import Control.Monad.IO.Class.Lift
import Data.Function (fix)
import Data.Text (Text)
import Linear.V2 as Linear
import Linear.V4 as Linear
import SDL.Event
import SDL.Init
import SDL.Video

withWindow :: (Has (Lift IO) sig m, MonadIO m) => Text -> Linear.V2 Int -> ((m a -> m a) -> m b) -> m b
withWindow name size action = withSDL $
  withSDLWindow name size $ \ window ->
    withGLContext window $ \ _ ->
      action $ \ draw -> fix $ \ loop -> do
        a <- draw
        Event _ payload <- waitEvent
        case payload of
          QuitEvent -> pure a
          _ -> glSwapWindow window *> loop

withSDL :: Has (Lift IO) sig m => m a -> m a
withSDL = CC.runInBoundThread . E.bracket_ (runLifting initializeAll) (runLifting quit)

withSDLWindow :: (Has (Lift IO) sig m, MonadIO m) => Text -> Linear.V2 Int -> (Window -> m a) -> m a
withSDLWindow name size = E.bracket
  (createWindow name windowConfig)
  destroyWindow where
  windowConfig = defaultWindow
    { windowInitialSize = fromIntegral <$> size
    , windowResizable = True
    , windowPosition = Centered
    , windowGraphicsContext = OpenGLContext glConfig
    , windowHighDPI = True
    }
  glConfig = defaultOpenGL
    { glProfile = Core Normal 4 1
    , glColorPrecision = V4 8 8 8 8
    }

withGLContext :: (Has (Lift IO) sig m, MonadIO m) => Window -> (GLContext -> m a) -> m a
withGLContext window = E.bracket (glCreateContext window) glDeleteContext
