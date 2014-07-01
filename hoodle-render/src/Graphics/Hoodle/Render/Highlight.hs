{-# LANGUAGE OverloadedStrings #-}

-----------------------------------------------------------------------------
-- |
-- Module      : Graphics.Hoodle.Render.Highlight
-- Copyright   : (c) 2011-2014 Ian-Woo Kim
--
-- License     : BSD3
-- Maintainer  : Ian-Woo Kim <ianwookim@gmail.com>
-- Stability   : experimental
-- Portability : GHC
--
-- collection of rendering routine that draws bounding box only
--
-----------------------------------------------------------------------------

module Graphics.Hoodle.Render.Highlight where

-- from others
import qualified Data.Map as M
import qualified Graphics.Rendering.Cairo as Cairo
-- from hoodle-platform 
import           Data.Hoodle.Simple
import           Data.Hoodle.BBox
import           Data.Hoodle.Predefined 
-- from this package
import           Graphics.Hoodle.Render.Primitive 
import           Graphics.Hoodle.Render.Type.Item 
-- 
import Prelude hiding (fst,snd,curry,uncurry,mapM_,concatMap)

-- | 
renderStrkHltd :: BBoxed Stroke -> Cairo.Render ()
renderStrkHltd sbbox = do 
    let s = bbxed_content sbbox 
    case M.lookup (stroke_color s) predefined_pencolor of 
      Just (r,g,b,a) -> Cairo.setSourceRGBA r g b a
      Nothing -> Cairo.setSourceRGBA 0 0 0 1 
    case s of
      Stroke _ _ w d -> do  
        Cairo.setLineWidth (w * 4.0) 
        Cairo.setLineCap Cairo.LineCapRound
        Cairo.setLineJoin Cairo.LineJoinRound
        drawStrokeCurve d
        Cairo.stroke
        Cairo.setSourceRGBA 1 1 1 1
        Cairo.setLineWidth w
        drawStrokeCurve . stroke_data $ s 
        Cairo.stroke
      VWStroke _ _ d -> do  
        Cairo.setFillRule Cairo.FillRuleWinding
        drawVWStrokeCurve $ map (\(x,y,z)->(x,y,4*z)) d
        Cairo.fill 
        Cairo.setSourceRGBA 1 1 1 1
        drawVWStrokeCurve d     
        Cairo.fill
    

-- | render items highlighted 
renderRItemHltd :: RItem -> Cairo.Render ()
renderRItemHltd (RItemStroke strk) = renderStrkHltd strk
renderRItemHltd (RItemImage img _) = (renderHltBBox . getBBox) img
renderRItemHltd (RItemSVG svg _) = (renderHltBBox . getBBox) svg 
renderRItemHltd (RItemLink lnk _) = (renderHltBBox . getBBox) lnk
renderRItemHltd (RItemAnchor anc _) = (renderHltBBox . getBBox) anc

-- |
renderHltBBox :: BBox -> Cairo.Render ()
renderHltBBox (BBox (x1,y1) (x2,y2)) = do 
    Cairo.setSourceRGBA 0 0 0 1
    Cairo.setLineWidth 10 
    Cairo.rectangle x1 y1 (x2-x1) (y2-y1)
    Cairo.stroke

{-
-- |
renderHighlightedBBoxedItem :: (GetBBoxable a) => a -> Cairo.Render () 
renderHighlinetedBBoxedItem x = renderHltBBox . getBBox 
  Cairo.setSourceRGBA 0 0 0 1
  Cairo.setLineWidth 10 
  let BBox (x1,y1) (x2,y2) = getBBox x
  Cairo.rectangle x1 y1 (x2-x1) (y2-y1)
  Cairo.stroke
-}
