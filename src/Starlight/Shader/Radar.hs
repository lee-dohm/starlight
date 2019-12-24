{-# LANGUAGE DataKinds, TypeOperators #-}
module Starlight.Shader.Radar
( vertex
) where

import GL.Shader.DSL
import Unit.Angle (Radians(..))

vertex
  :: Shader
    'Vertex
    '[ "matrix" '::: M33 Float
     , "angle"  '::: Radians Float
     , "sweep"  '::: Radians Float ]
    '[ "n" '::: Float ]
    '[]
vertex = uniforms $ \ matrix angle sweep -> inputs $ \ n -> main $ do
  angle <- let' "angle" (coerce angle + n * coerce sweep)
  pos   <- let' "pos"   (vec2 (cos angle) (sin angle) ^* 150)
  gl_Position .= vec4 (vec3 ((matrix !* vec3 pos 1) ^. _xy) 0) 1