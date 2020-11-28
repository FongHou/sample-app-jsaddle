{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE CPP #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingVia #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE GeneralisedNewtypeDeriving #-}
{-# LANGUAGE OverloadedLabels #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StrictData #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}

module Main where

#ifndef __GHCJS__
import Language.Javascript.JSaddle.Warp as JSaddle ( run )
#else
import JavaScript.Web.XMLHttpRequest
#endif

import Api
import qualified Button
import Control.Lens
import Data.Aeson as JSON
import Data.Aeson.Encode.Pretty as JSON
import Data.Either
import Data.Proxy
import GHC.Generics (Generic)
import Miso
import Miso.String as S
import Servant.API
import Servant.Links

newtype Message = Message MisoString
  deriving newtype (Eq, Show)
  deriving (Generic)

instance ToJSON Message

instance FromJSON Message

data Model = Model
  { _uri :: !URI,
    _msg :: !Message,
    _received :: !MisoString,
    _leftButton :: !Button.Model,
    _value :: !Int,
    _rightButton :: !Button.Model
  }
  deriving (Eq, Show)

makeLenses ''Model

data Action
  = Router RouteAction
  | WSMsg WSMsg
  | LeftButtonAction Button.Action
  | RightButtonAction Button.Action
  | AddOne
  | SubtractOne
  | ManyClicksWarning !Int
  | NoOp
  deriving (Show, Eq)

data RouteAction
  = ChangeURI URI
  | HandleURI URI
  deriving (Show, Eq)

data WSMsg
  = ReceiveMsg (WebSocket Message)
  | SendMsg Message
  | UpdateMsg MisoString
  deriving (Show, Eq)

initialModel :: URI -> Model
initialModel uri =
  Model
    { _uri = uri,
      _msg = Message "",
      _received = mempty,
      _leftButton = Button.initialModel "-",
      _value = 0,
      _rightButton = Button.initialModel "+"
    }

updateModel :: Action -> Transition Action Model ()
updateModel action = case action of
  Router act -> toTransition (handleRoute act)
  WSMsg act -> toTransition (handleWebSocket act)
  LeftButtonAction act -> do
    -- Update the component's model, with whatever side effects it may have
    zoom leftButton $ Button.updateModel iLeftButton act
    pure ()
  RightButtonAction act -> do
    zoom rightButton $ Button.updateModel iRightButton act
    pure ()
  SubtractOne -> do
    value -= 1
  AddOne -> do
    value += 1
  ManyClicksWarning i -> scheduleIO_ $ do
    consoleLog "Ouch! You're clicking too many times!"
    consoleLog (ms i <> " is way too much for me to handle!")
  NoOp -> pure ()

handleRoute :: RouteAction -> Model -> Effect Action Model
handleRoute (HandleURI u) m =
  m {_uri = u} <# do
    pure NoOp
handleRoute (ChangeURI u) m =
  m <# do
    pushURI u
    pure NoOp

handleWebSocket :: WSMsg -> Model -> Effect Action Model
handleWebSocket (ReceiveMsg (WebSocketMessage (Message m))) model =
  noEff model {_received = m}
handleWebSocket (SendMsg m) model =
  model <# do
    let Message what = m
    x <- Api.query (fromMisoString what) Api.defaults{limit = Just 1}
    consoleLog $ ms $ show x
    send $ Message (toMisoString . JSON.encodePretty $ snd x)
    pure NoOp
handleWebSocket (UpdateMsg m) model =
  noEff model {_msg = Message m}
handleWebSocket _ model = noEff model

type Routes = About :<|> Home

type Home = View Action

type About = "about" :> View Action

routes = Proxy :: Proxy Routes

goAbout, goHome :: Action
(goHome, goAbout) = (goto routes home, goto routes about)
  where
    goto a b = Router $ ChangeURI (linkURI (safeLink a b))
    home = Proxy :: Proxy Home
    about = Proxy :: Proxy About

-- Call the component's `viewModel` where you want it to be drawn
viewModel :: Model -> View Action
viewModel m =
  div_
    [class_ "ui container"]
    [ div_
        [class_ "ui breadcrumb"]
        [ a_ [class_ "section", onClick goHome] [text "Home"],
          span_ [class_ "divider"] [text " | "],
          a_ [class_ "section", onClick goAbout] [text "About"]
        ],
      div_ [class_ "ui divider"] [],
      fromRight the404 $ runRoute routes handlers (^. uri) m
    ]
  where
    handlers = about :<|> home

home :: Model -> View Action
home Model {..} =
  div_
    [class_ "ui container"]
    [ input_
        [ class_ "ui attached segment input",
          type_ "text",
          onInput (WSMsg . UpdateMsg),
          onChange (WSMsg . SendMsg . Message)
        ],
      button_
        [ class_ "ui bottom attached button",
          onClick (WSMsg $ SendMsg _msg)
        ]
        [text "Send to echo server"],
      div_ [] [pre_ [] [text _received | not . S.null $ _received]]
    ]

about :: Model -> View Action
about m =
  div_
    []
    [ Button.viewModel iLeftButton $ m ^. leftButton,
      text $ m ^. value . to show . to ms,
      Button.viewModel iRightButton $ m ^. rightButton
    ]

-- Filling in the Interface values for both buttons
iLeftButton :: Button.Interface Action
iLeftButton =
  Button.Interface
    { Button.dispatch = LeftButtonAction,
      Button.click = SubtractOne,
      Button.manyClicks = ManyClicksWarning
    }

iRightButton :: Button.Interface Action
iRightButton =
  Button.Interface
    { Button.dispatch = RightButtonAction,
      Button.click = AddOne,
      Button.manyClicks = ManyClicksWarning
    }

the404 :: View Action
the404 =
  h4_ [] [ text "Nothing to see here :)" ]

#ifndef __GHCJS__
runApp :: JSM () -> IO ()
runApp = JSaddle.run 9090
#else
runApp :: IO () -> IO ()
runApp app = app
#endif

-- | Entry point for a miso application
main :: IO ()
main = runApp $ do
  currentURI <- getCurrentURI
  let model = initialModel currentURI
  startApp App {..}
  where
    initialAction = NoOp
    update = fromTransition . updateModel
    view = viewModel
    events = defaultEvents
    subs =
      [ uriSub (Router . HandleURI),
        websocketSub wss protocols (WSMsg . ReceiveMsg)
      ]
    wss = URL "wss://echo.websocket.org"
    protocols = Protocols []
    mountPoint = Nothing
    logLevel = Off
