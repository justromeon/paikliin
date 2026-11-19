module Cache (
  Entry,
  CacheTtl (..),
  cacheTtl,
  cacheGet,
  cachePut,
  cacheDelete,
) where

import Control.Exception (SomeException, try)
import Control.Monad (void)
import Data.Aeson (FromJSON, ToJSON, decodeStrict, encode)
import Data.ByteString (ByteString)
import Data.ByteString.Lazy qualified as LBS
import Data.List.NonEmpty qualified as NE
import Data.Text (Text)
import Data.Text.Encoding (encodeUtf8)
import Data.Time (UTCTime, diffUTCTime)
import Database.Redis qualified as Redis
import Domain
import GHC.Generics (Generic)

data Entry = Entry
  { target :: Text
  , createdAt :: UTCTime
  , expiresAt :: Maybe UTCTime
  }
  deriving stock (Generic)
  deriving anyclass (ToJSON, FromJSON)

key :: ShortCode -> ByteString
key sc = "link:" <> encodeUtf8 (shortCodeText sc)

data CacheTtl
  = DontCache
  | CacheFor Integer
  deriving stock (Eq, Show)

{- | how many seconds to keep a link in cache.
1 hour at most but never longer than link expiration
'Nothing' if it has already expired
-}
cacheTtl :: UTCTime -> Link -> CacheTtl
cacheTtl now link = case link.expiresAt of
  Nothing -> CacheFor oneHour
  Just expiration ->
    let secsBeforeExp = floor (diffUTCTime expiration now)
     in if secsBeforeExp <= 0 then DontCache else CacheFor (min oneHour secsBeforeExp)
 where
  oneHour = 3600

cachePut :: Redis.Connection -> UTCTime -> Link -> IO ()
cachePut r now link = case cacheTtl now link of
  DontCache -> pure ()
  CacheFor ttl ->
    ignoreErrors $
      Redis.runRedis r $
        Redis.setex (key link.code) ttl (LBS.toStrict $ encode entry)
 where
  entry = Entry (longUrlText $ link.target) link.createdAt link.expiresAt

ignoreErrors :: IO a -> IO ()
ignoreErrors = void . try @SomeException

cacheGet :: Redis.Connection -> ShortCode -> IO (Maybe Link)
cacheGet r sc = do
  result <- try @SomeException $ Redis.runRedis r $ Redis.get (key sc)
  pure $ case result of
    Right (Right (Just bytes)) -> toLink <$> decodeStrict bytes
    _ -> Nothing
 where
  toLink :: Entry -> Link
  toLink entry = Link sc (unsafeLongUrl entry.target) entry.createdAt entry.expiresAt

cacheDelete :: Redis.Connection -> ShortCode -> IO ()
cacheDelete r sc = ignoreErrors $ Redis.runRedis r $ Redis.del $ NE.singleton (key sc)
