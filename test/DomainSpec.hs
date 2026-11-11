module DomainSpec where

import Data.Maybe (isJust)
import Data.Text qualified as T
import Data.Time (UTCTime (UTCTime), addUTCTime, fromGregorian)
import Domain
import Test.Hspec (Spec, describe, it, shouldBe)
import Test.Hspec.QuickCheck (prop)
import Test.QuickCheck ((==>))

t0 :: UTCTime
t0 = UTCTime (fromGregorian 2026 1 1) 0

spec :: Spec
spec = do
  describe "parseLongUrl" $ do
    it "accepts and trims an https URL" $
      longUrlText <$> parseLongUrl "  https://example.com/a  "
        `shouldBe` Right "https://example.com/a"
    it "rejects blank input" $
      parseLongUrl "   " `shouldBe` Left EmptyUrl
    it "rejects other schemas" $
      parseLongUrl "ftp://x.org" `shouldBe` Left NotHttp
    it "rejects very long URLs" $
      parseLongUrl ("https://" <> T.replicate 2050 "a") `shouldBe` Left UrlTooLong

  describe "encodeBase62" $ do
    it "encodes known values" $
      map (shortCodeText . encodeBase62) [0, 9, 10, 61, 62, 100000]
        `shouldBe` ["0", "9", "a", "Z", "10", "q0U"]
    prop "always produce a parseable code" $ \n ->
      isJust . parseShortCode . shortCodeText $ encodeBase62 n
    prop "different ids give different code" $ \a b ->
      a /= b ==> encodeBase62 a /= encodeBase62 b

  describe "parseShortCode" $ do
    it "rejects empty and too-long codes" $ do
      parseShortCode "" `shouldBe` Nothing
      parseShortCode (T.replicate 12 "a") `shouldBe` Nothing
    it "rejects non-alphanumeric characters" $
      parseShortCode "ab-c" `shouldBe` Nothing

  describe "validateCreate" $ do
    it "computes the expiry from now" $
      (.expiresAt) <$> validateCreate t0 "https://a.io" (Just 60)
        `shouldBe` Right (Just $ addUTCTime 60 t0)
    it "rejects a zero TTL" $
      validateCreate t0 "https://a.io" (Just 0) `shouldBe` Left BadTtl
    it "reports bad URLs" $
      validateCreate t0 "bad-url" Nothing `shouldBe` Left (BadUrl NotHttp)

  describe "resolve" $ do
    let url = either (error . show) id (parseLongUrl "https://a.io")
        link expiry = Link (encodeBase62 1) url t0 expiry
    it "is NotFound without a Link" $
      resolve t0 Nothing `shouldBe` NotFound
    it "redirects when no expiry" $
      resolve t0 (Just $ link Nothing) `shouldBe` Redirect url
    it "redirects before expiry" $
      resolve t0 (Just $ link $ Just $ addUTCTime 1 t0) `shouldBe` Redirect url
    it "is expired exactly at the expiry time" $
      resolve t0 (Just $ link $ Just t0) `shouldBe` Expired
