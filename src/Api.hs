module Api where

import Control.Monad.IO.Class (MonadIO (liftIO))
import Data.Aeson (FromJSON, ToJSON, encode, object, (.=))
import Data.Text (Text)
import Data.Time (UTCTime)
import Db qualified
import Domain
import GHC.Generics (Generic)
import Hasql.Connection (Connection)
import Servant

data Env = Env
  { db :: Connection
  , currentTime :: IO UTCTime
  -- ^ getCurrentTime in production; a moveable clock in tests
  }

-- DTOs: the JSON shapes. The API and the domain can change independently.

data CreateReq = CreateReq
  { url :: Text
  , ttlSeconds :: Maybe Int
  }
  deriving stock (Generic)
  deriving anyclass (FromJSON)

data LinkInfo = LinkInfo
  { code :: Text
  , target :: Text
  , createdAt :: UTCTime
  , expiresAt :: Maybe UTCTime
  }
  deriving stock (Generic)
  deriving anyclass (ToJSON)

toInfo :: Domain.Link -> LinkInfo
toInfo link =
  LinkInfo
    { code = shortCodeText link.code
    , target = longUrlText link.target
    , createdAt = link.createdAt
    , expiresAt = link.expiresAt
    }

type API =
  "health" :> Get '[PlainText] Text
    :<|> "links" :> ReqBody '[JSON] CreateReq :> PostCreated '[JSON] LinkInfo
    :<|> "links" :> Capture "code" Text :> Get '[JSON] LinkInfo
    :<|> "links" :> Capture "code" Text :> DeleteNoContent
    :<|> Capture "code" Text
      :> Verb 'GET 302 '[PlainText] (Headers '[Header "Location" Text] NoContent)

server :: Env -> Server API
server env = health :<|> create :<|> info :<|> remove :<|> redirect
 where
  health = pure "ok"

  create req = do
    now <- liftIO env.currentTime
    case validateCreate now req.url req.ttlSeconds of
      Left err -> throwError (badRequest err)
      Right new -> toInfo <$> liftIO (Db.insertLink env.db now new)

  info raw = do
    sc <- parsecode raw
    found <- liftIO (Db.findLink env.db sc)
    maybe (throwError err404) (pure . toInfo) found

  remove raw = do
    sc <- parsecode raw
    deleted <- liftIO (Db.deleteLink env.db sc)
    if deleted then pure NoContent else throwError err404

  redirect raw = do
    sc <- parsecode raw
    now <- liftIO env.currentTime
    found <- liftIO (Db.findLink env.db sc)
    case resolve now found of
      NotFound -> throwError err404
      Expired -> throwError err410
      Redirect longUrl -> pure $ addHeader (longUrlText longUrl) NoContent

badRequest :: CreateError -> ServerError
badRequest e =
  err400
    { errBody = encode (object ["error" .= show e])
    , errHeaders = [("Content-Type", "application/json")]
    }

parsecode :: Text -> Handler ShortCode
parsecode = maybe (throwError err404) pure . parseShortCode
