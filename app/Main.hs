{-# LANGUAGE GADTs, FlexibleInstances, RecordWildCards, ScopedTypeVariables #-}
module Main where

import Control.Monad
import Data.Foldable
import Data.List.NonEmpty (nonEmpty)
import Data.Semigroup.Foldable
import Foreign.Ptr
import Geometry.Rect
import GHC.Stack
import GL.Array
import GL.Error
import GL.Framebuffer
import GL.Object
import GL.Program
import GL.Scalar
import GL.Shader
import GL.Texture
import GL.TextureUnit
import GL.Uniform
import Graphics.GL.Core41
import Graphics.GL.Types
import Linear.Matrix as Linear
import Linear.V2 as Linear
import Linear.V3 as Linear
import Linear.V4 as Linear
import Linear.Vector as Linear
import UI.Colour
import UI.Font as Font
import UI.Glyph
import UI.Window

-- import qualified Codec.Picture as C
-- import qualified Codec.Picture.Types as C
-- import qualified Data.ByteString.Lazy as B
-- import qualified Foreign.Marshal.Alloc as A
-- import Foreign.Storable
-- import System.CPUTime

main :: HasCallStack => IO ()
main = do
  Just tahoma <- readTypeface "/Library/Fonts/Tahoma.ttf"
  let glyphs = Font.glyphs tahoma "s"
  [textVertex, textFragment, glyphVertex, glyphFragment] <- traverse readFile ["text-vertex.glsl", "text-fragment.glsl", "glyph-vertex.glsl", "glyph-fragment.glsl"]
  withWindow (Window "Text" (fromIntegral <$> windowSize)) $ \ draw ->
    let rect    = Var "rect"    :: Var (V4 Float)
        colour  = Var "colour"  :: Var (V4 Float)
        sampler = Var "sampler" :: Var TextureUnit
        matrix3 = Var "matrix3" :: Var (M33 Float)
        instances = combineInstances (V2 288 288) (V2 0 0) glyphs
        instanceBounds' = maybe (Rect zero zero) (getUnion . foldMap1 (Union . instanceBounds)) (nonEmpty instances)
        screenQuadVertices = foldl combineGeometry (ArrayVertices [] 0 [])
          [ Geometry GL_TRIANGLE_STRIP
            [ V2 (-1) (-1)
            , V2   1  (-1)
            , V2 (-1)   1
            , V2   1    1  :: V2 Float
            ]
          ]
        geometry = Geometry GL_TRIANGLES . instanceGeometry <$> instances
        glyphVertices = foldl combineGeometry (ArrayVertices [] 0 []) geometry in
    withArray (arrayVertices screenQuadVertices) $ \ screenQuadArray ->
    withArray (arrayVertices glyphVertices) $ \ glyphArray ->
    withBuiltProgram [(Vertex, textVertex), (Fragment, textFragment)] $ \ textProgram ->
    withBuiltProgram [(Vertex, glyphVertex), (Fragment, glyphFragment)] $ \ glyphProgram ->
    with $ \ texture ->
    with $ \ framebuffer -> do
      bindTexture Texture2D (Just texture)
      setMagFilter Texture2D Nearest
      setMinFilter Texture2D Nearest
      checkingGLError $ glTexParameteri GL_TEXTURE_2D GL_TEXTURE_WRAP_S GL_CLAMP_TO_EDGE
      checkingGLError $ glTexParameteri GL_TEXTURE_2D GL_TEXTURE_WRAP_T GL_CLAMP_TO_EDGE
      checkingGLError $ glTexImage2D GL_TEXTURE_2D 0 GL_RGBA8 (2 * width) (2 * height) 0 GL_RGBA GL_UNSIGNED_INT_8_8_8_8_REV nullPtr
      bindTexture Texture2D Nothing

      bindFramebuffer (Just framebuffer)
      checkingGLError $ glFramebufferTexture2D GL_FRAMEBUFFER GL_COLOR_ATTACHMENT0 GL_TEXTURE_2D (unTexture texture) 0
      status <- glCheckFramebufferStatus GL_FRAMEBUFFER
      unless (status == GL_FRAMEBUFFER_COMPLETE) (throwGLError status)
      bindFramebuffer Nothing

      glEnable GL_BLEND

      draw $ do
        setClearColour white
        glClear GL_COLOR_BUFFER_BIT

        bindFramebuffer (Just framebuffer)
        -- bindFramebuffer Nothing

        glViewport 0 0 (2 * width) (2 * height)

        setClearColour transparent
        glClear GL_COLOR_BUFFER_BIT

        glBlendFunc GL_ONE GL_ONE -- add

        useProgram glyphProgram

        -- setUniformValue glyphProgram colour white
        -- setUniformValue glyphProgram matrix3 identity
        -- bindArray screenQuadArray
        -- traverse_ drawRange (arrayRanges screenQuadVertices)

        bindArray glyphArray

        let V2 sx sy = V2 2 (-2) / fmap fromIntegral windowSize
            scale = 1 / 2
        for_ (zip instances (arrayRanges glyphVertices)) $ \ (Instance{..}, range) ->
          for_ jitterPattern $ \ (glyphColour, V2 tx ty) -> do
            setUniformValue glyphProgram colour glyphColour
            setUniformValue glyphProgram matrix3
              $   translated (V2 (-1) 1)
              !*! scaled     (V3 sx sy 1)
              !*! translated instanceOffset
              !*! translated (V2 tx ty * scale)
              !*! scaled     instanceScale
            drawRange range

        -- let w = 2 * fromIntegral width
        --     h = 2 * fromIntegral height
        -- A.allocaBytes (4 * w * h) $ \ pixels -> do
        --   bindTexture Texture2D (Just texture)
        --   checkingGLError $ glGetTexImage GL_TEXTURE_2D 0 GL_RGBA GL_UNSIGNED_INT_8_8_8_8_REV pixels
        --   checkingGLError $ glBindFramebuffer GL_READ_FRAMEBUFFER (unFramebuffer framebuffer)
        --   checkingGLError $ glReadPixels 0 0 (2 * width) (2 * height) GL_RGBA GL_UNSIGNED_INT_8_8_8_8_REV pixels
        --   image <- C.withImage w h $ \ x y -> do
        --     let pixel = pixels `plusPtr` (w * y + x)
        --     C.unpackPixel <$> peek pixel :: IO C.PixelRGBA8
        --   time <- getCPUTime
        --   B.writeFile ("test-" ++ show time ++ ".png") (C.encodePng image)

        bindFramebuffer Nothing
        glViewport 0 0 (2 * width) (2 * height)
        glBlendFunc GL_ZERO GL_SRC_COLOR

        -- print instanceBounds'

        useProgram textProgram
        let rect' = V4
              (    fromIntegral (floor   (minX instanceBounds') :: Int) / fromIntegral width)
              (1 - fromIntegral (ceiling (maxY instanceBounds') :: Int) / fromIntegral height)
              (    fromIntegral (ceiling (maxX instanceBounds') :: Int) / fromIntegral width)
              (1 - fromIntegral (floor   (minY instanceBounds') :: Int) / fromIntegral height)

        -- print rect'

        setUniformValue textProgram rect rect'
        -- setUniformValue textProgram rect (V4 0 0 1 1)
        setUniformValue textProgram colour transparent
        -- setUniformValue textProgram colour black
        let textureUnit = TextureUnit 0
        setActiveTexture textureUnit
        bindTexture Texture2D (Just texture)
        setUniformValue textProgram sampler textureUnit

        bindArray screenQuadArray

        traverse_ drawRange (arrayRanges screenQuadVertices)
        -- traverse_ drawRange (arrayRanges glyphVertices)

        when (opaque textColour /= black) $ do
          glBlendFunc GL_ONE GL_ONE
          setUniformValue textProgram colour textColour
          traverse_ drawRange (arrayRanges screenQuadVertices)
  where drawRange :: HasCallStack => ArrayRange -> IO ()
        drawRange (ArrayRange mode from count) = checkingGLError $ glDrawArrays mode (fromIntegral from) (fromIntegral count)
        jitterPattern
          = [ (red, V2 (-1 / 12.0) (-5 / 12.0))
            , (red, V2 ( 1 / 12.0) ( 1 / 12.0))
            , (green, V2 ( 3 / 12.0) (-1 / 12.0))
            , (green, V2 ( 5 / 12.0) ( 5 / 12.0))
            , (blue, V2 ( 7 / 12.0) (-3 / 12.0))
            , (blue, V2 ( 9 / 12.0) ( 3 / 12.0))
            ]
        windowSize = V2 width height
        width  = 1024
        height = 768

        textColour = black

translated :: V2 Float -> M33 Float
translated (V2 tx ty) = V3 (V3 1 0 tx)
                           (V3 0 1 ty)
                           (V3 0 0 1)


combineInstances :: V2 Float -> V2 Float -> [Glyph] -> [Instance]
combineInstances scale@(V2 sx sy) offset (g:gs)
  = Instance g offset (V3 sx sy 1)
  : combineInstances scale (offset + V2 (glyphAdvanceWidth g) 0) gs
combineInstances _ _ [] = []

combineGeometry :: ArrayVertices (v n) -> Geometry (v n) -> ArrayVertices (v n)
combineGeometry ArrayVertices{..} (Geometry mode vertices) =
  let count = length vertices
  in ArrayVertices
    (arrayVertices <> vertices)
    (prevIndex + count)
    (arrayRanges <> [ ArrayRange mode prevIndex count ])

data ArrayRange = ArrayRange
  { mode             :: {-# UNPACK #-} !GLuint
  , firstVertexIndex :: {-# UNPACK #-} !Int
  , vertexCount      :: {-# UNPACK #-} !Int
  }

data GeometryArray n = GeometryArray
  { geometryRanges :: [ArrayRange]
  , geometryArray  :: Array n
  }

data ArrayVertices a = ArrayVertices
  { arrayVertices :: [a]
  , prevIndex     :: Int
  , arrayRanges   :: [ArrayRange]
  }

data Geometry a where
  Geometry :: (Foldable v, Scalar n) => GLuint -> [v n] -> Geometry (v n)
