{-# LANGUAGE GADTs, NoMonomorphismRestriction, ScopedTypeVariables, KindSignatures #-}

----------------------------
-- | describe world object
----------------------------

module Control.Monad.Coroutine.World.Sample where 

import Control.Applicative
import Control.Category
import Control.Monad.Error 
import Control.Monad.Reader
import Control.Monad.State
import Data.Lens.Common 
-- 
import Control.Monad.Coroutine
import Control.Monad.Coroutine.Event 
import Control.Monad.Coroutine.Logger 
import Control.Monad.Coroutine.Object
import Control.Monad.Coroutine.Queue
import Control.Monad.Coroutine.World
import Control.Monad.Coroutine.World.SampleActor

-- 
import Prelude hiding ((.),id)


-- | 
world :: forall m. (MonadIO m) => ServerObj (WorldOp m) m () 
world = ReaderT staction 
  where 
    staction req = do runStateT (go req) initWorld
                      return ()
    go :: (MonadIO m) => MethodInput (WorldOp m) -> StateT (WorldAttrib (ServerT (WorldOp m) m)) (ServerT (WorldOp m) m) () 
    go (Input GiveEvent ev) = do
      dobj <- getL (objDoor.worldActor) <$> get  
      mobj <- getL (objMessageBoard.worldActor) <$> get 
      aobj <- getL (objAir.worldActor) <$> get 
      Right (dobj',mobj',aobj') <- 
        runErrorT $ (,,) <$> liftM fst (dobj <==> giveEventSub ev) 
                         <*> liftM fst (mobj <==> giveEventSub ev) 
                         <*> liftM fst (aobj <==> giveEventSub ev)
      put . setL (objDoor.worldActor) dobj' 
          . setL (objMessageBoard.worldActor) mobj' 
          . setL (objAir.worldActor) aobj' =<< get  
      req <- lift (request (Output GiveEvent ()))
      go req   
    go (Input FlushLog (logobj :: LogServer m ())) = do
      logf <- getL (tempLog.worldState) <$> get 
      let msg = logf "" 
      if ((not . null) msg) 
        then do 
          let l1 = runErrorT (logobj <==> writeLog ("[World] " ++ (logf ""))) 
          Right (logobj',_) <- lift . lift $ l1
          put . setL (tempLog.worldState) id =<< get
          req <- lift (request (Output FlushLog logobj'))
          go req  
        else do 
          req <- lift (request Ignore) 
          go req 
    go (Input FlushQueue ()) = do
      q <- getL (tempQueue.worldState) <$> get 
      let lst = fqueue q ++ reverse (bqueue q)
      put . setL (tempQueue.worldState) emptyQueue =<< get 
      req <- lift (request (Output FlushQueue lst))
      go req 