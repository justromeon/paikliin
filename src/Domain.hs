module Domain (
  LongUrl,
  longUrlText,
  UrlError (..),
  parseLongUrl,
  ShortCode,
  shortCodeText,
  parseShortCode,
  encodeBase62,
  Link (..),
  NewLink (..),
  CreateError (..),
  validateCreate,
  Resolution (..),
  resolve,
) where

import Data.Bifunctor (Bifunctor (first))
import Data.Char (isAlphaNum, isAscii)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (NominalDiffTime, UTCTime, addUTCTime)
import Data.Word (Word64)

-- Long URLs

newtype LongUrl = LongUrl Text
  deriving stock (Eq, Show)

longUrlText :: LongUrl -> Text
longUrlText (LongUrl t) = t

data UrlError
  = EmptyUrl
  | UrlTooLong
  | NotHttp
  deriving stock (Eq, Show)

parseLongUrl :: Text -> Either UrlError LongUrl
parseLongUrl raw
  | T.null trimmed = Left EmptyUrl
  | T.length trimmed > 2048 = Left UrlTooLong
  | any (`T.isPrefixOf` trimmed) ["http://", "https://"] = Right (LongUrl trimmed)
  | otherwise = Left NotHttp
 where
  trimmed = T.strip raw

-- Short Codes

newtype ShortCode = ShortCode Text
  deriving stock (Eq, Show)

shortCodeText :: ShortCode -> Text
shortCodeText (ShortCode t) = t

alphabet :: Text
alphabet = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"

encodeBase62 :: Word64 -> ShortCode
encodeBase62 n = ShortCode (T.pack $ encode n "")
 where
  encode x acc
    | x < 62 = digit x : acc
    | otherwise = encode (x `div` 62) (digit (x `mod` 62) : acc)
  digit = T.index alphabet . fromIntegral

parseShortCode :: Text -> Maybe ShortCode
parseShortCode t
  | T.length t >= 1 && T.length t <= 11 && T.all valid t = Just (ShortCode t)
  | otherwise = Nothing
 where
  valid c = isAscii c && isAlphaNum c

-- Links

data Link = Link
  { code :: ShortCode
  , target :: LongUrl
  , createdAt :: UTCTime
  , expiresAt :: Maybe UTCTime
  }
  deriving stock (Eq, Show)

-- | A validated request to create a link. It has no code yet, because the database assigns the id.
data NewLink = NewLink
  { target :: LongUrl
  , expiresAt :: Maybe UTCTime
  }
  deriving stock (Eq, Show)

data CreateError
  = BadUrl UrlError
  | BadTtl
  deriving stock (Eq, Show)

maxTtl :: NominalDiffTime
maxTtl = 365 * 24 * 60 * 60

validateCreate :: UTCTime -> Text -> Maybe Int -> Either CreateError NewLink
validateCreate now rawUrl mTtl = do
  target <- first BadUrl (parseLongUrl rawUrl)
  expires <- traverse toExpiry mTtl
  pure (NewLink target expires)
 where
  toExpiry secs
    | secs < 1 || fromIntegral secs > maxTtl = Left BadTtl
    | otherwise = Right $ addUTCTime (fromIntegral secs) now

data Resolution
  = Redirect LongUrl
  | Expired
  | NotFound
  deriving stock (Eq, Show)

resolve :: UTCTime -> Maybe Link -> Resolution
resolve _ Nothing = NotFound
resolve now (Just link) = case link.expiresAt of
  Just t | t <= now -> Expired
  _ -> Redirect link.target
