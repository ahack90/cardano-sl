{-# LANGUAGE TypeFamilies         #-}

module Pos.Shutdown.Class
       ( MonadShutdownMem
       , askShutdownMem
       ) where

import qualified Control.Monad.Ether.Implicit as Ether
import           Pos.Shutdown.Types           (ShutdownContext)

type MonadShutdownMem = Ether.MonadReader ShutdownContext

askShutdownMem :: MonadShutdownMem m => m ShutdownContext
askShutdownMem = Ether.ask
