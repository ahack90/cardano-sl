{-# LANGUAGE AllowAmbiguousTypes #-}

-- | Utilities for block logic testing.

module Test.Pos.Block.Logic.Util
       ( EnableTxPayload (..)
       , InplaceDB (..)
       , bpGenBlocks
       , bpGenBlock
       , genBlockGenParams
       , bpGoToArbitraryState
       , withCurrentSlot
       , satisfySlotCheck
       , getAllSecrets
       ) where

import           Universum

import           Control.Monad.Random.Strict (evalRandT)
import           Data.Default (Default (def))
import qualified Data.List as List (head)
import qualified Data.Set as Set
import           Test.QuickCheck.Gen (Gen (MkGen), sized)
import           Test.QuickCheck.Monadic (PropertyM, pick)

import           Pos.AllSecrets (AllSecrets, HasAllSecrets (..), allSecrets)
import           Pos.Chain.Block (Blund)
import           Pos.Chain.Block (Block)
import           Pos.Chain.Txp (TxpConfiguration (..))
import           Pos.Core (BlockCount, HasGenesisData, HasProtocolConstants,
                     SlotId (..), epochIndexL, genesisData)
import           Pos.Core.Chrono (NE, OldestFirst (..))
import           Pos.Core.Genesis (GenesisData (..))
import           Pos.Crypto (ProtocolMagic)
import           Pos.DB.Txp (MempoolExt, MonadTxpLocal, TxpGlobalSettings,
                     txpGlobalSettings)
import           Pos.Generator.Block (BlockGenMode, BlockGenParams (..),
                     MonadBlockGenInit, genBlocks, tgpTxCountRange)
import           Pos.Util (HasLens', _neLast)
import           Test.Pos.Block.Logic.Mode (BlockProperty, BlockTestContext,
                     btcSlotIdL)

-- | Wrapper for 'bpGenBlocks' to clarify the meaning of the argument.
newtype EnableTxPayload = EnableTxPayload Bool

-- | Wrapper for 'bpGenBlocks' to clarify the meaning of the argument.
newtype InplaceDB = InplaceDB Bool

-- | Generate arbitrary valid blocks inside 'BlockProperty'. The first
-- argument specifies how many blocks should be generated. If it's
-- 'Nothing', the number of blocks will be generated by QuickCheck
-- engine.
genBlockGenParams
    :: ( HasGenesisData
       , HasAllSecrets ctx
       , MonadReader ctx m
       )
    => ProtocolMagic
    -> Maybe BlockCount
    -> EnableTxPayload
    -> InplaceDB
    -> PropertyM m BlockGenParams
genBlockGenParams pm blkCnt (EnableTxPayload enableTxPayload) (InplaceDB inplaceDB) = do
    allSecrets_ <- lift $ getAllSecrets
    let genStakeholders = gdBootStakeholders genesisData
    let genBlockGenParamsF s =
            pure
                BlockGenParams
                { _bgpSecrets = allSecrets_
                , _bgpBlockCount = fromMaybe (fromIntegral s) blkCnt
                , _bgpTxGenParams =
                      def & tgpTxCountRange %~ bool (const (0,0)) identity enableTxPayload
                , _bgpInplaceDB = inplaceDB
                , _bgpGenStakeholders = genStakeholders
                , _bgpSkipNoKey = False
                , _bgpTxpGlobalSettings = txpGlobalSettings pm (TxpConfiguration 200 Set.empty)
                }
    pick $ sized genBlockGenParamsF

-- | Generate and apply arbitrary valid blocks inside 'BlockProperty'. The first
-- argument specifies how many blocks should be generated. If it's
-- 'Nothing', the number of blocks will be generated by QuickCheck
-- engine.
bpGenBlocks
    :: ( MonadBlockGenInit ctx m
       , HasLens' ctx TxpGlobalSettings
       , Default (MempoolExt m)
       , MonadTxpLocal (BlockGenMode (MempoolExt m) m)
       , HasAllSecrets ctx
       )
    => ProtocolMagic
    -> TxpConfiguration
    -> Maybe BlockCount
    -> EnableTxPayload
    -> InplaceDB
    -> PropertyM m (OldestFirst [] Blund)
bpGenBlocks pm txpConfig blkCnt enableTxPayload inplaceDB = do
    params <- genBlockGenParams pm blkCnt enableTxPayload inplaceDB
    g <- pick $ MkGen $ \qc _ -> qc
    lift $ OldestFirst <$> evalRandT (genBlocks pm txpConfig params maybeToList) g

-- | A version of 'bpGenBlocks' which generates exactly one
-- block. Allows one to avoid unsafe functions sometimes.
bpGenBlock
    :: ( MonadBlockGenInit ctx m
       , HasLens' ctx TxpGlobalSettings
       , MonadTxpLocal (BlockGenMode (MempoolExt m) m)
       , HasAllSecrets ctx
       , Default (MempoolExt m)
       )
    => ProtocolMagic
    -> TxpConfiguration
    -> EnableTxPayload
    -> InplaceDB
    -> PropertyM m Blund
-- 'unsafeHead' is safe because we create exactly 1 block
bpGenBlock pm txpConfig = fmap (List.head . toList) ... bpGenBlocks pm txpConfig (Just 1)

getAllSecrets :: (MonadReader ctx m, HasAllSecrets ctx) => m AllSecrets
getAllSecrets = view allSecrets

-- | Go to arbitrary global state in 'BlockProperty'.
bpGoToArbitraryState :: BlockProperty ()
-- TODO: generate arbitrary blocks, apply them.
bpGoToArbitraryState = pass

-- | Perform action pretending current slot is the given one.
withCurrentSlot :: MonadReader BlockTestContext m => SlotId -> m a -> m a
withCurrentSlot slot = local (set btcSlotIdL $ Just slot)

-- | This simple helper is useful when one needs to verify
-- blocks. Blocks verification checks that blocks are not from
-- future. This function pretends that current slot is after the last
-- slot of the given blocks.
satisfySlotCheck
    :: ( HasProtocolConstants, MonadReader BlockTestContext m)
    => OldestFirst NE Block
    -> m a
    -> m a
satisfySlotCheck (OldestFirst blocks) action =
    let lastEpoch = blocks ^. _neLast . epochIndexL
    in withCurrentSlot (SlotId (lastEpoch + 1) minBound) action
