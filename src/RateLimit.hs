module RateLimit (Decision (..), clientIp, windowKey, decide, countRequest) where

import Control.Exception (SomeException, try)
import Data.ByteString (ByteString)
import Data.ByteString.Char8 qualified as BS8
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (encodeUtf8)
import Data.Time (UTCTime)
import Data.Time.Clock.POSIX (utcTimeToPOSIXSeconds)
import Database.Redis qualified as Redis

data Decision = Allow | Reject Integer -- seconds until the window resets
  deriving stock (Eq, Show)

linksPerMinute :: Integer
linksPerMinute = 10

{- | The client's address, from the X-Forwarded-For header.
The header may hold a list, "a, b"; the last entry is the one our own
proxy added, so use that, without surrounding spaces.
No header means the request didn't come through Caddy: return "unknown".
-}
clientIp :: Maybe Text -> Text
clientIp Nothing = "unknown"
clientIp (Just h) = T.strip $ snd (T.breakOnEnd "," h)

{- | One counter per client per minute, e.g. "ratelimit:203.0.113.7:29745412".
A new minute means a new key, so the count starts again from zero.
-}
windowKey :: Text -> UTCTime -> ByteString
windowKey client now = "ratelimit:" <> encodeUtf8 client <> ":" <> BS8.pack (show (minute now))

minute :: UTCTime -> Integer
minute now = floor (utcTimeToPOSIXSeconds now) `div` 60

decide :: UTCTime -> Integer -> Decision
decide now count
  | count <= linksPerMinute = Allow
  | otherwise = Reject (60 - floor (utcTimeToPOSIXSeconds now) `mod` 60)

{- | Add one to the counter and return the new count. The key expires after
two minutes, so old windows clean themselves up. Nothing if Redis fails.
-}
countRequest :: Redis.Connection -> ByteString -> IO (Maybe Integer)
countRequest r key = do
  res <- try @SomeException $ Redis.runRedis r $ do
    n <- Redis.incr key
    _ <- Redis.expire key 120
    pure n
  pure $ case res of
    Right (Right n) -> Just n
    _ -> Nothing
