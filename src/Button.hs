{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

module Button
  ( -- Note: No constructors are exported
    Model,
    Action,
    initialModel,
    Interface (..),
    updateModel,
    viewModel,
  )
where

import Control.Lens (makeLenses, use, (+=), (.=), (^.))
import Control.Monad (when)
import Data.Monoid ((<>))
import Miso
import Miso.String

-- Internal state
data Model = Model
  { _mDownState :: !Bool,
    _mText :: !MisoString,
    _mEnterCount :: !Int
  }
  deriving (Eq, Show)

-- Some lenses
makeLenses ''Model

-- Demand a button text from above,
-- use defaults for the rest
initialModel :: MisoString -> Model
initialModel txt =
  Model
    { _mDownState = False,
      _mText = txt,
      _mEnterCount = 0
    }

-- Actions interface
-- These actions are interesting for the parent
data Interface action = Interface
  { -- dispatch to channel Actions back to this component
    dispatch :: Action -> action,
    -- Two events that the parent should do something with
    click :: action,
    manyClicks :: Int -> action
  }

data Action
  = MouseDown
  | MouseUp
  deriving (Show, Eq)

-- Note the polymorphism in `action`
-- This `action` will be filled in to become the parent's `Action`
-- Also note that this is the Transition monad, rather than the Effect monad
-- See the documentation for the Transition monad in miso's Haddock.
updateModel :: Interface action -> Action -> Transition action Model ()
updateModel iface action = case action of
  MouseDown -> do
    mDownState .= True
    mEnterCount += 1
    enterCount <- use mEnterCount
    when (enterCount == 10) $
      Miso.scheduleIO $ pure $ manyClicks iface enterCount
  MouseUp ->
    mDownState .= False

-- Same pattern as the `update` function
viewModel :: Interface action -> Model -> View action
viewModel iface m =
  button_
    [ onClick $ click iface,
      onMouseDown $ dispatch iface MouseDown,
      onMouseUp $ dispatch iface MouseUp
    ]
    [ if m ^. mDownState
        then text $ "~" <> m ^. mText <> "~"
        else text $ m ^. mText
    ]
