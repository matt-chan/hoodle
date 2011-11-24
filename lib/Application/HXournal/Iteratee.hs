{-# LANGUAGE OverloadedStrings #-}

module Application.HXournal.Iteratee where 

-- import Prelude hiding (uncurry)
import Control.Applicative hiding (empty)
import Control.Monad
import Control.Monad.State
import Control.Monad.Coroutine
import Control.Monad.Coroutine.SuspensionFunctors
import Control.Monad.IO.Class

import qualified Data.ByteString.Lazy as L
import qualified Data.ByteString.Char8 as S

import Application.HXournal.Type
import Application.HXournal.Util
import Application.HXournal.Draw
import Application.HXournal.Coroutine
import Application.HXournal.Builder

import Text.Xournal.Type 
import Text.Xournal.Predefined 

import Graphics.UI.Gtk hiding (get)

import Data.Maybe
import qualified Data.Map as M
import Data.Foldable (toList)
import Data.Sequence hiding (length,drop,take)
import Data.Strict.Tuple hiding (uncurry,fst,snd)

import Application.HXournal.Device

connPenMove :: (WidgetClass w) => w -> Iteratee MyEvent XournalStateIO (ConnectId w) 
connPenMove c = do 
  callbk <- lift $ callback <$> get 
  dev <- lift $ device <$> get 
  liftIO (c `on` motionNotifyEvent $ tryEvent $ do 
             p <- getPointer dev
             liftIO (callbk (PenMove p)))

connPenUp :: (WidgetClass w) => w -> Iteratee MyEvent XournalStateIO (ConnectId w) 
connPenUp c = do 
  callbk <- lift $ callback <$> get 
  dev <- lift $ device <$> get 
  liftIO (c `on` buttonReleaseEvent $ tryEvent $ do 
             p <- getPointer dev
             liftIO (callbk (PenMove p)))

iter :: Iteratee MyEvent XournalStateIO () 
iter = do liftIO (putStrLn "I am waiting first result") 
          initialize
          changePage (const 0)
          sequence_ (repeat eventProcess)
          return ()

initialize :: Iteratee MyEvent XournalStateIO ()
initialize = do ev <- await 
                liftIO $ putStrLn $ show ev 
                case ev of 
                  Initialized -> return () 
                  _ -> initialize

changePage :: (Int -> Int) -> Iteratee MyEvent XournalStateIO () 
changePage modifyfn = do 
  xstate <- lift get 
  let totalnumofpages = (length . xoj_pages) (xoj xstate)
      oldpage = currpage xstate
  let newpage | modifyfn oldpage >= totalnumofpages = totalnumofpages - 1
              | modifyfn oldpage < 0  = 0 
              | otherwise = modifyfn oldpage 
      
      Dim w h =  page_dim . (!! newpage) . xoj_pages . xoj $ xstate                            
      -- vm = viewMode xstate
      hadj = hscrolladj xstate  
      vadj = vscrolladj xstate
  liftIO $ do 
    adjustmentSetUpper hadj w 
    adjustmentSetUpper vadj h 
    adjustmentSetValue hadj 0
    adjustmentSetValue vadj 0
  lift (put (xstate { currpage = newpage}))
  invalidate   
  -- liftIO . putStrLn $ "changing " ++ show oldpage ++ " to " ++ show newpage

invalidate :: Iteratee MyEvent XournalStateIO () 
invalidate = do 
  xstate <- lift get  
  liftIO (updateCanvas <$> darea <*> xoj <*> currpage <*> viewMode $ xstate )

eventProcess :: Iteratee MyEvent XournalStateIO ()
eventProcess = do 
  r1 <- await 
  case r1 of 
    PenDown pcoord -> do 
      canvas <- lift ( darea <$> get )  
      win <- liftIO $ widgetGetDrawWindow canvas
      pagenum <- lift (currpage <$> get )
      page <- lift ( (!!pagenum) . xoj_pages . xoj <$> get ) 
      (x0,y0) <- lift ( vm_viewportOrigin . viewMode <$> get ) 
      geometry <- liftIO (getCanvasPageGeometry canvas page (x0,y0) )
      zmode <- lift ( vm_zmmode . viewMode <$> get )
      let (x,y) = device2pageCoord geometry zmode pcoord 
      connidup <- connPenUp canvas      
      connidmove <- connPenMove canvas
      pdraw <- penProcess geometry connidmove connidup (empty |> (x,y)) (x,y) 
      xstate <- lift get 
      let currxoj = xoj xstate
          pgnum = currpage xstate 
          pmode = penMode xstate
      let newxoj = addPDraw pmode currxoj pgnum pdraw
      lift $ put (xstate { xoj = newxoj }) 
      return ()
      -- liftIO (print pdraw) 
    _ -> defaultEventProcess r1

penProcess :: CanvasPageGeometry
           -> ConnectId DrawingArea -> ConnectId DrawingArea 
           -> Seq (Double,Double) -> (Double,Double) 
           -> Iteratee MyEvent XournalStateIO (Seq (Double,Double))
penProcess cpg connidmove connidup pdraw (x0,y0) = do 
  r <- await 
  case r of 
    PenMove pcoord -> do 
      canvas <- lift ( darea <$> get )
      zmode <- lift ( vm_zmmode . viewMode <$> get )
      pcolor <- lift ( pm_pencolor . penMode <$> get )
      pwidth <- lift ( pm_penwidth . penMode <$> get )
      let (x,y) = device2pageCoord cpg zmode pcoord 
          pcolRGBA = fromJust (M.lookup pcolor penColorRGBAmap) 
      liftIO $ drawSegment canvas cpg zmode pwidth pcolRGBA (x0,y0) (x,y)
      penProcess cpg connidmove connidup (pdraw |> (x,y)) (x,y) 
    PenUp pcoord -> do 
      canvas <- lift ( darea <$> get )
      zmode <- lift ( vm_zmmode . viewMode <$> get )      
      let (x,y) = device2pageCoord cpg zmode pcoord 
      liftIO $ signalDisconnect connidmove
      liftIO $ signalDisconnect connidup
      return (pdraw |> (x,y)) 
    other -> do
      defaultEventProcess other        
      penProcess cpg connidmove connidup pdraw (x0,y0) 

defaultEventProcess :: MyEvent -> Iteratee MyEvent XournalStateIO () 
defaultEventProcess UpdateCanvas = invalidate   
defaultEventProcess MenuPreviousPage = changePage (\x->x-1)
defaultEventProcess MenuNextPage =  changePage (+1)
defaultEventProcess MenuFirstPage = changePage (const 0)
defaultEventProcess MenuLastPage = changePage (const 10000)
defaultEventProcess MenuSave = do 
    xojcontent <- lift ( xoj <$> get )  
    liftIO $ L.writeFile "mytest.xoj" $ builder xojcontent
defaultEventProcess MenuNormalSize = do 
    liftIO $ putStrLn "NormalSize clicked"
    xstate <- lift get 
    let vm = viewMode xstate
        vm' = vm { vm_zmmode = Original }
    lift ( put xstate { viewMode = vm' } )
    invalidate       
defaultEventProcess MenuPageWidth = do 
    liftIO $ putStrLn "PageWidth clicked"
    xstate <- lift get 
    let vm = viewMode xstate
        vm' = vm { vm_zmmode = FitWidth }
    lift ( put xstate { viewMode = vm' } )
    invalidate       
defaultEventProcess (HScrollBarMoved v) = do 
    xstate <- lift get 
    let vm = viewMode xstate
        vm_orig = vm_viewportOrigin vm 
        vm' = vm { vm_viewportOrigin = (v,snd vm_orig) }
    lift ( put xstate { viewMode = vm' } )
    invalidate
defaultEventProcess (VScrollBarMoved v) = do 
    xstate <- lift get 
    let vm = viewMode xstate
        vm_orig = vm_viewportOrigin vm 
        vm' = vm { vm_viewportOrigin = (fst vm_orig,v) }
    lift ( put xstate { viewMode = vm' } )
    invalidate

defaultEventProcess _ = return ()
    -- ButtonRefresh -> invalidate 
    -- ButtonQuit -> do  
      -- liftIO . putStrLn $ "quit"
  


addPDraw :: PenMode -> Xournal -> Int -> Seq (Double,Double) -> Xournal
addPDraw pmode xoj pgnum pdraw = 
  let pcolor = pm_pencolor pmode 
      pcolname = fromJust (M.lookup pcolor penColorNameMap)
      pwidth = pm_penwidth pmode
      pagesbefore = take pgnum $ xoj_pages xoj  
      pagesafter  = drop (pgnum+1) $ xoj_pages xoj
      currpage = ((!!pgnum).xoj_pages) xoj 
      currlayer = head (page_layers currpage)
      otherlayers = tail (page_layers currpage)
      newstroke = Stroke { stroke_tool = "pen" 
                         , stroke_color = pcolname 
                         , stroke_width = pwidth
                         , stroke_data = map (uncurry (:!:)) . toList $ pdraw
                         } 
      newlayer = currlayer {layer_strokes = layer_strokes currlayer ++ [newstroke]}
      newpage = currpage {page_layers = newlayer : otherlayers }
      newxoj = xoj { xoj_pages =  pagesbefore ++ [newpage] ++ pagesafter }  
  in  newxoj










