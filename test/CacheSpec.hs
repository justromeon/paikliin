module CacheSpec (spec) where

import Cache
import Data.Time (UTCTime (UTCTime), addUTCTime, fromGregorian)
import Domain
import Test.Hspec (Spec, describe, it, shouldBe)

t0 :: UTCTime
t0 = UTCTime (fromGregorian 2026 1 1) 0

spec :: Spec
spec = do
  describe "cacheTtl" $ do
    let url = either (error . show) id (parseLongUrl "https://a.io")
        link expiry = Link (encodeBase62 1) url t0 expiry
    it "caps at one hour" $ do
      cacheTtl t0 (link Nothing) `shouldBe` CacheFor 3600
    it "never outlives the link" $ do
      cacheTtl t0 (link $ Just $ addUTCTime 60 t0) `shouldBe` CacheFor 60
    it "doesn't change expired links" $ do
      cacheTtl t0 (link $ Just t0) `shouldBe` DontCache
