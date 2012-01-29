-----------------------------------------------------------------------------
-- |
-- Module      : Application.HXournal.Coroutine.Scroll 
-- Copyright   : (c) 2011, 2012 Ian-Woo Kim
--
-- License     : BSD3
-- Maintainer  : Ian-Woo Kim <ianwookim@gmail.com>
-- Stability   : experimental
-- Portability : GHC
--
-----------------------------------------------------------------------------

module Application.HXournal.Coroutine.Scroll where

import Application.HXournal.Type.Event 
import Application.HXournal.Type.Coroutine
import Application.HXournal.Type.Canvas
import Application.HXournal.Type.XournalState
import Application.HXournal.Type.PageArrangement
import Application.HXournal.Coroutine.Draw
import Application.HXournal.Accessor
import Control.Monad
import Control.Monad.Coroutine.SuspensionFunctors
import Control.Category
import Data.Xournal.BBox
import Data.Label
import Prelude hiding ((.), id)

vscrollStart :: CanvasId -> MainCoroutine () 
vscrollStart cid = vscrollMove cid 
        
vscrollMove :: CanvasId -> MainCoroutine () 
vscrollMove cid = do    
    ev <- await 
    case ev of
      VScrollBarMoved _cid' v -> do 
        putSt . modifyCurrentCanvasInfo (selectBox (scrollmovecanvas v) (error "vscrollMove")) =<< getSt 
        invalidateWithBuf cid 
        vscrollMove cid 
      VScrollBarEnd cid' _v -> do 
        invalidate cid' 
        return ()
      _ -> return ()       
  where scrollmovecanvas v cvsInfo = 
          let BBox vm_orig _ = unViewPortBBox $ get (viewPortBBox.pageArrangement.viewInfo) cvsInfo
          in modify (viewPortBBox.pageArrangement.viewInfo) 
                    (apply (moveBBoxULCornerTo (fst vm_orig,v))) cvsInfo 


