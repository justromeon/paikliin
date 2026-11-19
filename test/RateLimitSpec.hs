module RateLimitSpec (spec) where

import Data.Time
import RateLimit
import Test.Hspec

t0 :: UTCTime
t0 = UTCTime (fromGregorian 2026 1 1) 0 -- exactly on a minute boundary

spec :: Spec
spec = do
  describe "clientIp" $ do
    it "uses the header's address" $
      clientIp (Just "203.0.113.7") `shouldBe` "203.0.113.7"
    it "uses the last entry of a list" $
      clientIp (Just "198.51.100.1, 203.0.113.7") `shouldBe` "203.0.113.7"
    it "falls back without the header" $
      clientIp Nothing `shouldBe` "unknown"

  describe "windowKey" $ do
    it "is the same within a minute" $
      windowKey "a" t0 `shouldBe` windowKey "a" (addUTCTime 59 t0)
    it "changes in the next minute" $
      windowKey "a" t0 `shouldNotBe` windowKey "a" (addUTCTime 60 t0)

  describe "decide" $ do
    it "allows up to the limit" $
      decide t0 10 `shouldBe` Allow
    it "rejects past the limit until the minute ends" $
      decide t0 11 `shouldBe` Reject 60
    it "counts down within the minute" $
      decide (addUTCTime 15 t0) 11 `shouldBe` Reject 45
